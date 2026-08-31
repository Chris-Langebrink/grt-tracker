"""Pull Garmin activity and wellness data into data/training.json.

Runs locally (tokens at ~/.garminconnect) or in a Claude routine / CI, where the
token JSON is supplied base64-encoded in GARMIN_TOKENS.

    python scripts/sync_garmin.py                # 10 Aug -> today
    python scripts/sync_garmin.py 2026-08-25     # from a date -> today

The watch under-records: it starts late, auto-splits continuous rides and runs
out of battery. Everything written here is therefore a FLOOR, never a total.
Rides also carry optical-HR artefacts above 190 bpm, which are dropped before
any average is taken - Garmin's own displayed averages include them.
"""
import base64
import json
import os
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

from garminconnect import Garmin

ROOT = Path(__file__).resolve().parent.parent
HR_ARTEFACT_CEILING = 190
DISCIPLINE = {
    "lap_swimming": "swim", "open_water_swimming": "swim", "swimming": "swim",
    "cycling": "bike", "road_biking": "bike", "mountain_biking": "bike",
    "virtual_ride": "bike", "indoor_cycling": "bike",
    "running": "run", "treadmill_running": "run", "trail_running": "run",
    "indoor_cardio": "gym", "strength_training": "gym", "fitness_equipment": "gym",
    "walking": "walk", "hiking": "walk",
}


def connect():
    """Token store from GARMIN_TOKENS (base64 JSON) if present, else ~/.garminconnect."""
    api = Garmin()
    blob = os.getenv("GARMIN_TOKENS")
    if blob:
        store = Path.home() / ".garminconnect"
        store.mkdir(parents=True, exist_ok=True)
        (store / "garmin_tokens.json").write_text(
            base64.b64decode(blob).decode("utf-8"), encoding="utf-8"
        )
    api.login(str(Path.home() / ".garminconnect"))
    return api


def clean_hr(series):
    """Optical sensors spike to 200-240 on the bike. Those are not heart rates."""
    good = [hr for hr in series if hr and hr <= HR_ARTEFACT_CEILING]
    return round(sum(good) / len(good)) if good else None


def hr_trace(api, activity_id, bucket_s=120):
    """Mean heart rate per bucket - the shape that reveals a wrapped session."""
    try:
        detail = api.get_activity_details(activity_id, maxchart=2000, maxpoly=0)
    except Exception:
        return []
    idx = {m["key"]: m["metricsIndex"] for m in detail.get("metricDescriptors", [])}
    hr_i, ts_i = idx.get("directHeartRate"), idx.get("directTimestamp")
    if hr_i is None or ts_i is None:
        return []
    points = [
        (r["metrics"][ts_i], r["metrics"][hr_i])
        for r in detail.get("activityDetailMetrics", [])
        if r["metrics"][hr_i]
    ]
    if not points:
        return []
    t0 = points[0][0]
    buckets = {}
    for ts, hr in points:
        buckets.setdefault(int((ts - t0) / (bucket_s * 1000)), []).append(hr)
    return [round(sum(v) / len(v)) for _, v in sorted(buckets.items())]


def split_point(trace):
    """Where a Cardio log stops being strength work and becomes endurance.

    Strength is jagged with optical dropouts; endurance settles into a plateau.
    Scan for the earliest index after which the trace stays inside a narrow band
    for at least 20 minutes, and report it so the routine can name the session.
    """
    window = 10  # 10 buckets = 20 minutes at the default bucket size
    if len(trace) < window + 5:
        return None

    def churn(seq):
        """Mean absolute step between buckets. Lifting swings; steady state does not."""
        if len(seq) < 2:
            return 0.0
        return sum(abs(b - a) for a, b in zip(seq, seq[1:])) / (len(seq) - 1)

    for i in range(len(trace) - window):
        tail = trace[i:]
        # A real endurance tail is smooth, sits at a working heart rate, and is
        # preceded by something visibly rougher. All three, or it is not a split.
        if churn(tail) > 5.0 or sum(tail) / len(tail) < 120:
            continue
        if i == 0:
            return 0
        if churn(trace[:i]) >= churn(tail) * 1.8:
            return i
    return None


def activities(api, start, end):
    out = []
    for a in api.get_activities_by_date(start, end):
        type_key = (a.get("activityType") or {}).get("typeKey", "other")
        aid = str(a.get("activityId"))
        row = {
            "id": aid,
            "start": (a.get("startTimeLocal") or "")[:16],
            "date": (a.get("startTimeLocal") or "")[:10],
            "type": type_key,
            "discipline": DISCIPLINE.get(type_key, "other"),
            "name": a.get("activityName") or "",
            "km": round((a.get("distance") or 0) / 1000, 2),
            "min": round((a.get("duration") or 0) / 60),
            "sec": round(a.get("duration") or 0),
            "elev_m": round(a.get("elevationGain") or 0),
            "hr_avg_raw": a.get("averageHR"),
            "kcal": round(a.get("calories") or 0),
        }
        # Only the long or ambiguous files are worth a detail call.
        if row["min"] >= 25:
            trace = hr_trace(api, aid)
            if trace:
                row["hr_trace"] = trace
                row["hr_avg"] = clean_hr(trace)
                if row["discipline"] == "gym":
                    sp = split_point(trace)
                    if sp is not None and sp < len(trace) - 10:
                        row["wrapped_from_bucket"] = sp
                        row["wrapped_min"] = (len(trace) - sp) * 2
        row.setdefault("hr_avg", row["hr_avg_raw"])
        if row["km"] and row["sec"]:
            if row["discipline"] == "run":
                sec = row["sec"] / row["km"]
                row["pace"] = f"{int(sec // 60)}:{round(sec % 60):02d}/km"
            elif row["discipline"] == "bike":
                row["kmh"] = round(row["km"] / (row["sec"] / 3600), 1)
            elif row["discipline"] == "swim":
                sec = row["sec"] / (row["km"] * 10)
                row["pace"] = f"{int(sec // 60)}:{round(sec % 60):02d}/100m"
        out.append(row)
    return out


def wellness(api, start, end):
    out = []
    day = date.fromisoformat(start)
    last = date.fromisoformat(end)
    while day <= last:
        s = str(day)
        row = {"date": s}
        try:
            stats = api.get_stats(s) or {}
            row["rhr"] = stats.get("restingHeartRate")
            row["steps"] = stats.get("totalSteps")
            row["stress"] = stats.get("averageStressLevel")
            row["bb_low"] = stats.get("bodyBatteryLowestValue")
            row["bb_high"] = stats.get("bodyBatteryHighestValue")
        except Exception:
            pass
        try:
            sleep = (api.get_sleep_data(s) or {}).get("dailySleepDTO", {}) or {}
            if sleep.get("sleepTimeSeconds"):
                row["sleep_h"] = round(sleep["sleepTimeSeconds"] / 3600, 1)
            if sleep.get("deepSleepSeconds"):
                row["deep_min"] = round(sleep["deepSleepSeconds"] / 60)
        except Exception:
            pass
        try:
            hrv = (api.get_hrv_data(s) or {}).get("hrvSummary") or {}
            row["hrv"] = hrv.get("lastNightAvg")
            row["hrv_status"] = hrv.get("status")
        except Exception:
            pass
        out.append(row)
        day += timedelta(days=1)
    return out


def main():
    start = sys.argv[1] if len(sys.argv) > 1 else "2026-08-10"
    end = sys.argv[2] if len(sys.argv) > 2 else str(date.today())

    api = connect()
    acts = activities(api, start, end)
    well = wellness(api, start, end)

    payload = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "window": {"start": start, "end": end},
        "activities": acts,
        "wellness": well,
        "caveat": "Recorded distance and duration are a floor, not a total - the watch starts late, auto-splits and runs flat. HR above 190 bpm is dropped as an optical artefact.",
    }
    out = ROOT / "data" / "training.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(payload, indent=1), encoding="utf-8")

    wrapped = [a for a in acts if a.get("wrapped_min")]
    print(f"{len(acts)} activities, {len(well)} wellness days -> {out}")
    print(f"{len(wrapped)} Cardio logs look like they contain a wrapped session:")
    for a in wrapped:
        print(f"   {a['start']}  {a['min']:>3} min total, ~{a['wrapped_min']} min endurance tail")


if __name__ == "__main__":
    main()
