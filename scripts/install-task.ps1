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

# Two triggers, because one was not enough. The 07:50 run only fires if the
# machine is awake; through 3-4 September it was asleep every morning and
# -StartWhenAvailable caught up at 21:07 and 18:25 - after the 08:03 cloud
# routine had already read a stale file. The evening run captures that day's
# training; the morning run catches anything Garmin uploaded overnight.
$trigger = @(
  (New-ScheduledTaskTrigger -Daily -At 7:50am),
  (New-ScheduledTaskTrigger -Daily -At 9:30pm)
)

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -DontStopIfGoingOnBatteries `
  -AllowStartIfOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

# -ErrorAction Stop, or the "task not found" error is non-terminating, skips
# the catch, and still reports failure on a first install.
try { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop } catch {}

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
  -Settings $settings -Description "Syncs Garmin and pushes training.json for the Garden Route Ultra tracker." | Out-Null

Write-Host "Registered '$name' for 07:50 daily."
Write-Host "Run it now with:  Start-ScheduledTask -TaskName '$name'"
Write-Host "Log:              $repo\data\last-run.log"
