. (Join-Path $PSScriptRoot 'common.ps1')
try {
    $markerFile = Join-Path $script:PackageRoot 'installation.json'
    if (-not (Test-Path -LiteralPath $markerFile)) { throw '请先安装完整 Windows 包。' }
    $marker = Get-Content -LiteralPath $markerFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($marker.PSObject.Properties['scheduledTaskName'] -and $marker.scheduledTaskName) {
        . (Join-Path $PSScriptRoot 'task-runner.ps1')
        Start-QuotaLaunchTask
    } else {
        # Development-only installs can explicitly skip Task Scheduler registration.
        & (Join-Path $PSScriptRoot 'launch.ps1')
    }
} catch {
    Show-QuotaMessage -Text $_.Exception.Message -Kind 'Error'
    exit 1
}
