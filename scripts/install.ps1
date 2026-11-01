[CmdletBinding()]
param([string]$InstallRoot, [string]$DesktopDirectory, [string]$CodexPath, [switch]$Quiet, [switch]$NoLaunch, [switch]$SkipTaskRegistration)
. (Join-Path $PSScriptRoot 'common.ps1')
try {
    if (-not $InstallRoot) { $InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\CodexQuotaRings' }
    if (-not $DesktopDirectory) { $DesktopDirectory = [Environment]::GetFolderPath('Desktop') }
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $DesktopDirectory = [IO.Path]::GetFullPath($DesktopDirectory)
    if ($InstallRoot -eq [IO.Path]::GetPathRoot($InstallRoot).TrimEnd('\')) { throw '安装目录不能是磁盘根目录。' }
    $hashFile = Join-Path $script:PackageRoot 'package-hashes.json'
    if (Test-Path -LiteralPath $hashFile) {
        $hashes = Get-Content -Raw -Encoding UTF8 -LiteralPath $hashFile | ConvertFrom-Json
        $packagePrefix = [IO.Path]::GetFullPath($script:PackageRoot).TrimEnd('\') + '\'
        foreach ($property in $hashes.PSObject.Properties) {
            $payloadPath = [IO.Path]::GetFullPath((Join-Path $script:PackageRoot $property.Name))
            if (-not $payloadPath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) { throw '安装包文件清单无效或缺少文件。' }
            if ((Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash -ne $property.Value) { throw '安装包文件校验失败，请重新下载完整 Release。' }
        }
    }
    if (Test-Path -LiteralPath $InstallRoot) {
        $directoryInfo = Get-Item -LiteralPath $InstallRoot -Force
        if ($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '不能安装到目录链接。' }
        $ownershipFile = Join-Path $InstallRoot 'installation.json'
        if ((Get-ChildItem -LiteralPath $InstallRoot -Force | Measure-Object).Count -gt 0 -and -not (Test-Path -LiteralPath $ownershipFile)) { throw '安装目录已有其他文件，请选择一个空目录。' }
        if (Test-Path -LiteralPath $ownershipFile) {
            $old = Get-Content -Raw -Encoding UTF8 -LiteralPath $ownershipFile | ConvertFrom-Json
            if ($old.id -ne 'codex-quota-rings' -or $old.installRoot -ne $InstallRoot) { throw '安装目录不属于本程序。' }
        }
    }
    $node = Resolve-QuotaNode
    $nodeVersion = (& $node -p 'process.versions.node')
    if ([version]$nodeVersion -lt [version]'22.5.0') { throw '需要 Node.js 22.5 或更新运行时。请下载完整 Release 包。' }
    $info = Get-QuotaDesktopInfo $CodexPath
    if (-not $info -and -not $Quiet) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = '选择 Codex Desktop 的 ChatGPT.exe 或 Codex.exe'
        $dialog.Filter = 'Codex Desktop|ChatGPT.exe;Codex.exe'
        if ($dialog.ShowDialog() -eq 'OK') { $info = Get-QuotaDesktopInfo $dialog.FileName }
    }
    if (-not $info) { throw '未找到 Codex Desktop。可用 -CodexPath 指定应用路径。' }
    Stop-QuotaLauncher
    & $node (Join-Path $script:PackageRoot 'src\cli.mjs') stop 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Start-Sleep -Milliseconds 1800 }
    [IO.Directory]::CreateDirectory($InstallRoot) | Out-Null
    [IO.Directory]::CreateDirectory($DesktopDirectory) | Out-Null
    $owned = New-Object 'System.Collections.Generic.List[string]'
    $source = [IO.Path]::GetFullPath($script:PackageRoot).TrimEnd('\')
    foreach ($entry in @('src','scripts','assets','runtime','third-party','.codex-plugin','.agents','package.json','.mcp.json','LICENSE','README.md','README.en.md','SECURITY.md','THIRD_PARTY_NOTICES.md','REFERENCE-RESEARCH.md','Install.cmd','Uninstall.cmd','Check.cmd')) {
        $sourceEntry = Join-Path $source $entry
        if (-not (Test-Path -LiteralPath $sourceEntry)) { continue }
        $item = Get-Item -LiteralPath $sourceEntry -Force
        $files = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $sourceEntry -File -Recurse -Force) } else { @($item) }
        foreach ($file in $files) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安装包不能包含文件链接。' }
            $relative = $file.FullName.Substring($source.Length + 1)
            $destination = [IO.Path]::GetFullPath((Join-Path $InstallRoot $relative))
            if (-not $destination.StartsWith($InstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '安装文件超出目标目录。' }
            [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
            if ($file.FullName -ne $destination) { Copy-Item -LiteralPath $file.FullName -Destination $destination -Force }
            $owned.Add($relative)
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot 'runtime\node.exe'))) {
        # Source installs can reuse Node on PATH. Release installs always include it.
        if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw '缺少运行时，请使用完整 Release。' }
    }
    $shortcutPath = Join-Path $DesktopDirectory 'Codex 额度.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        $existing = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
        if (-not (Test-QuotaShortcut $existing $InstallRoot)) { throw '同名桌面快捷方式已被其他程序使用，请先改名。' }
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $InstallRoot 'scripts\launch.vbs') + '"'
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.Description = '启动带双环额度显示的 Codex'
    $shortcut.IconLocation = $info.Path + ',0'
    $shortcut.Save()
    $taskName = $null
    if (-not $SkipTaskRegistration) {
        . (Join-Path $InstallRoot 'scripts\task-runner.ps1')
        $taskName = (Get-QuotaTaskSpec $InstallRoot).Name
    }
    Write-QuotaJson (Join-Path $InstallRoot 'installation.json') @{ id='codex-quota-rings'; version='0.1.5'; installRoot=$InstallRoot; codexPath=$info.Path; shortcut=$shortcutPath; scheduledTaskName=$taskName; files=@($owned) }
    # Record ownership before registering, so a failed registration is still uninstallable.
    if (-not $SkipTaskRegistration) { [void](Install-QuotaLaunchTask $InstallRoot) }
    if (-not $Quiet) {
        Show-QuotaMessage -Text ("安装完成。{0}{0}双击桌面的 Codex 额度 快捷方式。{0}若 Codex 仍在运行，启动器会等待你通过 右下角托盘图标右键 → 退出/Quit 完全退出，再自动重开。{0}以后使用这个快捷方式即可加载双环。" -f [Environment]::NewLine)
    }
    if (-not $NoLaunch -and @(Get-QuotaRunningCodex).Count -eq 0) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $InstallRoot 'scripts\launch.vbs') + '"') -WindowStyle Hidden | Out-Null
    }
    Write-Output "Installed: $InstallRoot"
} catch {
    if ($Quiet) { Write-Error $_.Exception.Message } else { Show-QuotaMessage -Text $_.Exception.Message -Kind 'Error' }
    exit 1
}
