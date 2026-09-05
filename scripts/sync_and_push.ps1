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

# --autostash, so an unrelated edit sitting in the working tree does not kill
# the sync. Without it, one uncommitted file stops the brief for the day.
git pull --rebase --autostash --quiet origin main
if ($LASTEXITCODE -ne 0) { Say "git pull failed (exit $LASTEXITCODE) - stopping"; exit 1 }

$py = Join-Path (Split-Path -Parent $repo) ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }

# Weather first - it needs no credential, so a Garmin failure should not cost
# the forecast. Cape Town's south-easter decides more sessions than fatigue does.
& $py scripts/fetch_weather.py
if ($LASTEXITCODE -ne 0) { Say "weather fetch failed (exit $LASTEXITCODE) - continuing" }

& $py scripts/sync_garmin.py
if ($LASTEXITCODE -ne 0) {
  Say "Garmin sync failed (exit $LASTEXITCODE). Re-mint tokens with:"
  Say "  cd ..; .\.venv\Scripts\python.exe garmin_login.py"
  exit 1
}

# Commit needs an identity. Without one `git commit` fails, `git push` then finds
# nothing to send and exits 0, and this script used to report "pushed" every
# evening while nothing ever landed - two silent days before anyone noticed.
# Setting it per-invocation means the task never depends on global git config.
$ident = @("-c", "user.name=Chris Langebrink", "-c", "user.email=chris@langebrink.com")

git add data/training.json data/weather.json
if ($LASTEXITCODE -ne 0) { Say "git add failed (exit $LASTEXITCODE)"; exit 1 }

# `git diff --cached --quiet` answers through its EXIT CODE and prints nothing.
# `if (git diff ...)` tests stdout instead, which is always empty, so it always
# took the else branch. Read $LASTEXITCODE: 0 means no staged change.
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Say "no change in training.json - nothing to push"
  Say "=== done ==="
  exit 0
}

git @ident commit --quiet -m "chore(sync): garmin $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
if ($LASTEXITCODE -ne 0) { Say "git commit failed (exit $LASTEXITCODE) - nothing pushed"; exit 1 }

git push --quiet origin HEAD:main
if ($LASTEXITCODE -ne 0) { Say "git push failed (exit $LASTEXITCODE)"; exit 1 }

# Prove it landed rather than trusting the exit code.
git fetch --quiet origin main
$remote = (git rev-parse origin/main).Trim()
$local = (git rev-parse HEAD).Trim()
if ($remote -eq $local) {
  Say "pushed $($local.Substring(0,7)) - origin/main matches"
} else {
  Say "push reported success but origin/main is $($remote.Substring(0,7)), not $($local.Substring(0,7))"
  exit 1
}

Say "=== done ==="
