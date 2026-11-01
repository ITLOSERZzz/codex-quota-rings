[CmdletBinding()]
param([string]$NodePath, [string]$OutputDirectory)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $script:PackageRoot 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$package = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:PackageRoot 'package.json') | ConvertFrom-Json
$version = $package.version
$runtimeVersion = (& $NodePath -p 'process.version')
$runtimeArch = (& $NodePath -p 'process.arch')
if ($runtimeVersion -ne 'v24.16.0' -or $runtimeArch -ne 'x64') { throw 'Use Node.js v24.16.0 win-x64 so the bundled runtime and its audited license match.' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$stagingParent = Join-Path $OutputDirectory ('stage-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $stagingParent "CodexQuotaRings-$version-win-x64"
[IO.Directory]::CreateDirectory($stage) | Out-Null
$entries = @('src','scripts','assets','third-party','.codex-plugin','.agents','package.json','.mcp.json','LICENSE','README.md','README.en.md','SECURITY.md','THIRD_PARTY_NOTICES.md','REFERENCE-RESEARCH.md','CHANGELOG.md','Install.cmd','Uninstall.cmd','Check.cmd')
foreach ($entry in $entries) {
    $source = Join-Path $script:PackageRoot $entry
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release file: $entry" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $entry) -Recurse -Force
}
$runtime = Join-Path $stage 'runtime'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Copy-Item -LiteralPath $NodePath -Destination (Join-Path $runtime 'node.exe')
Copy-Item -LiteralPath (Join-Path $script:PackageRoot 'third-party\Node-LICENSE.txt') -Destination (Join-Path $runtime 'LICENSE.txt')
$hashes = @{}
Get-ChildItem -LiteralPath $stage -Recurse -File -Force | ForEach-Object {
    $relative = $_.FullName.Substring($stage.Length + 1).Replace('\','/')
    $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
Write-QuotaJson (Join-Path $stage 'package-hashes.json') $hashes
$zip = Join-Path $OutputDirectory "CodexQuotaRings-$version-win-x64.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip + '.sha256'), ($hash + '  ' + [IO.Path]::GetFileName($zip) + "`n"), $script:Utf8)
Write-Output $zip
Write-Output ($zip + '.sha256')
