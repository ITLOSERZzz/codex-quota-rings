Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:StateRoot = if ($env:CODEX_QUOTA_STATE_DIR) { [IO.Path]::GetFullPath($env:CODEX_QUOTA_STATE_DIR) } else { Join-Path $env:USERPROFILE '.codex-quota-rings' }
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:ObservedMainPids = @()
$script:ReplacementMainPids = @()

function Show-QuotaMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text, [ValidateSet('Information','Warning','Error')][string]$Kind = 'Information')
    Add-Type -AssemblyName PresentationFramework
    $buttons = [System.Windows.MessageBoxButton]::OK
    $icon = [System.Windows.MessageBoxImage][Enum]::Parse([System.Windows.MessageBoxImage], $Kind)
    [void][System.Windows.MessageBox]::Show([string]$Text, [string]'Codex 额度', $buttons, $icon)
}
function Resolve-QuotaNode([string]$Root = $script:PackageRoot) {
    $bundled = Join-Path $Root 'runtime\node.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    $command = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw '没有找到运行时。请下载 GitHub Release 中包含 runtime 的 Windows 完整包。'
}
function Test-QuotaShortcut($Shortcut, [string]$Root) {
    $expectedTarget = Join-Path $env:WINDIR 'System32\wscript.exe'
    $expectedScript = Join-Path $Root 'scripts\launch.vbs'
    return $Shortcut.TargetPath -eq $expectedTarget -and $Shortcut.Arguments.Trim('"') -eq $expectedScript
}
function Write-QuotaJson([string]$Path, $Value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $temporary = "$Path.$PID.tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), $script:Utf8)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Get-QuotaRunningCodex {
    foreach ($process in @(Get-Process ChatGPT,Codex -ErrorAction SilentlyContinue)) {
        try {
            $file = $process.Path
            if ($file -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $file) 'resources\app.asar'))) {
                [pscustomobject]@{ Id = $process.Id; Path = $file }
            }
        } catch { }
    }
}
function Select-QuotaMainProcesses([object[]]$Processes, [string[]]$AllowedPaths) {
    foreach ($item in $Processes) {
        if (-not $item.ExecutablePath -or $AllowedPaths -notcontains $item.ExecutablePath) { continue }
        # Renderers, GPU workers and crash reporters may outlive the browser process.
        # They must not block a new desktop launch after the browser has exited.
        if ($item.CommandLine -match '(?i)--type(?:=|\s)|--crashpad-handler') { continue }
        [pscustomobject]@{Id=[int]$item.ProcessId;Path=$item.ExecutablePath}
    }
}
function Get-QuotaMainCodex {
    $allowed = @(@(Get-QuotaRunningCodex) | ForEach-Object { $_.Path } | Select-Object -Unique)
    if ($allowed.Count -eq 0) { return }
    $items = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe' OR Name='Codex.exe'" -ErrorAction Stop)
    Select-QuotaMainProcesses $items $allowed
}
function Get-QuotaExitWatchers([object[]]$Roots) {
    foreach ($root in $Roots) {
        $process = Get-Process -Id $root.Id -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try {
            if ($process.Path -ne $root.Path) { $process.Dispose(); continue }
            # Open and retain the original process handle; later PID reuse cannot
            # make a replacement process look like the one we were waiting for.
            $null = $process.Handle
            $process
        } catch { $process.Dispose() }
    }
}
function Get-QuotaDesktopInfo([string]$PreferredPath) {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $preferredValid = $PreferredPath -and (Test-Path -LiteralPath $PreferredPath -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PreferredPath) 'resources\app.asar'))
    if ($preferredValid) { $candidates.Add($PreferredPath) }
    if (-not $preferredValid) {
    foreach ($running in @(Get-QuotaRunningCodex)) { $candidates.Add($running.Path) }
    try {
        foreach ($package in @(Get-AppxPackage -Name '*Codex*' -ErrorAction SilentlyContinue)) {
            $candidates.Add((Join-Path $package.InstallLocation 'app\ChatGPT.exe'))
        }
    } catch { }
    foreach ($file in @('Programs\Codex\Codex.exe', 'Programs\Codex\ChatGPT.exe', 'Programs\ChatGPT\ChatGPT.exe')) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA $file))
    }
    }
    foreach ($file in $candidates) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $absolute = [IO.Path]::GetFullPath($file)
        if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $absolute) 'resources\app.asar'))) { continue }
        $aumid = $null
        $match = [regex]::Match($absolute, '(?i)^(.*\\WindowsApps\\([^\\]+))\\')
        if ($match.Success) {
            $manifestFile = Join-Path $match.Groups[1].Value 'AppxManifest.xml'
            try {
                [xml]$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFile
                $application = @($manifest.Package.Applications.Application) | Where-Object { [string]$_.Executable -match '(ChatGPT|Codex)\.exe$' } | Select-Object -First 1
                if ($application) {
                    $publisher = ($match.Groups[2].Value -split '_')[-1]
                    $aumid = "$($manifest.Package.Identity.Name)_$publisher!$($application.Id)"
                }
            } catch { }
        }
        return [pscustomobject]@{ Path = $absolute; AppUserModelId = $aumid }
    }
    return $null
}
function Start-QuotaCodex($Info, [int]$Port) {
    $arguments = "--remote-debugging-port=$Port --remote-debugging-address=127.0.0.1"
    if (-not $Info.AppUserModelId) {
        $appProcess = Start-Process -FilePath $Info.Path -ArgumentList $arguments -PassThru
        return $appProcess.Id
    }
    Initialize-QuotaWindowsActivation
    return [QuotaRings.WindowsActivation]::Start($Info.AppUserModelId, $arguments)
}
function Initialize-QuotaWindowsActivation {
    if (-not ('QuotaRings.WindowsActivation' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace QuotaRings {
  [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IActivation {
    [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint pid);
  }
  public static class WindowsActivation {
    public static int Start(string appId, string arguments) {
      object com = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")));
      try { uint pid; int result = ((IActivation)com).ActivateApplication(appId, arguments, 2, out pid); Marshal.ThrowExceptionForHR(result); return (int)pid; }
      finally { Marshal.ReleaseComObject(com); }
    }
  }
}
'@
    }
}
function Test-QuotaDebugPort([int]$Port) {
    if ($Port -lt 1024 -or $Port -gt 65535) { return $false }
    try {
        $result = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 -MaximumRedirection 0
        return [bool]$result.webSocketDebuggerUrl
    } catch { return $false }
}
function Get-QuotaAvailablePort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Get-QuotaLaunchControlName {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $bytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:StateRoot.ToLowerInvariant())) }
    finally { $hash.Dispose() }
    return 'Local\CodexQuotaLaunch-' + ([BitConverter]::ToString($bytes).Replace('-','').Substring(0,24))
}
function Stop-QuotaLauncher {
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting((Get-QuotaLaunchControlName) + '-cancel')
        try { [void]$event.Set() } finally { $event.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] { }
}
function Write-QuotaLaunchState([string]$Phase) {
    $script:LastLaunchPhase = $Phase
    Write-QuotaJson (Join-Path $script:StateRoot 'launch-state.json') @{ version='0.1.5'; phase=$Phase; updatedAt=[DateTime]::UtcNow.ToString('o'); launcherPid=$PID; launcherStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); observedMainPids=@($script:ObservedMainPids); replacementMainPids=@($script:ReplacementMainPids) }
}
function Wait-QuotaDesktopExit($Cancellation, [int]$TimeoutSeconds = 1800) {
    if ($Cancellation.WaitOne(0)) { return 'cancelled' }
    if ($TimeoutSeconds -le 0) { return 'wait-expired' }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $roots = @(Get-QuotaMainCodex)
    $watchers = @(Get-QuotaExitWatchers $roots)
    $script:ObservedMainPids = @($roots | ForEach-Object { $_.Id })
    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($Cancellation.WaitOne(0)) { return 'cancelled' }
            Write-QuotaLaunchState 'waiting-for-exit'
            $alive = @($watchers | Where-Object { -not $_.HasExited })
            if ($alive.Count -eq 0) {
                $replacement = @(Get-QuotaMainCodex)
                if ($replacement.Count -gt 0) {
                    $script:ReplacementMainPids = @($replacement | ForEach-Object { $_.Id })
                    return 'ordinary-relaunch-detected'
                }
                return 'exited'
            }
            if ($Cancellation.WaitOne(200)) { return 'cancelled' }
        }
        return 'wait-expired'
    } finally {
        foreach ($watcher in $watchers) { $watcher.Dispose() }
    }
}
function Start-QuotaHelper([string]$Node, [string]$Cli, [int]$Port) {
    return Start-Process -FilePath $Node -ArgumentList @(('"' + $Cli + '"'), 'daemon', "--port=$Port") -WindowStyle Hidden -PassThru
}
