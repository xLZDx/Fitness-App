"""Build the app's exercise catalog from the public-domain free-exercise-db.

Source: https://github.com/yuhonas/free-exercise-db (Unlicense / public domain)
873 exercises, each with instructions + two demo frames (start / end position).
Those two frames are what the app loops as an animated demo — no video
hosting, works offline, and it is real movement data rather than a stock clip.

Writes:
  mobile/assets/data/exercises.json          (app schema)
  mobile/assets/exercises/<id>_0.jpg, <id>_1.jpg  (demo frames, FLAT)

Run:  python scripts/catalog/build_catalog.py [--limit-per-equipment 6]
"""
from __future__ import annotations

import argparse
import json
import re
import urllib.request
from pathlib import Path

SRC_JSON = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
SRC_IMG = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

ROOT = Path(__file__).resolve().parents[2] / "mobile"
DATA_OUT = ROOT / "assets" / "data" / "exercises.json"
IMG_OUT = ROOT / "assets" / "exercises"

# Our catalog's equipment ids -> how to spot matching source rows.
# `equipment` matches the source's equipment field; `any` / `none` are
# name-keyword filters so e.g. a barbell bench press lands on bench_press,
# not on the generic barbell shelf.
EQUIPMENT_RULES: dict[str, dict] = {
    "bench_press": {"any": ["bench press"], "equipment": None},
    "leg_press": {"any": ["leg press", "sled"], "equipment": None},
    "lat_pulldown": {"any": ["pulldown", "pull-down"], "equipment": None},
    "squat_rack": {"any": ["squat"], "equipment": ["barbell"],
                   "none": ["dumbbell", "kettlebell", "bodyweight"]},
    "rowing_machine": {"any": ["row"], "equipment": ["machine", "other"]},
    "treadmill": {"any": ["run", "sprint", "jog", "walk"], "equipment": None},
    "kettlebell": {"equipment": ["kettlebells"]},
    "dumbbell": {"equipment": ["dumbbell"]},
    "barbell": {"equipment": ["barbell"], "none": ["squat", "bench press"]},
    "cable_machine": {"equipment": ["cable"], "none": ["pulldown"]},
    # `None` equipmentId in our schema means bodyweight / "workout at home".
    None: {"equipment": ["body only"]},
}

# Source muscle vocabulary -> ours (see ExerciseItem.muscles usage in
# workout_player_page._restSecondsFor, which keys off these names).
MUSCLE_MAP = {
    "abdominals": "core", "abductors": "glutes", "adductors": "adductors",
    "biceps": "biceps", "calves": "calves", "chest": "chest",
    "forearms": "forearms", "glutes": "glutes", "hamstrings": "hamstrings",
    "lats": "lats", "lower back": "lower_back", "middle back": "back",
    "neck": "neck", "quadriceps": "quads", "shoulders": "shoulders",
    "traps": "traps", "triceps": "triceps",
}

# Injury flags the app filters on. Keyed to the muscles a movement loads, so
# a user who flagged a knee keeps squats out of their plan.
CONTRA_BY_MUSCLE = {
    "quads": "knee", "hamstrings": "knee", "lower_back": "lower_back",
    "shoulders": "shoulder", "biceps": "elbow", "triceps": "elbow",
}
LEVEL_MAP = {"beginner": "beginner", "intermediate": "intermediate",
             "expert": "advanced"}


def _fetch_json(url: str):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def _matches(row: dict, rule: dict) -> bool:
    name = row["name"].lower()
    eq = (row.get("equipment") or "").lower()
    if rule.get("equipment") is not None and eq not in rule["equipment"]:
        return False
    if any(k in name for k in rule.get("none", [])):
        return False
    if rule.get("any") and not any(k in name for k in rule["any"]):
        return False
    return True


def _slug(source_id: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", source_id.lower()).strip("_")


def _to_app(row: dict, equipment_id: str | None) -> dict:
    muscles = [MUSCLE_MAP.get(m, m) for m in row.get("primaryMuscles", [])]
    muscles += [MUSCLE_MAP.get(m, m) for m in row.get("secondaryMuscles", [])]
    seen: list[str] = []
    for m in muscles:
        if m not in seen:
            seen.append(m)
    contra = sorted({CONTRA_BY_MUSCLE[m] for m in seen if m in CONTRA_BY_MUSCLE})
    steps = row.get("instructions", [])
    return {
        "id": _slug(row["id"]),
        "title": row["name"],
        "equipmentId": equipment_id,
        "muscles": seen,
        "primaryMuscles": [MUSCLE_MAP.get(m, m)
                           for m in row.get("primaryMuscles", [])],
        "difficulty": LEVEL_MAP.get(row.get("level", "beginner"), "beginner"),
        "durationMinutes": 8 if row.get("mechanic") == "compound" else 6,
        "summary": steps[0] if steps else "",
        "steps": steps,
        # Flat filenames, NOT one directory per exercise. A pubspec entry
        # like `- assets/exercises/` covers only the files sitting directly
        # in that directory -- Flutter does not recurse into subdirectories.
        # The per-exercise-folder layout meant all 132 frames were silently
        # left out of the APK and every demo rendered "Demo unavailable".
        "frames": [f"assets/exercises/{_slug(row['id'])}_{i}.jpg"
                   for i in range(len(row.get("images", [])[:2]))],
        "contraindications": contra,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit-per-equipment", type=int, default=6)
    args = ap.parse_args()

    source = _fetch_json(SRC_JSON)
    print(f"source rows: {len(source)}")

    out: list[dict] = []
    used_ids: set[str] = set()
    for equipment_id, rule in EQUIPMENT_RULES.items():
        picked = 0
        for row in source:
            if picked >= args.limit_per_equipment:
                break
            if len(row.get("images", [])) < 2:
                continue  # no demo frames -> useless for the animation
            if _slug(row["id"]) in used_ids:
                continue
            if not _matches(row, rule):
                continue
            item = _to_app(row, equipment_id)
            out.append(item)
            used_ids.add(item["id"])
            picked += 1
        print(f"  {equipment_id or 'bodyweight':<16} {picked}")

    # Fetch the two demo frames for everything we kept.
    IMG_OUT.mkdir(parents=True, exist_ok=True)
    by_id = {_slug(r["id"]): r for r in source}
    for item in out:
        row = by_id[item["id"]]
        for i, rel in enumerate(row["images"][:2]):
            # Flat, for the packaging reason documented in _to_app.
            dest = IMG_OUT / f"{item['id']}_{i}.jpg"
            if dest.exists():
                continue
            url = SRC_IMG + urllib.parse.quote(rel)
            with urllib.request.urlopen(url, timeout=60) as r:
                dest.write_bytes(r.read())
    print(f"exercises written: {len(out)}")
    DATA_OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False),
                        encoding="utf-8")
    print(f"-> {DATA_OUT}")


if __name__ == "__main__":
    import urllib.parse  # noqa: E402  (used in main)
    main()
