# Morning coaching run, local edition.
#
# Syncs Garmin, hands the routine prompt to Claude Code, and lets it write the
# brief and push. This is the bridge until the cloud routine has an environment
# with GARMIN_TOKENS in it; the cloud version runs the identical prompt.
#
#   .\scripts\morning.ps1            # run it now
#   .\scripts\install-task.ps1       # register it for 08:00 daily

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$log = Join-Path $repo "data\last-run.log"
function Say($m) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"
  Write-Host $line
  Add-Content -Path $log -Value $line -Encoding utf8
}

Say "=== morning run starting ==="

# Land on whatever the remote has before writing anything.
git pull --rebase --quiet origin main
if (-not $?) { Say "git pull failed - stopping"; exit 1 }

# Prefer the venv next door, fall back to whatever python is on PATH.
$py = Join-Path (Split-Path -Parent $repo) ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }

Say "syncing Garmin via $py"
& $py scripts/sync_garmin.py
if ($LASTEXITCODE -ne 0) {
  Say "Garmin sync failed (exit $LASTEXITCODE). Tokens may need refreshing:"
  Say "  cd ..; .\.venv\Scripts\python.exe garmin_login.py"
  exit 1
}

$prompt = Get-Content ".claude\routines\daily-brief.prompt.md" -Raw
Say "handing off to Claude Code"
$prompt | claude -p --output-format text
if ($LASTEXITCODE -ne 0) { Say "claude exited $LASTEXITCODE"; exit 1 }

Say "=== done ==="
