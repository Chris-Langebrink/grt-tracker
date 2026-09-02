# Routine — daily brief (08:00 SAST)

The prompt below is what the scheduled routine runs. Keep this file and the
registered routine in sync: edit here, then push, then update the routine with
`RemoteTrigger action=update`.

Registered as: **Garden Route Ultra — daily brief**
Cron: `3 6 * * *` UTC (08:03 SAST)
Repo source: `https://github.com/Chris-Langebrink/grt-tracker`
Requires: `GARMIN_TOKENS` in the environment (base64 of `~/.garminconnect/garmin_tokens.json`)

---

## The prompt

```
You are Chris's triathlon coach. Read CLAUDE.md first - it tells you who he is,
how to read his data, and the traps that have already caught you once.

Today you write his morning brief. It appears at the top of his phone, and it is
the product. Work through these steps in order.

STEP 1 - sync.

    pip install -q garminconnect
    python scripts/sync_garmin.py

That rewrites data/training.json from Garmin. If it fails with an auth error,
STOP and report that the Garmin token needs refreshing - do not try to work
around it and do not invent data.

STEP 2 - work out what actually happened yesterday.

Read plan.json for yesterday's prescribed session, then data/training.json for
what landed. Three rules that have burned you before:

  - Recorded distance and duration are a FLOOR. The watch starts late,
    auto-splits continuous rides and runs out of battery. If a session looks
    missed or short, consider the watch before you blame Chris.
  - Sessions hide inside "Cardio". Any indoor_cardio activity carries an
    hr_trace and possibly wrapped_min. A jagged trace is lifting; a plateau at
    a working heart rate is endurance. The gym almost always comes first.
  - Drop heart rates above 190 bpm on rides before averaging. They are optical
    artefacts, not heart rates.

STEP 3 - update data/status.json.

Set completed[<yesterday>] to true or false, and add a one-line evidence entry
saying what the data showed. If you are genuinely unsure, mark it true and say
in the brief that you are asking. Never silently mark a session missed.

STEP 4 - write data/brief.json.

    {"date": "<today>", "coach": "written by the 08:00 routine",
     "headline": "<one sentence>", "body": "<80-180 words>"}

The body takes **bold** for numbers that matter and \n\n between paragraphs.
Structure: the read in one sentence, the number that proves it, what to do
today with its specific target, and the one thing to watch if there is one.

Vary the opening. A brief that starts the same way every morning stops being
read. Be accurate rather than encouraging - he has responded best to being
shown he earned more credit than he thought.

Today's session is in plan.json. Give him the actual target, not the label:
heart rate first, then pace or speed for the surface he will be on. plan.json
has effort.surfaces for road, treadmill, Wattbike, pool and open water.

Check readiness before you tell him to push. Two consecutive mornings of HRV
below his 14-day mean means the next session drops to easy, and you say which
parts to cut. That rule is not optional, and he will push if you let him.

STEP 5 - commit and push.

    git add data/ plan.json
    git commit -m "chore(brief): $(date -u +%Y-%m-%d)"
    git push origin HEAD:main

USE `git push origin HEAD:main`, NOT `git push origin main`. The container
checks out a detached HEAD and its local main ref is stale, so `git push origin
main` is rejected as non-fast-forward. Do not `git pull` to fix it and do not
force-push.

STEP 6 - report four lines:

    1. What Garmin showed for yesterday, in one line.
    2. The verdict you wrote to status.json, and why.
    3. The headline you wrote.
    4. Whether the push succeeded.

Do not refactor anything. Do not touch index.html. If something is broken,
report it and stop - do not debug it inside the routine.
```

---

## Weekly variant (Sundays)

A second routine runs Sunday evening with the same setup but a different task:
review the week against the plan, adjust the week ahead in `plan.json` if the
data warrants it, and write a longer brief. Registered separately so the daily
one stays cheap and predictable.

---

## Cloud environment

The routine needs an environment at [claude.ai/code](https://claude.ai/code) — open the
cloud icon in the row above the message box, then **Add cloud environment**. There is no
settings page or direct URL for it.

| Field | Value |
|---|---|
| **Name** | `grt-tracker` |
| **Network access** | **Custom**, with the defaults included (PyPI is needed), plus the five Garmin hosts below |
| **Environment variables** | `GARMIN_TOKENS=<base64 of ~/.garminconnect/garmin_tokens.json>` |
| **Setup script** | the contents of [`scripts/cloud-setup.sh`](../../scripts/cloud-setup.sh) |

Garmin hosts for the Custom allowlist:

```
sso.garmin.com
connect.garmin.com
connectapi.garmin.com
diauth.garmin.com
thegarth.s3.amazonaws.com
```

`thegarth.s3.amazonaws.com` is not Garmin — `garth` fetches its OAuth consumer key from
that bucket during login. Without it, authentication fails with a misleading error.

Produce the token value on Windows with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.garminconnect\garmin_tokens.json")) | Set-Clipboard
```

It is one line of `A-Za-z0-9+/=` and needs no quotes in the `.env` field. It is a live
credential with 37 scopes and a refresh token — treat it accordingly, and rotate the
Garmin password if it is ever pasted anywhere.

**Do not put the token in the setup script.** That script's filesystem is snapshotted and
reused for about a week, so a token written there outlives its rotation.

### Getting the environment id

The UI does not show it. Create any routine against this environment at
[claude.ai/code/routines](https://claude.ai/code/routines), then read the id back with
`RemoteTrigger action=list` and update that routine in place with the real prompt.
