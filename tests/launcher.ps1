$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('test-results\launcher-' + [guid]::NewGuid().ToString('N'))
$scripts = Join-Path $fixture 'package\scripts'
[IO.Directory]::CreateDirectory($scripts) | Out-Null
foreach ($name in @('common.ps1','launch.ps1')) { Copy-Item -LiteralPath (Join-Path $root ('scripts\' + $name)) -Destination $scripts }
$record = Join-Path $fixture 'events.jsonl'
$node = (Get-Command node.exe).Source
$common = Join-Path $scripts 'common.ps1'
# The real launcher runs, but all desktop-start and helper-start actions are replaced.
# The existing real Codex session and desktop are never touched by this test.
$stubs = @'
$script:FakeRunningReads=0
$script:FakeWatchReads=0
function Resolve-QuotaNode { return $env:CODEX_QUOTA_TEST_NODE }
function Get-QuotaDesktopInfo { return [pscustomobject]@{Path='C:\synthetic\ChatGPT.exe';AppUserModelId=$null} }
function Get-QuotaRunningCodex {
 # Includes a synthetic worker that stays alive after the main process exits.
 [pscustomobject]@{Id=123;Path='C:\synthetic\ChatGPT.exe'}
 [pscustomobject]@{Id=124;Path='C:\synthetic\ChatGPT.exe'}
}
function Get-QuotaMainCodex {
 if($script:FakeWatchReads -le 2) { return [pscustomobject]@{Id=123;Path='C:\synthetic\ChatGPT.exe'} }
 if($env:CODEX_QUOTA_TEST_REPLACEMENT -eq '1') { return [pscustomobject]@{Id=456;Path='C:\synthetic\ChatGPT.exe'} }
}
function Get-QuotaExitWatchers {
 $watcher=[pscustomobject]@{Id=123}
 $watcher | Add-Member ScriptProperty HasExited { $script:FakeWatchReads++; return $script:FakeWatchReads -gt 2 }
 $watcher | Add-Member ScriptMethod Dispose { }
 return $watcher
}
function Start-QuotaCodex {
 [IO.File]::AppendAllText($env:CODEX_QUOTA_TEST_EVENTS,"desktop-started`n")
 return $PID
}
function Test-QuotaDebugPort { return $true }
function Start-QuotaHelper {
 [IO.File]::AppendAllText($env:CODEX_QUOTA_TEST_EVENTS,"helper-started`n")
 $child = [pscustomobject]@{ Synthetic=$true }
 $child | Add-Member ScriptMethod WaitForExit { [IO.File]::AppendAllText($env:CODEX_QUOTA_TEST_EVENTS,"helper-exited`n") }
 return $child
}
'@
$original = Get-Content -LiteralPath $common -Raw -Encoding UTF8
[IO.File]::WriteAllText($common,($original + "`n" + $stubs),(New-Object Text.UTF8Encoding($true)))
$src = Join-Path $fixture 'package\src'
[IO.Directory]::CreateDirectory($src) | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'cli.mjs'), 'console.log(JSON.stringify({running:false}));')
$env:CODEX_QUOTA_STATE_DIR = Join-Path $fixture 'state'
$env:CODEX_QUOTA_TEST_EVENTS = $record
$env:CODEX_QUOTA_TEST_NODE = $node
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'launch.ps1') -Quiet
if ($LASTEXITCODE -ne 0) { throw 'Launcher failed to wait for a normal exit' }
$events = @(Get-Content -LiteralPath $record)
if ($events.Count -ne 2 -or $events[0] -ne 'desktop-started' -or $events[1] -ne 'helper-started') { throw 'Launch order or count is incorrect' }
$state = Get-Content -LiteralPath (Join-Path $env:CODEX_QUOTA_STATE_DIR 'launch-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.phase -ne 'helper-started') { throw 'Launch status missing' }
# Cancellation must not return "exited" or restart anything.
. (Join-Path $root 'scripts\common.ps1')
$lock = New-Object Threading.Mutex($false,(Get-QuotaLaunchControlName))
try {
    if (-not $lock.WaitOne(0)) { throw 'Fixture lock unavailable' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'launch.ps1') -Quiet
    if ($LASTEXITCODE -ne 0 -or @(Get-Content -LiteralPath $record).Count -ne 2) { throw 'Duplicate launcher started another desktop/helper' }
} finally { $lock.ReleaseMutex(); $lock.Dispose() }
$namedCancel = New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,((Get-QuotaLaunchControlName) + '-cancel'))
try { Stop-QuotaLauncher; if (-not $namedCancel.WaitOne(0)) { throw 'Upgrade/uninstall did not signal cancellation' } }
finally { $namedCancel.Dispose() }
$cancel = New-Object Threading.EventWaitHandle($true,[Threading.EventResetMode]::ManualReset)
try { if ((Wait-QuotaDesktopExit $cancel 1) -ne 'cancelled') { throw 'Cancelled launcher continued' } }
finally { $cancel.Dispose() }
$pending = New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset)
try { if ((Wait-QuotaDesktopExit $pending 0) -ne 'wait-expired') { throw 'Expired launcher continued' } }
finally { $pending.Dispose() }
[IO.File]::WriteAllText($record,'')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'launch.ps1') -Quiet -KeepAlive
if ($LASTEXITCODE -ne 0) { throw 'Scheduled parent failed to wait for its helper' }
$events = @(Get-Content -LiteralPath $record)
if ($events.Count -ne 3 -or $events[2] -ne 'helper-exited') { throw 'Scheduled parent did not wait for helper exit' }
$state = Get-Content -LiteralPath (Join-Path $env:CODEX_QUOTA_STATE_DIR 'launch-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.phase -ne 'helper-exited' -or -not $state.launcherPid -or -not $state.launcherStartedAt) { throw 'Launcher lifetime status missing' }
[IO.File]::WriteAllText($record,'')
$env:CODEX_QUOTA_TEST_REPLACEMENT='1'
try {
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'launch.ps1') -Quiet
 if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $record).Length -ne 0) { throw 'Replacement ordinary desktop was restarted' }
 $state=Get-Content -LiteralPath (Join-Path $env:CODEX_QUOTA_STATE_DIR 'launch-state.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($state.phase -ne 'ordinary-relaunch-detected') { throw 'Replacement launch was not reported' }
} finally { $env:CODEX_QUOTA_TEST_REPLACEMENT=$null }
Write-Output 'PASS: original main-process exit despite lingering worker; replacement is not restarted; duplicate/cancel/expiry guards; scheduled helper lifetime.'
