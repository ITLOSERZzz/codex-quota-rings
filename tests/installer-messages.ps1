$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\install.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Installer parse error' }
$success = @($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Show-QuotaMessage' -and $node.Extent.Text.Contains('安装完成')
}, $true))
if ($success.Count -ne 1) { throw 'Success message call not found' }
# Execute the real call through PowerShell's parser and parameter binder, without
# opening a modal dialog on the user's desktop. The old smart-quote call fails here.
$global:CapturedQuotaMessage = $null
function Show-QuotaMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Text, [ValidateSet('Information','Warning','Error')][string]$Kind='Information')
    $global:CapturedQuotaMessage = @{Text=$Text;Kind=$Kind}
}
& ([scriptblock]::Create($success[0].Extent.Text))
if ($global:CapturedQuotaMessage.Kind -ne 'Information' -or -not $global:CapturedQuotaMessage.Text.Contains('Codex 额度') -or -not $global:CapturedQuotaMessage.Text.Contains('以后使用')) { throw 'The full success text was not bound as one parameter' }
Add-Type -AssemblyName PresentationFramework
$signature = [type[]]@([string],[string],[System.Windows.MessageBoxButton],[System.Windows.MessageBoxImage])
if (-not [System.Windows.MessageBox].GetMethod('Show',$signature)) { throw 'WPF message overload unavailable' }
# Install a test-only copy with a recording dialog sink. This exercises the
# actual non-Quiet installer path, including file copy and shortcut creation.
$fixture = Join-Path $root ('test-results\messages-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $fixture 'package'
[IO.Directory]::CreateDirectory($package) | Out-Null
foreach ($entry in @('src','scripts','package.json')) { Copy-Item -LiteralPath (Join-Path $root $entry) -Destination (Join-Path $package $entry) -Recurse }
$common = Join-Path $package 'scripts\common.ps1'
$commonText = Get-Content -LiteralPath $common -Raw -Encoding UTF8
$commonAst = [Management.Automation.Language.Parser]::ParseInput($commonText,[ref]$tokens,[ref]$parseErrors)
$function = $commonAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-QuotaMessage'},$true)
$sink = @'
function Show-QuotaMessage {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$Text,[ValidateSet('Information','Warning','Error')][string]$Kind='Information')
 [IO.File]::WriteAllText($env:CODEX_QUOTA_TEST_MESSAGE_FILE,(@{Text=$Text;Kind=$Kind}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
}
'@
$commonText = $commonText.Substring(0,$function.Extent.StartOffset) + $sink + $commonText.Substring($function.Extent.EndOffset)
[IO.File]::WriteAllText($common,$commonText,(New-Object Text.UTF8Encoding($true)))
$fakeApp = Join-Path $fixture 'fake-app'
[IO.Directory]::CreateDirectory((Join-Path $fakeApp 'resources')) | Out-Null
[IO.File]::WriteAllBytes((Join-Path $fakeApp 'ChatGPT.exe'),[byte[]]@(1,2,3))
[IO.File]::WriteAllText((Join-Path $fakeApp 'resources\app.asar'),'test fixture, never executed')
$env:CODEX_QUOTA_TEST_MESSAGE_FILE = Join-Path $fixture 'message.json'
$env:CODEX_QUOTA_STATE_DIR = Join-Path $fixture 'state'
$destination = Join-Path $fixture 'installed'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -InstallRoot $destination -DesktopDirectory (Join-Path $fixture 'desktop') -CodexPath (Join-Path $fakeApp 'ChatGPT.exe') -NoLaunch -SkipTaskRegistration
if ($LASTEXITCODE -ne 0) { throw 'Non-Quiet installer failed' }
$message = Get-Content -LiteralPath $env:CODEX_QUOTA_TEST_MESSAGE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
if ($message.Kind -ne 'Information' -or -not $message.Text.Contains('Codex 额度')) { throw 'Non-Quiet installer sent an error or split success message' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'scripts\uninstall.ps1') -Quiet
if ($LASTEXITCODE -ne 0) { throw 'Fixture cleanup failed' }
Write-Output 'PASS: real success-message binding, WPF signature, non-Quiet install and cleanup.'
