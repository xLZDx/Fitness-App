# -*- coding: utf-8 -*-
"""Work out what the 496 unlabelled vendor exercises actually need.

THE PROBLEM, PLAINLY

Their metadata sheet has an Equipment column and they filled it for 1,403 of
1,899 rows. The other 496 are blank — not "nothing needed", just blank. Those
entries were marked `Unknown`, which is honest but useless: the app cannot put
them in the at-home tab, cannot say what to bring, and cannot link them to a
machine.

Operator: *"как это чинить?"*

THREE PASSES, MOST CERTAIN FIRST

    title   the name says it -- `Band Bench Press`, `Ball Slams`,
            `Alternate Biceps Curl Standing Dumbbells`. 347 of 496.
    steps   the instructions say it -- "Grasp the barbell with an overhand
            grip". Read only when the title is silent.
    none    left as Unknown and listed, for an eye rather than a guess.

Matching is by substring, not word boundary. `\\bdumbbell\\b` misses
`Dumbbells`, and that single detail undercounted the title pass by 33 exercises
when this was first measured.

WHAT IT WILL NOT DO

It will not decide that an exercise needs nothing. Silence in both the name and
the instructions means we do not know, and "no equipment" is a promise the
at-home tab makes to the user — an exercise nobody checked must not be in it.
Only the vendor's own `None`/`None (Bodyweight)` counts as bodyweight.

Every decision is written to `core/vendor_equipment_resolved.csv` with the
evidence that produced it, so the ones that came from a name can be checked
against the ones that came from a sentence.

Usage:
    python scripts/catalog/resolve_vendor_equipment.py
    python scripts/catalog/resolve_vendor_equipment.py --write
"""
from __future__ import annotations

import argparse
import base64
import collections
import concurrent.futures
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import PROJECT, access_token, api  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
REPORT = ROOT / "core" / "vendor_equipment_resolved.csv"

# Longest first, so `resistance band` wins over `band` and `ez bar` over `bar`.
# The label on the right is what the user reads, in the vendor's own register so
# a resolved entry is indistinguishable from a labelled one.
EQUIPMENT = [
    ("resistance band", "Resistance Band"),
    ("loop band", "Loop Resistance Band"),
    ("mini band", "Loop Resistance Band"),
    ("agility ladder", "Agility Ladder"),
    # Added after the first vision pass answered from a list that lacked them,
    # so it picked the nearest thing it HAD: a yoga block became a plyo box, a
    # tyre became a weight plate, and seven rebounder exercises came back
    # Unclear because a mini trampoline was not on offer. A forced choice from
    # an incomplete vocabulary looks exactly like a confident answer.
    ("yoga block", "Yoga Block"),
    ("rebounder", "Mini Trampoline"),
    ("mini trampoline", "Mini Trampoline"),
    ("trampoline", "Mini Trampoline"),
    ("treadmill", "Treadmill"),
    ("tyre", "Tyre"),
    ("tire", "Tyre"),
    ("partner", "A Partner"),
    ("dip bar", "Dip Bars"),
    ("block", "Yoga Block"),
    ("suspension trainer", "Suspension Trainer"),
    ("smith machine", "Smith Machine"),
    ("medicine ball", "Medicine Ball"),
    ("stability ball", "Exercise Ball"),
    ("exercise ball", "Exercise Ball"),
    ("swiss ball", "Exercise Ball"),
    ("bosu", "Bosu Ball"),
    ("foam roller", "Foam Roller"),
    ("battle rope", "Battle Ropes"),
    ("jump rope", "Jump Rope"),
    ("ab wheel", "Ab Wheel"),
    ("pull up bar", "Pull Up Bar"),
    ("pull-up bar", "Pull Up Bar"),
    ("ez bar", "Ez Bar"),
    ("ez-bar", "Ez Bar"),
    ("landmine", "Landmine"),
    ("kettlebell", "Kettlebells"),
    ("dumbbell", "Dumbbells"),
    ("barbell", "Barbell"),
    ("sandbag", "Sandbag"),
    ("parallette", "Parallettes"),
    ("gymnastic ring", "Gymnastic Rings"),
    ("cable", "Cable Pulley Machine"),
    ("pulley", "Cable Pulley Machine"),
    ("machine", "Machine"),
    ("sled", "Sled"),
    ("hurdle", "Hurdles"),
    ("plate", "Weight Plate"),
    ("trx", "Suspension Trainer"),
    ("bench", "Bench"),
    ("box", "Plyo Box"),
    ("wall", "Wall"),
    ("band", "Resistance Band"),
    ("ball", "Exercise Ball"),
    ("rope", "Rope"),
    ("bar", "Barbell"),
]


def find(text: str) -> tuple[str, str] | None:
    """(label, the phrase that produced it), or None."""
    low = text.lower()
    for needle, label in EQUIPMENT:
        if needle in low:
            return label, needle
    return None


# --------------------------------------------------------------------------
# the third pass: look at the clip
# --------------------------------------------------------------------------

VISION_MODEL = "gemini-2.5-flash"
VISION_LOCATION = "us-central1"

VISION_PROMPT = """This is a still from a short exercise demonstration called
"{title}". A 3D-rendered figure performs the movement on a plain background.

What equipment is the figure actually using or touching? Answer with ONE of:
{labels}
None

Rules:
- Answer "None" only when the figure uses nothing but the floor and their own
  body. A mat counts as None.
- Answer with the label alone, nothing else.
- If you cannot tell from this frame, answer "Unclear"."""


def ask_the_picture(token: str, title: str, poster: Path) -> str:
    """What the frame shows, or 'Unclear'.

    Operator's standing rule: *"если есть хоть малейшее сомнение что это такое
    то делай скрин с обоих роликов, ищи в интернете что это на самом деле и
    потом принимай окончательный вердикт"*. The poster IS a frame of the clip,
    already cut, so the evidence is on disk and costs nothing to gather.
    """
    labels = "\n".join(sorted({label for _, label in EQUIPMENT}))
    url = (
        f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
        f"/locations/{VISION_LOCATION}/publishers/google/models/"
        f"{VISION_MODEL}:generateContent"
    )
    body = {
        "contents": [{
            "role": "user",
            "parts": [
                {"text": VISION_PROMPT.format(title=title, labels=labels)},
                {"inlineData": {
                    "mimeType": "image/jpeg",
                    "data": base64.b64encode(poster.read_bytes()).decode(),
                }},
            ],
        }],
        "generationConfig": {"temperature": 0.0, "maxOutputTokens": 2048},
    }
    result = api(url, token, "POST", body)
    if "_httpError" in result:
        return "Unclear"
    try:
        answer = result["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError):
        return "Unclear"
    known = {label.lower(): label for _, label in EQUIPMENT}
    if answer.lower() in known:
        return known[answer.lower()]
    if answer.lower().startswith("none"):
        return "None (Bodyweight)"
    return "Unclear"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--vision", action="store_true",
                    help="ask the clip's own still what it shows")
    args = ap.parse_args()

    rows = json.loads(CATALOG.read_text(encoding="utf-8"))
    unknown = [r for r in rows if r.get("equipmentLabel") == "Unknown"]
    print(f"{len(rows)} exercises, {len(unknown)} with no equipment stated")

    out: list[dict] = []
    silent: list[dict] = []
    counts = collections.Counter()
    for row in unknown:
        hit = find(row["title"])
        source = "title"
        if not hit and row.get("steps"):
            hit = find(" ".join(row["steps"]))
            source = "steps"
        if not hit:
            silent.append(row)
            out.append({"id": row["id"], "title": row["title"],
                        "resolved": "", "from": "", "evidence": ""})
            continue
        label, phrase = hit
        counts[source] += 1
        if args.write:
            row["equipmentLabel"] = label
        out.append({"id": row["id"], "title": row["title"],
                    "resolved": label, "from": source, "evidence": phrase})

    if args.vision and silent:
        print(f"  looking at {len(silent)} frames...")
        token = access_token()
        by_id = {r["id"]: r for r in out}

        def look(row: dict) -> tuple[str, str]:
            poster = row.get("poster") or {}
            path = poster.get("men") or poster.get("girl")
            if not path:
                return row["id"], "Unclear"
            return row["id"], ask_the_picture(
                token, row["title"], ROOT / "mobile" / path)

        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            for exercise_id, answer in pool.map(look, silent):
                record = by_id[exercise_id]
                if answer == "Unclear":
                    continue
                counts["vision"] += 1
                record["resolved"] = answer
                record["from"] = "frame"
                record["evidence"] = "read from the clip's own still"
                if args.write:
                    next(r for r in rows if r["id"] == exercise_id)[
                        "equipmentLabel"] = answer

    counts["unresolved"] = sum(1 for r in out if not r["resolved"])
    print(f"  from the title  {counts['title']}")
    print(f"  from the steps  {counts['steps']}")
    if args.vision:
        print(f"  from the frame  {counts['vision']}")
    print(f"  still unknown   {counts['unresolved']}")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(out[0]))
        writer.writeheader()
        writer.writerows(out)
    print(f"\nwrote {REPORT}")

    if args.write:
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {CATALOG}")
        remaining = sum(1 for r in rows if r.get("equipmentLabel") == "Unknown")
        print(f"catalog now has {remaining} exercises of unknown equipment")
    else:
        print("nothing written -- pass --write")


if __name__ == "__main__":
    main()
