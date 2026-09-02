# Register the Garmin sync as a Windows scheduled task at 07:50 daily.
#
# It must land before the 08:03 cloud routine, which reads the data this pushes.
#
# Run once, from the repo root:
#     .\scripts\install-task.ps1
#
# It runs as you, only when you are logged in, and catches up if the machine was
# asleep at 07:50. To remove it:
#     Unregister-ScheduledTask -TaskName "GRT garmin sync" -Confirm:$false

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo "scripts\sync_and_push.ps1"
$name = "GRT garmin sync"

if (-not (Test-Path $script)) { throw "sync_and_push.ps1 not found at $script" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"" `
  -WorkingDirectory $repo

$trigger = New-ScheduledTaskTrigger -Daily -At 7:50am

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -DontStopIfGoingOnBatteries `
  -AllowStartIfOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

try { Unregister-ScheduledTask -TaskName $name -Confirm:$false } catch {}

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
  -Settings $settings -Description "Syncs Garmin and pushes training.json for the Garden Route Ultra tracker." | Out-Null

Write-Host "Registered '$name' for 07:50 daily."
Write-Host "Run it now with:  Start-ScheduledTask -TaskName '$name'"
Write-Host "Log:              $repo\data\last-run.log"
