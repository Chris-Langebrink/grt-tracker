# Sync Garmin and push the data. Runs locally at 07:50 on a scheduled task.
#
# WHY THIS IS LOCAL AND NOT IN THE CLOUD ROUTINE
#
# Garmin rotates the refresh token every time a client uses it and invalidates
# the previous one, so only one machine can hold a live session. A local client
# persists the rotated token straight back to ~/.garminconnect; a cloud
# environment variable cannot update itself, so a cloud copy goes stale the
# first time anything else syncs - which is exactly how the 2 September run
# failed with a 401.
#
# So: this script owns Garmin, and the 08:03 cloud routine owns the coaching.
# The routine reads data/training.json out of the repo and never touches a
# credential.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$log = Join-Path $repo "data\last-run.log"
function Say($m) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"
  Write-Host $line
  Add-Content -Path $log -Value $line -Encoding utf8
}

Say "=== sync starting ==="

git pull --rebase --quiet origin main
if (-not $?) { Say "git pull failed - stopping"; exit 1 }

$py = Join-Path (Split-Path -Parent $repo) ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }

& $py scripts/sync_garmin.py
if ($LASTEXITCODE -ne 0) {
  Say "Garmin sync failed (exit $LASTEXITCODE). Re-mint tokens with:"
  Say "  cd ..; .\.venv\Scripts\python.exe garmin_login.py"
  exit 1
}

git add data/training.json
if (git diff --cached --quiet) {
  Say "no change in training.json - nothing to push"
} else {
  git commit --quiet -m "chore(sync): garmin $(Get-Date -Format 'yyyy-MM-dd')"
  git push --quiet origin HEAD:main
  if ($?) { Say "pushed" } else { Say "push failed"; exit 1 }
}

Say "=== done ==="
