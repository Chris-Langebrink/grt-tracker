"""Fetch the Cape Town forecast into data/weather.json.

Open-Meteo, no API key, no credential. Run alongside the Garmin sync so the
morning routine can tell Chris whether today's session is actually rideable.

Cape Town's limiter is almost never temperature - it is the south-easter. A
25 km/h mean wind with 80 km/h gusts reads as "breezy" on most forecasts and is
genuinely dangerous on a road bike, so GUSTS drive every verdict here, not mean
wind speed.
"""
import json
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAT, LON = -33.9249, 18.4241  # Cape Town city bowl

# Gust thresholds in km/h. A road bike is the binding constraint: a crosswind
# gust moves you sideways, and 60+ km/h will take your front wheel.
BIKE = [(40, "good"), (55, "care"), (70, "poor"), (999, "no")]
RUN = [(50, "good"), (70, "care"), (90, "poor"), (999, "no")]
# Open water: onshore chop wrecks sighting long before it becomes unsafe.
SWIM = [(25, "good"), (35, "care"), (50, "poor"), (999, "no")]

WINDOWS = {"early": (6, 11), "midday": (11, 16), "evening": (16, 21)}
DIRS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def verdict(gust, scale):
    for limit, word in scale:
        if gust <= limit:
            return word
    return "no"


def main():
    url = (
        f"https://api.open-meteo.com/v1/forecast?latitude={LAT}&longitude={LON}"
        "&hourly=temperature_2m,precipitation,wind_speed_10m,wind_gusts_10m,"
        "wind_direction_10m&timezone=Africa/Johannesburg&forecast_days=4"
        "&wind_speed_unit=kmh"
    )
    with urllib.request.urlopen(url, timeout=30) as r:
        raw = json.load(r)

    h = raw["hourly"]
    days = {}
    for i, stamp in enumerate(h["time"]):
        day, hour = stamp[:10], int(stamp[11:13])
        rec = days.setdefault(day, {})
        for name, (lo, hi) in WINDOWS.items():
            if not lo <= hour < hi:
                continue
            w = rec.setdefault(name, {"gust": [], "wind": [], "temp": [], "rain": [], "dir": []})
            w["gust"].append(h["wind_gusts_10m"][i])
            w["wind"].append(h["wind_speed_10m"][i])
            w["temp"].append(h["temperature_2m"][i])
            w["rain"].append(h["precipitation"][i])
            w["dir"].append(h["wind_direction_10m"][i])

    out = {}
    for day, windows in sorted(days.items()):
        summary = {}
        for name, w in windows.items():
            if not w["gust"]:
                continue
            gust = round(max(w["gust"]))
            wind = round(sum(w["wind"]) / len(w["wind"]))
            bearing = sum(w["dir"]) / len(w["dir"])
            summary[name] = {
                "gust_max_kmh": gust,
                "wind_mean_kmh": wind,
                "dir": DIRS[round(bearing / 22.5) % 16],
                "temp_c": round(sum(w["temp"]) / len(w["temp"])),
                "rain_mm": round(sum(w["rain"]), 1),
                "bike": verdict(gust, BIKE),
                "run": verdict(gust, RUN),
                "open_water": verdict(gust, SWIM),
            }
        if summary:
            best = min(summary.items(),
                       key=lambda kv: kv[1]["gust_max_kmh"])
            out[day] = {"windows": summary, "calmest": best[0]}

    payload = {
        "generated_at": raw.get("current_weather", {}).get("time")
        or date.today().isoformat(),
        "location": "Cape Town",
        "source": "open-meteo.com",
        "units": "km/h, degrees C, mm",
        "thresholds": {
            "bike": "good <=40 gust, care <=55, poor <=70, no above",
            "run": "good <=50 gust, care <=70, poor <=90, no above",
            "open_water": "good <=25 gust, care <=35, poor <=50, no above",
        },
        "note": "Verdicts key off MAXIMUM GUST, not mean wind. Cape Town's south-easter "
                "routinely runs a 20 km/h mean with 80 km/h gusts, which is rideable on "
                "paper and not in practice.",
        "days": out,
    }
    path = ROOT / "data" / "weather.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(payload, indent=1), encoding="utf-8")

    print(f"weather -> {path}")
    for day, d in out.items():
        parts = [f"{n}: gust {w['gust_max_kmh']} {w['dir']} bike={w['bike']}"
                 for n, w in d["windows"].items()]
        print(f"  {day}  " + " | ".join(parts))


if __name__ == "__main__":
    main()
