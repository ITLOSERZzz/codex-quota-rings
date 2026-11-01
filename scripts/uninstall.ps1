[CmdletBinding()]
param([switch]$Quiet)
. (Join-Path $PSScriptRoot 'common.ps1')
try {
    $root = [IO.Path]::GetFullPath($script:PackageRoot).TrimEnd('\')
    $marker = Join-Path $root 'installation.json'
    if (-not (Test-Path -LiteralPath $marker)) { throw '这里不是已安装的程序目录。请从安装目录运行 Uninstall.cmd。' }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $marker | ConvertFrom-Json
    if ($manifest.id -ne 'codex-quota-rings' -or $manifest.installRoot -ne $root -or $root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')) { throw '安装归属校验失败，未删除任何文件。' }
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安装路径已被替换成链接，拒绝卸载。' }
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force)) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安装目录内包含链接，拒绝卸载。' }
    }
    $targets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in $manifest.files) {
        if ([IO.Path]::IsPathRooted($relative)) { throw '卸载清单含有绝对路径。' }
        $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '卸载清单超出安装目录。' }
        if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '卸载文件被替换成链接。' }
        $targets.Add($target)
    }
    Stop-QuotaLauncher
    $node = Resolve-QuotaNode
    & $node (Join-Path $root 'src\cli.mjs') stop 2>$null | Out-Null
    Start-Sleep -Milliseconds 1800
    if ($manifest.PSObject.Properties['scheduledTaskName'] -and $manifest.scheduledTaskName) {
        . (Join-Path $PSScriptRoot 'task-runner.ps1')
        Remove-QuotaLaunchTask $root
    }
    if (Test-Path -LiteralPath $manifest.shortcut) {
        $link = Read-QuotaShortcut $manifest.shortcut
        if (Test-QuotaShortcut $link $root) { Remove-Item -LiteralPath $manifest.shortcut -Force }
    }
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    }
    Remove-Item -LiteralPath $marker -Force
    # Remove only empty directories; preserve any files the user added.
    Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if (-not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and @(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -eq 0) { Remove-Item -LiteralPath $root -Force }
    if (-not $Quiet) { Show-QuotaMessage -Text '已卸载双环扩展。Codex 及其账户、聊天、项目均未改动。' }
} catch {
    if ($Quiet) { Write-Error $_.Exception.Message } else { Show-QuotaMessage -Text $_.Exception.Message -Kind 'Error' }
    exit 1
}
