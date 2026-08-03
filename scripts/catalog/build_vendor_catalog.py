# -*- coding: utf-8 -*-
"""Turn the purchased library into a catalog of its own.

WHY THIS EXISTS AT ALL

The first attempt matched vendor clips onto our existing 511 titles. That put
every exercise's fate in the hands of a name comparison, and the comparison is
not up to it: `Alternating Renegade Row` and `dumbbell renegade row` are the
same movement and share one significant word. 94 of our exercises were reported
as "no vendor candidate" when a direct search of the archive finds most of them
under different phrasing.

Operator: *"мы же вроде договорились использовать только вендор ресурсы, какой
смысл сравнивать с тем что было"*. Right. This builds the vendor library as its
own list -- all 1,899 movements, complete, with no matching involved. Our 511
keep their Russian, their contraindications and their machine links; the two
lists sit side by side and the legacy one can be switched off.

WHAT EACH ENTRY GETS

    id          a slug from the vendor's own name, prefixed `ea_`
    title       the vendor's name, tidied
    video       object keys, per body, straight from the import plan
    muscles     from their metadata sheet (79% filled)
    steps/tips  likewise
    equipment   their free-text string, kept verbatim for now

Difficulty and duration are ours to invent and we do not have them, so they get
values that say so rather than a confident-looking guess: every entry is
`beginner`/10 minutes until something real replaces them. Nothing in the app
treats those as facts about the exercise -- difficulty only feeds tier sorting.

Usage:
    python scripts/catalog/build_vendor_catalog.py            # measure
    python scripts/catalog/build_vendor_catalog.py --write
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bundle_layout import canonical_stem, plan_import, split_gender  # noqa: E402
from match_vendor_list import norm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
BUNDLE_ZIP = Path("D:/Downloads/4K UHD 2160P.zip")
VENDOR_META = Path("D:/Downloads/1500+ exercise data.xlsx")

# The vendor's twelve folders, mapped to the muscle vocabulary the app already
# uses for filtering and for the muscle map. Only used when their metadata sheet
# has nothing -- a folder is a much weaker signal than a filled-in row.
GROUP_MUSCLES = {
    "Abdominals": ["core"],
    "Back": ["back"],
    "Biceps": ["biceps"],
    "Chest": ["chest"],
    "Forearms": ["forearms"],
    "Legs": ["quads"],
    "Shoulders": ["shoulders"],
    "Triceps": ["triceps"],
    # Four folders name no muscle honestly, so they get none. `full_body` and
    # `mobility` were the obvious inventions and both are wrong: neither is one
    # of the fifteen tags the app renders, so they would have shown as blank
    # chips and been invisible to the injury filter — the exact failure the
    # note on APP_MUSCLES describes, committed two functions later by me.
    #
    # An exercise with no tag still appears in every list and under its
    # equipment; it is only absent from a muscle chip, which is honest, because
    # we genuinely do not know which muscle a "Calisthenics" clip trains.
    "Calisthenics-Cardio-Plyo-Functional": [],
    "Powerlifting": [],
    "Stretching - Mobility": [],
    "Yoga": [],
}

STRETCH_GROUPS = {"Stretching - Mobility", "Yoga"}

# The app understands exactly fifteen muscle tags — the vocabulary already in
# `exercises.json`, read by the muscle map, the muscle chips and the injury
# filter. Anything that does not map lands here as nothing rather than as a new
# tag: an unrecognised value would show as an empty chip and, worse, would be
# invisible to `filterContraindicated`, so an exercise could slip past a user's
# injury because its muscle was spelled in a way the filter never heard of.
APP_MUSCLES = {
    "adductors", "back", "biceps", "calves", "chest", "core", "forearms",
    "glutes", "hamstrings", "lats", "lower_back", "quads", "shoulders",
    "traps", "triceps",
}

# Their vocabulary against ours. Written from the actual column values, which
# are phrased `Glutes (Gluteus Maximus, Gluteus Medius)` — the Latin sits in
# brackets and contains its own commas, which is why the brackets are stripped
# before anything is split. Splitting first produced tags like
# `gluteus mideus)` and mapped nothing at all.
MUSCLE_ALIASES = {
    "abdominals": "core", "abs": "core", "core": "core", "obliques": "core",
    "rectus abdominis": "core", "transverse abdominis": "core",
    "lower back": "lower_back", "erector spinae": "lower_back",
    "lats": "lats", "latissimus dorsi": "lats", "middle back": "lats",
    "back": "back", "upper back": "traps", "trapezius": "traps",
    "traps": "traps", "rhomboids": "back", "teres major": "back",
    "chest": "chest", "pectoralis major": "chest", "pectorals": "chest",
    "shoulders": "shoulders", "deltoids": "shoulders", "delts": "shoulders",
    "rotator cuff": "shoulders",
    "biceps": "biceps", "triceps": "triceps", "forearms": "forearms",
    "brachioradialis": "forearms", "brachialis": "biceps",
    "quadriceps": "quads", "quads": "quads",
    "hamstrings": "hamstrings",
    "glutes": "glutes", "gluteus maximus": "glutes", "gluteus medius": "glutes",
    "calves": "calves", "soleus": "calves", "gastrocnemius": "calves",
    "adductors": "adductors", "abductors": "glutes",
    # No tag of our own, and the nearest honest home for each. Hip flexors and
    # the spinal erectors both sit with the lower back for filtering purposes;
    # a "full body" movement is left untagged rather than given all fifteen.
    "hip flexors": "lower_back", "iliopsoas": "lower_back",
    "spinal erectors": "lower_back",
}


def slug(name: str) -> str:
    """`'Barbell Full Squat'` -> `'ea_barbell_full_squat'`.

    Prefixed so a vendor entry is recognisable at a glance in a log, a
    Firestore document or a bug report, and can never collide with the
    `fedb_` / `vid_` / hand-authored ids already in use.
    """
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return f"ea_{s}" or "ea_unnamed"


def tidy_title(stem: str) -> str:
    """Their filenames are cased at random -- `barbell full squat`, `AB Wheel
    Pulses`, `Dumbbell Fly`. Title-case everything so one list does not look
    like three imports."""
    small = {"to", "on", "in", "with", "and", "the", "a", "of", "or", "at"}
    words = canonical_stem(stem).split()
    out = []
    for i, w in enumerate(words):
        # Strip punctuation before testing for an acronym, or `POV)` fails
        # `isupper()` on the bracket and comes out as `Pov)`.
        core = w.strip("()[[]{}.,:-")
        if core.isupper() and 1 < len(core) <= 4:
            out.append(w)  # AB, EZ, TRX, POV
        elif i and w.lower() in small:
            out.append(w.lower())
        else:
            out.append(w[:1].upper() + w[1:].lower())
    return " ".join(out)


def load_metadata() -> dict[str, dict]:
    try:
        import openpyxl
    except ImportError:
        sys.exit("pip install openpyxl")
    wb = openpyxl.load_workbook(VENDOR_META, read_only=True)
    rows = list(wb.active.iter_rows(min_row=2, values_only=True))
    wb.close()
    out: dict[str, dict] = {}
    for row in rows:
        name = str(row[1] or "").strip()
        if not name:
            continue
        stem, _ = split_gender(name)
        key = " ".join(sorted(set(norm(canonical_stem(stem)))))
        filled = any(row[i] not in (None, "") for i in (2, 3, 4, 5, 6))
        # A filled row beats an empty one for the same movement; otherwise the
        # first wins. Their sheet has a row per gender and often fills only one.
        if key not in out or (filled and not out[key]["filled"]):
            out[key] = {
                "steps": row[2], "tips": row[3], "primary": row[4],
                "secondary": row[5], "equipment": row[6], "filled": filled,
            }
    return out


def split_steps(value) -> list[str]:
    if not value:
        return []
    text = str(value).replace("\r", "")
    parts = [p.strip() for p in text.split("\n")]
    # Their numbering is inconsistent ("1.", "1)", "Step 1:"); strip it so the
    # app's own numbered list does not read "1. 1. Stand with...".
    cleaned = [re.sub(r"^(step\s*)?\d+[\.\)\:]\s*", "", p, flags=re.I) for p in parts]
    return [c.strip(" .;\t") for c in cleaned if c.strip(" .;\t")]


def split_muscles(value) -> list[str]:
    """`'Glutes (Gluteus Maximus, Gluteus Medius), Quadriceps'` -> `['glutes',
    'quads']`.

    Brackets go first. Their Latin names live inside them and carry their own
    commas, so splitting before stripping tore `Glutes (Gluteus Maximus,
    Gluteus Medius)` into `glutes (gluteus maximus` and `gluteus mideus)` —
    two tokens, neither of which maps, which is why every generated entry came
    out with no primary muscle at all.
    """
    if not value:
        return []
    text = re.sub(r"\([^)]*\)", " ", str(value).lower())
    out: list[str] = []
    for token in re.split(r"[,/;]| and ", text):
        token = token.strip(" .")
        mapped = MUSCLE_ALIASES.get(token)
        if mapped and mapped in APP_MUSCLES and mapped not in out:
            out.append(mapped)
    return out


def build() -> list[dict]:
    with zipfile.ZipFile(BUNDLE_ZIP) as z:
        members = {i.filename: i.file_size for i in z.infolist() if not i.is_dir()}
    plan = plan_import(members)
    meta = load_metadata()

    by_stem: dict[str, dict] = {}
    for key in sorted(plan.chosen):
        _, body, group, filename = key.split("/", 3)
        stem = canonical_stem(filename.rsplit("/", 1)[-1][:-4])
        norm_key = " ".join(sorted(set(norm(stem))))
        entry = by_stem.setdefault(norm_key, {
            "stem": stem, "group": group, "video": {},
        })
        entry["video"][body] = key
        # The men's spelling wins the title when both exist, purely so the
        # choice is deterministic rather than dependent on dict order.
        if body == "men":
            entry["stem"] = stem

    out: list[dict] = []
    seen_ids: set[str] = set()
    for norm_key, e in by_stem.items():
        m = meta.get(norm_key, {})
        muscles = split_muscles(m.get("primary")) + split_muscles(m.get("secondary"))
        primary = split_muscles(m.get("primary"))
        if not muscles:
            muscles = list(GROUP_MUSCLES.get(e["group"], []))
        exercise_id = slug(e["stem"])
        if exercise_id in seen_ids:
            # Two different vendor spellings that slug the same. Keep both and
            # make the second distinct rather than silently dropping a clip.
            n = 2
            while f"{exercise_id}_{n}" in seen_ids:
                n += 1
            exercise_id = f"{exercise_id}_{n}"
        seen_ids.add(exercise_id)

        steps = split_steps(m.get("steps"))
        tips = split_steps(m.get("tips"))
        row = {
            "id": exercise_id,
            "title": tidy_title(e["stem"]),
            "equipmentId": None,
            "muscles": muscles,
            "primaryMuscles": primary,
            # Ours to invent and we do not have it. `beginner`/10 is the value
            # that says "unknown" here; difficulty only feeds tier sorting and
            # duration only feeds a label.
            "difficulty": "beginner",
            "durationMinutes": 10,
            "summary": steps[0] if steps else "",
            "steps": steps,
            "video": e["video"],
            "isStretch": e["group"] in STRETCH_GROUPS,
            "vendorGroup": e["group"],
        }
        if tips:
            row["tips"] = tips
        # An entry the sheet says nothing about is UNKNOWN, not bodyweight.
        # 496 of the 1,899 have no equipment column at all, and leaving the
        # field null made `needsEquipment` read them as needing nothing —
        # which put them in an "at home" tab that promises exactly that.
        row["equipmentLabel"] = (
            str(m["equipment"]).strip() if m.get("equipment") else "Unknown"
        )
        out.append(row)

    out.sort(key=lambda r: r["title"].lower())
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    rows = build()
    print(f"vendor exercises   {len(rows)}")
    print(f"  both bodies      {sum(1 for r in rows if len(r['video']) == 2)}")
    print(f"  with steps       {sum(1 for r in rows if r['steps'])}")
    print(f"  with tips        {sum(1 for r in rows if r.get('tips'))}")
    print(f"  with muscles     {sum(1 for r in rows if r['muscles'])}")
    print(f"  stretch/mobility {sum(1 for r in rows if r['isStretch'])}")
    print(f"  with equipment   {sum(1 for r in rows if r.get('equipmentLabel'))}")
    groups = collections.Counter(r["vendorGroup"] for r in rows)
    print(f"  groups           {dict(sorted(groups.items()))}")

    if args.write:
        OUT.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nwrote {OUT}  ({OUT.stat().st_size / 1e6:.2f} MB)")
    else:
        print("\nnothing written -- pass --write")


if __name__ == "__main__":
    main()
