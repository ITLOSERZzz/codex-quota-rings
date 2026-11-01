# One per-user, on-demand launcher. No triggers, login startup, admin rights, or taskkill.
function Get-QuotaTaskSpec([string]$Root = $script:PackageRoot) {
    $absolute = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($absolute.ToLowerInvariant()))).Replace('-','').Substring(0,24) }
    finally { $sha.Dispose() }
    return [pscustomobject]@{
        Name=('CodexQuotaRings-' + $digest)
        WorkingDirectory=$absolute
        Path=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
        Arguments=('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $absolute 'scripts\launch.ps1') + '" -Quiet -KeepAlive')
        Description=('Codex Quota Rings on-demand launcher | ' + $absolute)
        UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
}
function Test-QuotaTaskOwnership($Task, $Spec) {
    $definition = $Task.Definition
    if ($definition.Actions.Count -ne 1 -or $definition.Triggers.Count -ne 0) { return $false }
    $action = $definition.Actions.Item(1)
    # Task Scheduler may canonicalize a supplied SID into DOMAIN\user. Compare
    # the resolved security identity rather than its display representation.
    try {
        $principalSid = if ($definition.Principal.UserId -match '^S-1-') {
            (New-Object Security.Principal.SecurityIdentifier($definition.Principal.UserId)).Value
        } else {
            (New-Object Security.Principal.NTAccount($definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
        }
    } catch { return $false }
    return $definition.RegistrationInfo.Description -eq $Spec.Description -and
        $action.Path -eq $Spec.Path -and $action.Arguments -eq $Spec.Arguments -and $action.WorkingDirectory -eq $Spec.WorkingDirectory -and
        $principalSid -eq $Spec.UserSid -and
        $definition.Principal.LogonType -eq 3 -and $definition.Principal.RunLevel -eq 0
}
function Get-QuotaTaskService {
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    return $service
}
function Find-QuotaTask($Folder, [string]$Name) {
    try { return $Folder.GetTask($Name) }
    catch {
        # Only a missing task is absence. Access or service failures must remain visible.
        $errorObject = $_.Exception
        while ($errorObject.InnerException) { $errorObject = $errorObject.InnerException }
        if ($errorObject.HResult -eq -2147024894) { return $null }
        throw
    }
}
function Install-QuotaLaunchTask([string]$Root = $script:PackageRoot) {
    $spec = Get-QuotaTaskSpec $Root
    $service = Get-QuotaTaskService
    $folder = $service.GetFolder('\')
    $existing = Find-QuotaTask $folder $spec.Name
    if ($existing -and -not (Test-QuotaTaskOwnership $existing $spec)) { throw '同名按需启动任务不属于本扩展，未覆盖。' }
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = $spec.Description
    $definition.Principal.UserId = $spec.UserSid
    $definition.Principal.LogonType = 3
    $definition.Principal.RunLevel = 0
    $definition.Settings.Hidden = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.MultipleInstances = 2
    $definition.Settings.ExecutionTimeLimit = 'PT0S'
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.AllowHardTerminate = $false
    $action = $definition.Actions.Create(0)
    $action.Path = $spec.Path
    $action.Arguments = $spec.Arguments
    $action.WorkingDirectory = [IO.Path]::GetFullPath($Root)
    $registered = $folder.RegisterTaskDefinition($spec.Name,$definition,6,$spec.UserSid,$null,3,$null)
    if (-not (Test-QuotaTaskOwnership $registered $spec)) { throw '按需启动任务校验失败。' }
    return $spec.Name
}
function Remove-QuotaLaunchTask([string]$Root = $script:PackageRoot) {
    $spec = Get-QuotaTaskSpec $Root
    $service = Get-QuotaTaskService
    $folder = $service.GetFolder('\')
    $task = Find-QuotaTask $folder $spec.Name
    if (-not $task) { return }
    if (-not (Test-QuotaTaskOwnership $task $spec)) { throw '按需启动任务归属校验失败，未删除。' }
    for ($attempt=0; $task.State -eq 4 -and $attempt -lt 20; $attempt++) { Start-Sleep -Milliseconds 250 }
    if ($task.State -eq 4) { throw '额度启动任务尚未正常退出，请稍候再试。未强制结束进程。' }
    $folder.DeleteTask($spec.Name,0)
}
function Start-QuotaLaunchTask([string]$Root = $script:PackageRoot) {
    $spec = Get-QuotaTaskSpec $Root
    $service = Get-QuotaTaskService
    $task = Find-QuotaTask ($service.GetFolder('\')) $spec.Name
    if (-not $task -or -not (Test-QuotaTaskOwnership $task $spec)) { throw '未找到经过校验的额度启动任务，请重新安装。' }
    [void]$task.Run($null)
}
