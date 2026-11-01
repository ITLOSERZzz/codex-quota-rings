$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('test-results\installer test 中文 ' + [guid]::NewGuid().ToString('N'))
$appRoot = Join-Path $testRoot 'fake-desktop'
[IO.Directory]::CreateDirectory((Join-Path $appRoot 'resources')) | Out-Null
[IO.File]::WriteAllBytes((Join-Path $appRoot 'ChatGPT.exe'), [byte[]]@(1,2,3))
[IO.File]::WriteAllText((Join-Path $appRoot 'resources\app.asar'), 'synthetic test fixture, never executed')
$installation = Join-Path $testRoot 'installed'
$desktop = Join-Path $testRoot 'desktop'
$env:CODEX_QUOTA_STATE_DIR = Join-Path $testRoot 'state'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\install.ps1') -InstallRoot $installation -DesktopDirectory $desktop -CodexPath (Join-Path $appRoot 'ChatGPT.exe') -Quiet -NoLaunch -SkipTaskRegistration
if ($LASTEXITCODE -ne 0) { throw 'Installer failed' }
$marker = Join-Path $installation 'installation.json'
if (-not (Test-Path -LiteralPath $marker)) { throw 'Ownership marker missing' }
if (-not (Test-Path -LiteralPath (Join-Path $desktop 'Codex 额度.lnk'))) { throw 'Desktop shortcut missing' }
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $marker | ConvertFrom-Json
if ($manifest.id -ne 'codex-quota-rings') { throw 'Invalid installation identity' }
$userFile = Join-Path $installation 'keep-my-file.txt'
[IO.File]::WriteAllText($userFile, 'must survive uninstall')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installation 'scripts\uninstall.ps1') -Quiet
if ($LASTEXITCODE -ne 0) { throw 'Uninstaller failed' }
if (-not (Test-Path -LiteralPath $userFile)) { throw 'Uninstaller removed a user file' }
if (Test-Path -LiteralPath $marker) { throw 'Ownership marker was not removed' }
if (Test-Path -LiteralPath (Join-Path $desktop 'Codex 额度.lnk')) { throw 'Owned shortcut was not removed' }
Write-Output 'PASS: Windows PowerShell 5.1 install, shortcut, uninstall, user-file preservation.'
