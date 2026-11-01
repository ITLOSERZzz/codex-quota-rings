$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\common.ps1')
. (Join-Path $root 'scripts\task-runner.ps1')
# In-memory COM doubles only. This test cannot register, run, or delete OS tasks.
function New-FakeTaskDefinition {
    $actions = [pscustomobject]@{Count=0;Action=$null}
    $actions | Add-Member ScriptMethod Create { param($type)
        $this.Count=1; $this.Action=[pscustomobject]@{Path='';Arguments='';WorkingDirectory=''}; return $this.Action
    }
    $actions | Add-Member ScriptMethod Item { param($index) return $this.Action }
    return [pscustomobject]@{
        RegistrationInfo=[pscustomobject]@{Description=''}
        Principal=[pscustomobject]@{UserId='';LogonType=0;RunLevel=0}
        Triggers=[pscustomobject]@{Count=0}
        Actions=$actions
        Settings=[pscustomobject]@{Hidden=$false;AllowDemandStart=$false;MultipleInstances=0;ExecutionTimeLimit='';DisallowStartIfOnBatteries=$true;StopIfGoingOnBatteries=$true;AllowHardTerminate=$true}
    }
}
$folder = [pscustomobject]@{Tasks=@{};Registrations=0;Deletions=0}
$folder | Add-Member ScriptMethod GetTask { param($name)
    if (-not $this.Tasks.ContainsKey($name)) { throw (New-Object Runtime.InteropServices.COMException('missing',-2147024894)) }
    return $this.Tasks[$name]
}
$folder | Add-Member ScriptMethod RegisterTaskDefinition { param($name,$definition,$flags,$userId,$password,$logonType,$sddl)
    if ($flags -ne 6 -or $logonType -ne 3 -or $password) { throw 'Unexpected registration privilege or credential' }
    $task = [pscustomobject]@{Definition=$definition;State=3;Ran=$false}
    $task | Add-Member ScriptMethod Run {param($parameters) $this.Ran=$true}
    $this.Tasks[$name]=$task; $this.Registrations++; return $task
}
$folder | Add-Member ScriptMethod DeleteTask { param($name,$flags) $this.Tasks.Remove($name); $this.Deletions++ }
$script:FakeService = [pscustomobject]@{Folder=$folder}
$script:FakeService | Add-Member ScriptMethod GetFolder {param($name) return $this.Folder}
$script:FakeService | Add-Member ScriptMethod NewTask {param($flags) return New-FakeTaskDefinition}
function Get-QuotaTaskService { return $script:FakeService }
$fakeRoot = Join-Path $root 'test-results\task spec 中文'
$name = Install-QuotaLaunchTask $fakeRoot
$spec = Get-QuotaTaskSpec $fakeRoot
$task = $folder.Tasks[$name]
if (-not (Test-QuotaTaskOwnership $task $spec)) { throw 'Owned task rejected' }
$task.Definition.Principal.UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not (Test-QuotaTaskOwnership $task $spec)) { throw 'Canonical Windows account name was not resolved to its SID' }
$task.Definition.Principal.UserId='S-1-5-18'
if (Test-QuotaTaskOwnership $task $spec) { throw 'Another security principal was accepted' }
$task.Definition.Principal.UserId=$spec.UserSid
if ($task.Definition.Settings.ExecutionTimeLimit -ne 'PT0S' -or $task.Definition.Triggers.Count -ne 0 -or $task.Definition.Principal.RunLevel -ne 0) { throw 'Task must be on-demand and non-elevated' }
Start-QuotaLaunchTask $fakeRoot
if (-not $task.Ran) { throw 'Task did not receive on-demand run' }
$task.Definition.Actions.Action.Path = 'C:\unowned.exe'
foreach ($operation in @('install','remove','run')) {
    $refused=$false
    try {
        switch($operation) {
            'install' { Install-QuotaLaunchTask $fakeRoot | Out-Null }
            'remove' { Remove-QuotaLaunchTask $fakeRoot }
            'run' { Start-QuotaLaunchTask $fakeRoot }
        }
    } catch { $refused=$true }
    if (-not $refused) { throw ('Foreign task was accepted for ' + $operation) }
}
if ($folder.Registrations -ne 1 -or $folder.Deletions -ne 0) { throw 'Foreign task was modified' }
$task.Definition.Actions.Action.Path = $spec.Path
$task.Definition.Triggers.Count=1
if (Test-QuotaTaskOwnership $task $spec) { throw 'Triggered task was accepted' }
$task.Definition.Triggers.Count=0
$task.Definition.Principal.RunLevel=1
if (Test-QuotaTaskOwnership $task $spec) { throw 'Elevated task was accepted' }
$task.Definition.Principal.RunLevel=0
Remove-QuotaLaunchTask $fakeRoot
if ($folder.Deletions -ne 1 -or $folder.Tasks.Count -ne 0) { throw 'Owned task was not removed' }
Write-Output 'PASS: task registration/run/removal and ownership guards via in-memory COM doubles; zero OS tasks changed.'
