# -*- coding: utf-8 -*-
"""Tag exercises with the movement pattern the Form Coach could judge.

WHAT A TAG MEANS

`poseTargetId: "squat"` means: this row's silhouette, seen from the side, is
the squat pattern. It does NOT mean the coach can judge it today. Whether a
pattern has hand-authored joint coordinates is a fact about the app, not about
the catalog, and it lives in `pose_target.dart` -- which is why the button is
gated on that and not on this field.

The separation is the whole point of the pass. Tagging is done once for all
1,887 rows; authoring is done once per pattern. The day a pattern's targets are
written, roughly a hundred exercises light up at the same moment with no
catalog work at all.

WHY PATTERNS AND NOT EXERCISES

A back squat, a front squat, a goblet squat, an air squat and a box squat are
one shape from the side. `poseMatchScore` removes position and overall size
before comparing, so what distinguishes them -- the load and where it sits --
is not in the signal at all. One target serves all of them.

WHAT IS DELIBERATELY NOT TAGGED

Anything a single side-on camera cannot see: seated and lying work, machines,
benches and cables that hide the hip line. The exclusions are one shared list
rather than per-pattern, because the reason is always the same. A bench press
is the clearest case and it is the operator's own example: supine, with a bench
across the hip line, and BlazePose has no spinal landmark to begin with.

DIRECTION OF ERROR

The opposite of the contraindications pass. There a false negative shows a
dangerous exercise; here a false positive merely offers a coach that scores
poorly, and the user can ignore it. So these rules do not lean toward tagging:
an untagged exercise loses a feature, a wrongly tagged one teaches the user
that the coach is unreliable, and the second costs more.

Usage:
    python scripts/catalog/tag_pose_targets.py
    python scripts/catalog/tag_pose_targets.py --write
    python scripts/catalog/tag_pose_targets.py --pattern squat
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
VOCAB = Path(__file__).with_name("pose_patterns.json")
AUDIT = ROOT / "core" / "pose_targets"

FIELD = "poseTargetId"


def load_vocab() -> tuple[list[dict], re.Pattern, re.Pattern]:
    v = json.loads(VOCAB.read_text("utf-8"))
    ex = v["excludeWhen"]
    return (
        v["patterns"],
        re.compile(ex["title"], re.I),
        re.compile(ex["equipmentLabel"], re.I),
    )


def classify(row: dict, patterns, ex_title, ex_equipment) -> tuple[str | None, str]:
    """Returns (pattern id or None, the reason).

    The reason travels into the CSV twin so a reviewer can disagree with one
    row rather than with the pass -- the same contract `tag_contraindications`
    established, and for the same reason: a tagging pass nobody can audit is a
    tagging pass nobody can correct.
    """
    title = row.get("title") or ""
    equipment = row.get("equipmentLabel") or ""

    hits = [
        p for p in patterns
        if re.search(p["matchTitle"], title, re.I)
        and not (p.get("notTitle") and re.search(p["notTitle"], title, re.I))
    ]
    if not hits:
        return None, "no pattern in the title"
    if len(hits) > 1:
        # Ambiguous by construction, e.g. "Squat to Overhead Press". Two
        # silhouettes in one movement is not something a single target can
        # score, and guessing which half the user is in is worse than saying
        # nothing.
        return None, "matches more than one pattern: " + ",".join(
            p["id"] for p in hits
        )

    if ex_title.search(title):
        return None, f"excluded by title: {ex_title.search(title).group(0)}"
    if equipment and ex_equipment.search(equipment):
        return None, f"excluded by equipment: {equipment}"

    return hits[0]["id"], "title match"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true",
                    help="apply to the catalog; without it nothing is written")
    ap.add_argument("--pattern", help="report on one pattern only")
    args = ap.parse_args()

    patterns, ex_title, ex_equipment = load_vocab()
    known = {p["id"] for p in patterns}
    if args.pattern and args.pattern not in known:
        sys.exit(f"unknown pattern {args.pattern!r}; known: "
                 + ", ".join(sorted(known)))

    rows = json.loads(CATALOG.read_text("utf-8"))
    tagged: list[tuple[str, str, str, str]] = []
    counts: collections.Counter = collections.Counter()

    for row in rows:
        pid, reason = classify(row, patterns, ex_title, ex_equipment)
        if pid is None:
            row.pop(FIELD, None)
            continue
        counts[pid] += 1
        tagged.append((row["id"], row["title"], pid, reason))
        if args.write:
            row[FIELD] = pid

    print(f"catalog rows      {len(rows)}")
    print(f"tagged            {sum(counts.values())} "
          f"({100 * sum(counts.values()) / len(rows):.1f}%)")
    print()
    for p in patterns:
        if args.pattern and p["id"] != args.pattern:
            continue
        print(f"  {p['id']:16s} {counts[p['id']]:5d}  {p['label']}")

    if args.write:
        # indent=2 + a trailing newline is what the catalog is already written
        # with -- verified by round-tripping the file before the first write,
        # rather than assumed. Guessing costs a diff of every one of the 1,887
        # rows, which buries the handful this pass actually changed.
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        AUDIT.mkdir(parents=True, exist_ok=True)
        out = AUDIT / "pose_target_tags.csv"
        with out.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["id", "title", "poseTargetId", "reason"])
            w.writerows(tagged)
        print(f"\nwrote {CATALOG.relative_to(ROOT)}")
        print(f"wrote {out.relative_to(ROOT)}")
    else:
        print("\ndry run -- re-run with --write to apply.")


if __name__ == "__main__":
    main()
