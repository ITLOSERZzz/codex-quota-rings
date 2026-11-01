[CmdletBinding()]
param([string]$CodexPath, [switch]$Quiet, [switch]$KeepAlive)
. (Join-Path $PSScriptRoot 'common.ps1')
$launchMutex = $null
$launchCancel = $null
$ownsLaunch = $false
$script:LastLaunchPhase = 'initializing'
try {
    $launchMutex = New-Object Threading.Mutex($false, (Get-QuotaLaunchControlName))
    try { $ownsLaunch = $launchMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsLaunch = $true }
    if (-not $ownsLaunch) { return }
    $launchCancel = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, ((Get-QuotaLaunchControlName) + '-cancel'))
    [void]$launchCancel.Reset()
    Write-QuotaLaunchState 'initializing'
    $node = Resolve-QuotaNode
    $cli = Join-Path $script:PackageRoot 'src\cli.mjs'
    if (-not $CodexPath) {
        $installFile = Join-Path $script:PackageRoot 'installation.json'
        if (Test-Path -LiteralPath $installFile) { $CodexPath = (Get-Content -Raw -Encoding UTF8 -LiteralPath $installFile | ConvertFrom-Json).codexPath }
    }
    $info = Get-QuotaDesktopInfo $CodexPath
    if (-not $info) { throw '未找到 Codex Desktop。请重新运行安装程序，选择实际的 ChatGPT.exe 或 Codex.exe。' }
    if ($info.AppUserModelId) { Initialize-QuotaWindowsActivation }
    $running = @(Get-QuotaRunningCodex)
    $port = 0
    $launchFile = Join-Path $script:StateRoot 'launch.json'
    if ($running.Count -gt 0 -and (Test-Path -LiteralPath $launchFile)) {
        try {
            $previous = Get-Content -Raw -Encoding UTF8 -LiteralPath $launchFile | ConvertFrom-Json
            $sameProcess = @($running | Where-Object { $_.Id -eq $previous.processId -and $_.Path -eq $previous.codexPath }).Count -gt 0
            if ($sameProcess -and (Test-QuotaDebugPort ([int]$previous.port))) { $port = [int]$previous.port }
        } catch { }
    }
    if ($running.Count -gt 0 -and $port -eq 0) {
        Write-QuotaLaunchState 'waiting-for-exit'
        if (-not $Quiet) {
            Show-QuotaMessage -Text ("启动器已就绪，正在等待 Codex 完全退出。{0}{0}点击确定后，请保存工作，通过 右下角托盘图标右键 → 退出/Quit 关闭 Codex。{0}退出后会自动重新打开并加载双环，无需再次点击快捷方式。{0}{0}右上角关闭只关窗口，程序仍可能在后台运行；等待最长 30 分钟。" -f [Environment]::NewLine)
        }
        $waitResult = Wait-QuotaDesktopExit $launchCancel
        if ($waitResult -ne 'exited') { Write-QuotaLaunchState $waitResult; return }
        # Resolve again after an exit in case the app updated while the launcher waited.
        $info = Get-QuotaDesktopInfo $CodexPath
        if (-not $info) { throw '未找到 Codex Desktop，请重新运行安装程序。' }
    }
    if ($launchCancel.WaitOne(0)) { Write-QuotaLaunchState 'cancelled'; return }
    if ($port -eq 0) {
        Write-QuotaLaunchState 'starting-desktop'
        $port = Get-QuotaAvailablePort
        $appProcessId = Start-QuotaCodex $info $port
        Write-QuotaJson $launchFile @{ processId = $appProcessId; port = $port; codexPath = $info.Path }
        $ready = $false
        for ($attempt = 0; $attempt -lt 90; $attempt++) {
            if ($launchCancel.WaitOne(0)) { Write-QuotaLaunchState 'cancelled'; return }
            if (Test-QuotaDebugPort $port) { $ready = $true; break }
            if (-not (Get-Process -Id $appProcessId -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 2000
        }
        if (-not $ready) { Write-QuotaLaunchState 'port-unavailable'; throw 'Codex 未开放本机监控端口。请运行安装目录中的 Check.cmd 查看启动阶段。' }
    }
    # One helper per Windows user. Do not silently reuse a helper for a different app instance.
    $current = & $node $cli status 2>$null | Out-String
    if ($LASTEXITCODE -eq 0) {
        $currentState = $current | ConvertFrom-Json
        if ($currentState.running -and [int]$currentState.port -eq $port) { Write-QuotaLaunchState 'helper-running'; return }
        if ($currentState.running) {
            & $node $cli stop 2>$null | Out-Null
            Start-Sleep -Milliseconds 1800
        }
    }
    $helperProcess = Start-QuotaHelper $node $cli $port
    Write-QuotaLaunchState 'helper-started'
    # Keep the scheduled action alive for the helper's lifetime; never detach it into
    # the agent command runner's process tree or rely on orphan-child behavior.
    if ($KeepAlive -and $helperProcess) {
        $launchMutex.ReleaseMutex(); $ownsLaunch = $false
        $helperProcess.WaitForExit()
        Write-QuotaLaunchState 'helper-exited'
    }
} catch {
    try { if ($script:LastLaunchPhase -ne 'port-unavailable') { Write-QuotaLaunchState 'failed' } } catch { }
    $message = $_.Exception.Message
    if ($Quiet) { Write-Error $message } else { Show-QuotaMessage -Text $message -Kind 'Warning' }
    exit 1
} finally {
    if ($launchCancel) { $launchCancel.Dispose() }
    if ($ownsLaunch) { $launchMutex.ReleaseMutex() }
    if ($launchMutex) { $launchMutex.Dispose() }
}
