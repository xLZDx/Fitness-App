# -*- coding: utf-8 -*-
"""Leave the legacy catalog playing licensed clips or nothing at all.

WHY THIS EXISTS

`exercises.json` was filled from a library of 677 clips pulled out of a public
Drive folder, before the animation pack was bought. My own commit at the time
said it plainly: *"these clips came from a public Drive folder and carry none
[no licence]. They are a development scaffold"*. They were uploaded to
`traidingbot-b4061-videos-eu`, which grants `objectViewer` to `allUsers`.

They were never taken back out. Measured on the catalog as shipped:

    41   entries fully licensed
    101  entries MIXED -- one body licensed, the other still the scaffold
    223  entries fully scaffold
    146  entries with no clip at all

So 324 of 511 entries still served unlicensed footage over permanent public
URLs. The commit that introduced the licensed clips said "142 exercises play
licensed clips", which was true and hid the more useful fact: 101 of those 142
were only half converted, because the importer fills a body at a time and
nothing ever checked the other one.

Operator: *"мы же вроде договорились использовать только вендор ресурсы"*.

WHAT IT DOES

1. Applies `core/subset_verdicts.csv` -- the 48 subset candidates, judged one
   by one against the frames rather than against their filenames. 13 of them
   point at a DIFFERENT vendor clip than the name-matching heuristic chose,
   because the heuristic picked `Archer push up` for "Push-Up" while
   `Normal Push-up` sat in the same library, and `Kipping Pull Up` for
   "Pullups" while `pull up normal grip` did too.

2. Removes every remaining `http` URL from `video`. An entry left with nothing
   is not a regression to fix here: H1's rule already hides an exercise the app
   cannot demonstrate, so it stops being offered rather than appearing broken.

Usage:
    python scripts/catalog/relicense_legacy_catalog.py           # measure
    python scripts/catalog/relicense_legacy_catalog.py --write
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_bundle_clips import load_plan  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises.json"
VERDICTS = ROOT / "core" / "subset_verdicts.csv"


def is_scaffold(value: object) -> bool:
    """A public URL is the unlicensed library; an object key is the licensed one."""
    return str(value).startswith("http")


def census(catalog: list[dict]) -> collections.Counter:
    out = collections.Counter()
    for entry in catalog:
        video = entry.get("video") or {}
        if not video:
            out["no clip"] += 1
            continue
        scaffold = [b for b, s in video.items() if is_scaffold(s)]
        licensed = [b for b, s in video.items() if not is_scaffold(s)]
        if scaffold and licensed:
            out["mixed"] += 1
        elif scaffold:
            out["scaffold only"] += 1
        else:
            out["licensed"] += 1
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_id = {e["id"]: e for e in catalog}
    plan = load_plan()

    print("BEFORE")
    for name, n in census(catalog).most_common():
        print(f"  {n:4}  {name}")

    # --- 1. the 48, as judged -------------------------------------------
    applied = collections.Counter()
    for row in csv.DictReader(VERDICTS.open(encoding="utf-8")):
        if row["verdict"] == "reject":
            applied["rejected -- left with no licensed clip"] += 1
            continue
        entry = by_id.get(row["id"])
        if entry is None:
            sys.exit(f"verdict names an exercise the catalog does not have: {row['id']}")
        keys = plan.get(row["vendor_stem"])
        if not keys:
            sys.exit(f"verdict names a clip the bundle does not have: {row['chosen_clip']}")
        video = dict(entry.get("video") or {})
        for body in ("girl", "men"):
            if body in keys:
                video[body] = keys[body]
        entry["video"] = video
        applied[row["verdict"]] += 1

    print("\nVERDICTS")
    for name, n in applied.most_common():
        print(f"  {n:4}  {name}")

    # --- 2. the scaffold comes out --------------------------------------
    stripped_entries = stripped_bodies = emptied = 0
    for entry in catalog:
        video = entry.get("video") or {}
        if not video:
            continue
        keep = {b: s for b, s in video.items() if not is_scaffold(s)}
        if len(keep) == len(video):
            continue
        stripped_entries += 1
        stripped_bodies += len(video) - len(keep)
        if keep:
            entry["video"] = keep
        else:
            # Removed, not left as an empty object: `playableVideoFor` reads
            # "has a video" from the field being there at all, and an entry
            # holding {} would claim a demonstration it cannot play.
            entry.pop("video", None)
            emptied += 1

    print("\nUNLICENSED FOOTAGE REMOVED")
    print(f"  {stripped_entries:4}  entries touched")
    print(f"  {stripped_bodies:4}  clip references dropped")
    print(f"  {emptied:4}  entries left with no clip (H1 hides these)")

    print("\nAFTER")
    for name, n in census(catalog).most_common():
        print(f"  {n:4}  {name}")

    remaining = [e["id"] for e in catalog
                 if any(is_scaffold(s) for s in (e.get("video") or {}).values())]
    if remaining:
        sys.exit(f"still unlicensed: {remaining[:5]}")
    print("\n  0 unlicensed references remain")

    if args.write:
        CATALOG.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nwrote {CATALOG}")
    else:
        print("\nnothing written -- pass --write to apply")


if __name__ == "__main__":
    main()
