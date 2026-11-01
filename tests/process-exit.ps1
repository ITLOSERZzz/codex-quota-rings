$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\common.ps1')
$fixture=Join-Path $root ('test-results\process-exit-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$env:CODEX_QUOTA_STATE_DIR=Join-Path $fixture 'state'
$script:StateRoot=$env:CODEX_QUOTA_STATE_DIR
$node=(Get-Command node.exe).Source
$worker=Join-Path $fixture 'worker.mjs'
$workerCode=@'
setTimeout(()=>process.exit(0),process.argv[2]==='main'?1800:9000);
'@
[IO.File]::WriteAllText($worker,$workerCode,(New-Object Text.UTF8Encoding($false)))
$script:TestMain=$null
$child=$null
$cancel=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset)
try {
 # Separate owned processes reproduce an exited main with a still-live worker.
 # Worker classification is checked independently below with real Electron args.
 $child=Start-Process -FilePath $node -ArgumentList @(('"'+$worker+'"'),'worker') -WindowStyle Hidden -PassThru
 $script:TestMain=Start-Process -FilePath $node -ArgumentList @(('"'+$worker+'"'),'main') -WindowStyle Hidden -PassThru
 function Get-QuotaMainCodex { if(-not $script:TestMain.HasExited){[pscustomobject]@{Id=$script:TestMain.Id;Path=$node}} }
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $result=Wait-QuotaDesktopExit $cancel 6
 $clock.Stop()
 if($result -ne 'exited'){throw ('Main exit not detected: '+$result)}
 if($child.HasExited){throw 'Owned worker must still be running when the main exit is detected'}
 if($clock.Elapsed.TotalSeconds -gt 5){throw 'Waited for workers instead of the main process'}
 $items=@(
  [pscustomobject]@{ProcessId=1;ExecutablePath='C:\app\ChatGPT.exe';CommandLine='ChatGPT.exe'},
  [pscustomobject]@{ProcessId=2;ExecutablePath='C:\app\ChatGPT.exe';CommandLine='ChatGPT.exe --type=renderer'},
  [pscustomobject]@{ProcessId=3;ExecutablePath='C:\app\ChatGPT.exe';CommandLine='ChatGPT.exe --type=crashpad-handler'},
  [pscustomobject]@{ProcessId=4;ExecutablePath='C:\cli\codex.exe';CommandLine='codex.exe'}
 )
 $selected=@(Select-QuotaMainProcesses $items @('C:\app\ChatGPT.exe'))
 if($selected.Count -ne 1 -or $selected[0].Id -ne 1){throw 'Subprocess or unrelated CLI was selected as main'}
 Write-Output 'PASS: actual owned Node main exits while another owned worker stays alive; exit detected promptly; renderer/crashpad/CLI excluded.'
} finally {
 $cancel.Dispose()
 # These handles refer only to the two Node processes created by this test.
 foreach($ownedProcess in @($script:TestMain,$child)) {
  if($ownedProcess){try{if(-not $ownedProcess.HasExited){$ownedProcess.Kill();$ownedProcess.WaitForExit()}}finally{$ownedProcess.Dispose()}}
 }
}
