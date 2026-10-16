param([string]$Lua = 'lua', [string]$Python = '', [switch]$Enable, [switch]$AllowEarlyStart)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Enable) { throw 'Scheduling is disabled by default. After acceptance and observed manual days, pass -Enable.' }
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.local/ACCEPTANCE_PASSED'))) { throw 'Run the mock acceptance suite first.' }
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.local/MANUAL_DAYS_CONFIRMED'))) {
    if (-not $AllowEarlyStart) { throw 'Record successful observed manual days, or explicitly pass -AllowEarlyStart to override the calibration period.' }
    Set-Content -LiteralPath (Join-Path $Repo '.local/EARLY_SCHEDULING_AUTHORIZED') -Value ('Human explicitly authorized unattended scheduling before completion of the manual calibration period. ' + (Get-Date).ToString('o'))
}
if ($Python) {
    $Action = New-ScheduledTaskAction -Execute $Python -Argument 'system/run.py heartbeat' -WorkingDirectory $Repo
} else {
    $Action = New-ScheduledTaskAction -Execute $Lua -Argument 'system/heartbeat.lua' -WorkingDirectory $Repo
}
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'ComputationalArtCollectiveHeartbeat' -Action $Action -Trigger $Trigger -Settings $Settings -Description 'Local studio heartbeat; Lua gateway controls all inference.' | Out-Null
