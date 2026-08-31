# Register the morning coaching run as a Windows scheduled task at 08:00 daily.
#
# Run once, from the repo root:
#     .\scripts\install-task.ps1
#
# It runs as you, only when you are logged in, and catches up if the machine was
# asleep at 08:00. To remove it:
#     Unregister-ScheduledTask -TaskName "GRT morning brief" -Confirm:$false

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo "scripts\morning.ps1"
$name = "GRT morning brief"

if (-not (Test-Path $script)) { throw "morning.ps1 not found at $script" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"" `
  -WorkingDirectory $repo

$trigger = New-ScheduledTaskTrigger -Daily -At 8:00am

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -DontStopIfGoingOnBatteries `
  -AllowStartIfOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

try { Unregister-ScheduledTask -TaskName $name -Confirm:$false } catch {}

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
  -Settings $settings -Description "Syncs Garmin and writes the daily brief for the Garden Route Ultra tracker." | Out-Null

Write-Host "Registered '$name' for 08:00 daily."
Write-Host "Run it now with:  Start-ScheduledTask -TaskName '$name'"
Write-Host "Log:              $repo\data\last-run.log"
