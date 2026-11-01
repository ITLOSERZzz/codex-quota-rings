. (Join-Path $PSScriptRoot 'common.ps1')
$running = @(Get-QuotaRunningCodex)
Write-Output ('Codex 额度双环 0.1.5 · 桌面进程数：' + $running.Count)
$stateFile = Join-Path $script:StateRoot 'launch-state.json'
if (Test-Path -LiteralPath $stateFile) {
    $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Output ('启动阶段：' + $state.phase)
    $alive = $false
    if ($state.PSObject.Properties['launcherPid'] -and $state.PSObject.Properties['launcherStartedAt']) {
        $process = Get-Process -Id $state.launcherPid -ErrorAction SilentlyContinue
        $alive = $process -and $process.StartTime.ToUniversalTime().ToString('o') -eq $state.launcherStartedAt
    }
    Write-Output ('启动器进程仍在：' + [bool]$alive)
    if (-not $alive -and $state.phase -eq 'waiting-for-exit') { Write-Output '上次等待进程已结束，记录不是当前运行状态。请使用桌面快捷方式或检查按需启动任务。' }
    if ($state.phase -eq 'waiting-for-exit') { Write-Output '请通过 Codex 的 右下角托盘图标右键 → 退出/Quit 完全退出，等待中的启动器会自动重开。' }
    if ($state.phase -eq 'ordinary-relaunch-detected') { Write-Output '原主进程退出后，检测到另一个普通 Codex 进程已先打开。本扩展没有关闭它；请从托盘退出后使用 Codex 额度 快捷方式。' }
} else { Write-Output '尚无新版本启动记录，请打开桌面 Codex 额度 快捷方式。' }
$node = Resolve-QuotaNode
$markerFile = Join-Path $script:PackageRoot 'installation.json'
if (Test-Path -LiteralPath $markerFile) {
    $marker = Get-Content -LiteralPath $markerFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($marker.PSObject.Properties['scheduledTaskName'] -and $marker.scheduledTaskName) {
        try {
            . (Join-Path $PSScriptRoot 'task-runner.ps1')
            $spec = Get-QuotaTaskSpec
            $task = Find-QuotaTask ((Get-QuotaTaskService).GetFolder('\')) $spec.Name
            Write-Output ('按需启动任务已校验：' + [bool]($task -and (Test-QuotaTaskOwnership $task $spec)))
            if ($task) { Write-Output ('任务状态：' + $task.State + '；上次结果：' + $task.LastTaskResult) }
        } catch { Write-Output '按需启动任务暂不可读，请检查任务计划程序服务。' }
    }
}
$raw = & $node (Join-Path $script:PackageRoot 'src\cli.mjs') status 2>$null | Out-String
if ($LASTEXITCODE -eq 0) {
    $helper = $raw | ConvertFrom-Json
    Write-Output ('监控运行：' + $helper.running)
    foreach ($window in @($helper.windows)) {
        Write-Output ('双环已显示：' + $window.mounted + '；位置：' + $window.placement + '；状态：' + $window.reason)
    }
}
# Intentionally omit usage values, account identifiers, window titles, and raw errors.
