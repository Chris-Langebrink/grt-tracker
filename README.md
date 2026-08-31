# Garden Route Ultra — training tracker

Live: **https://chris-langebrink.github.io/grt-tracker/**

A race command centre for one athlete and one date: 2 km / 80 km / 20 km at
Santos Beach, Mossel Bay, 07:00 on 20 September 2026.

## How it works

| File | What it is |
|---|---|
| `index.html` | The app. Static, no build. Fetches the three JSON files below at load. |
| `plan.json` | Single source of truth — sessions, heart-rate zones, race effort by surface, fuelling. |
| `data/training.json` | Garmin activities and wellness, rewritten every morning by the sync. |
| `data/status.json` | Per-date verdict on whether a session was completed, with the evidence. |
| `data/brief.json` | The morning read that appears at the top of the page. |
| `CLAUDE.md` | Coaching instructions — who Chris is, how to read the data, what not to get wrong. |

A Claude routine runs at 08:00 SAST, syncs Garmin, judges yesterday against the
plan, writes the brief and pushes. GitHub Pages serves the result.

## Running the sync locally

```bash
python -m venv .venv
.venv/Scripts/python.exe -m pip install garminconnect
.venv/Scripts/python.exe scripts/sync_garmin.py            # 10 Aug -> today
.venv/Scripts/python.exe scripts/sync_garmin.py 2026-09-01 # from a date
```

Auth uses OAuth tokens at `~/.garminconnect`. To create them, run the login
script in the parent Fitness folder — it prompts for the password directly so it
never passes through a transcript. In a routine or CI, set `GARMIN_TOKENS` to
the base64 of `~/.garminconnect/garmin_tokens.json` instead.

## Data caveats that matter

- **Recorded distance is a floor, not a total.** The watch starts late,
  auto-splits continuous rides and runs out of battery.
- **Sessions hide inside `indoor_cardio` logs.** The sync flags them as
  `wrapped_min` from the shape of the heart-rate trace.
- **Heart rates above 190 bpm on rides are dropped** as optical artefacts, so
  averages here differ from what Garmin displays.
