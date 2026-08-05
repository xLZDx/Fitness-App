# -*- coding: utf-8 -*-
"""Turn one muscle group's clip gaps into the file Exercise Animatic asked for.

WHY A SCRIPT AND NOT A ONE-OFF EXPORT

The vendor will not evaluate 1,235 rows at once. Their instruction (reply of
2026-08-06, recorded in `core/BACKLOG_2026-07-31.md` E4.2) is one group at a
time, starting with Legs, then Shoulders, then Back. So this runs at least
three times, and the second and third runs must produce a file shaped exactly
like the first -- otherwise whoever reads them has to re-learn the layout, and
the differences read as meaning.

WHAT THE VENDOR ASKED FOR, AND WHY THE COLUMNS STOP THERE

Six fields: our internal id, the exact exercise name, the file name we already
have, which gendered version is missing, variation notes, and a reference link
where the name is ambiguous. That is the whole list, and it is the whole list
here.

Equipment and difficulty are in our gap CSV and are NOT exported. They would
look helpful and are not: the exercise name already carries the variation
("Barbell Bulgarian Split Squat Left Side View"), so an Equipment column mostly
repeats a word already in the name. A request to a third party is processed
faster when it matches the shape they asked for, and every extra column is a
question the reader has to decide whether to act on.

WHAT IS LEFT EMPTY, HONESTLY

`Variation Notes` and `Reference Video URL` ship blank. Notes are blank because
inside a group our titles do not collide -- measured, not assumed: the script
checks and says so. A URL column is blank because we host no public
demonstration of these movements; inventing one would be worse than an empty
cell.

WHAT THIS SCRIPT CANNOT CHECK

The vendor's own caveat: their file names and exercise titles are periodically
revised, so some of these may already exist under a different name. Nothing in
this repository describes the current state of their library, so this pass
cannot filter them out. The cover note says so in as many words rather than
letting the file imply a verified list.

Usage:
    python scripts/catalog/build_vendor_request_batch.py --group Legs
    python scripts/catalog/build_vendor_request_batch.py --group Legs --write
    python scripts/catalog/build_vendor_request_batch.py --list-groups
"""

from __future__ import annotations

import argparse
import collections
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAPS = ROOT / "core" / "vendor_clip_gaps_2026-08-05.csv"
OUT_DIR = ROOT / "core" / "vendor_requests"

# The vendor's own phrasing, in the order they listed it.
COLUMNS = [
    "Internal ID",
    "Exercise Name",
    "Existing File Name",
    "Missing Version",
    "Variation Notes",
    "Reference Video URL",
]

# Their sentence was "какого пола версия отсутствует" -- a person reads this
# column, so it says Female/Male rather than repeating our lowercase enum.
VERSION_LABEL = {"female": "Female", "male": "Male"}


def load_gaps(path: Path = GAPS) -> list[dict]:
    # utf-8-sig: the file carries a BOM, and without this the first column name
    # arrives as "﻿exercise_id" and every lookup of it silently misses.
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def groups(rows: list[dict]) -> collections.Counter:
    return collections.Counter(r["group"] for r in rows)


def file_name(reference: str) -> str:
    """The vendor's file name, not our repository path.

    Our column holds `exercises/men/Legs/barbell bulgarian split squat left
    side view.mp4`. The directories are our layout; only the last part is
    something they can search their Dropbox for.
    """
    return reference.rsplit("/", 1)[-1]


def build(rows: list[dict], group: str) -> list[dict]:
    picked = [r for r in rows if r["group"] == group]
    picked.sort(key=lambda r: r["title_en"].lower())
    out = []
    for r in picked:
        missing = r["missing_version"].strip().lower()
        out.append(
            {
                "Internal ID": r["exercise_id"],
                "Exercise Name": r["title_en"],
                "Existing File Name": file_name(r["existing_reference_clip"]),
                # Falls back to the raw value rather than to "" if the enum ever
                # grows: an unrecognised label is visible, a blank cell is not.
                "Missing Version": VERSION_LABEL.get(missing, r["missing_version"]),
                "Variation Notes": "",
                "Reference Video URL": "",
            }
        )
    return out


def ambiguous_titles(batch: list[dict]) -> list[str]:
    """Names that appear twice in this batch, i.e. where a note would be needed.

    The empty `Variation Notes` column is only defensible while this is empty,
    so it is measured on every run instead of being asserted once.
    """
    seen = collections.Counter(r["Exercise Name"].strip().lower() for r in batch)
    return sorted(t for t, n in seen.items() if n > 1)


def cover_note(group: str, batch: list[dict], date: str) -> str:
    counts = collections.Counter(r["Missing Version"] for r in batch)
    missing = ", ".join(f"{n} {k.lower()}" for k, n in sorted(counts.items()))
    return f"""# Missing clip request -- {group}

{len(batch)} exercises, {missing}.

This is the first of the per-group batches you asked for. Shoulders and Back
follow in the same format once you have reviewed this one.

Columns are as requested: internal id, exercise name, the file name we already
hold, which gendered version is missing, a blank notes column, and a blank
reference-link column.

Two things worth stating plainly:

* `Variation Notes` is blank because no two exercise names collide inside this
  batch -- the camera angle and the side are already part of the name, so there
  was nothing a note would disambiguate. It is left in place for your team to
  use.
* `Reference Video URL` is blank because we host no public demonstration of
  these movements. Where a name is unclear, the existing file name in column
  three points at the version we do have.

We have not filtered this list against the current Ultimate Bundle library. You
noted that file names and exercise titles are revised periodically, so some of
these may already exist under a different name; we have no way to check that
from our side. Please treat the list as "missing as far as our copy of the
Master Folder shows", not as verified.

Generated {date} from our catalogue by
`scripts/catalog/build_vendor_request_batch.py --group {group}`.
"""


def write_xlsx(path: Path, batch: list[dict]) -> None:
    try:
        import openpyxl
    except ImportError:
        sys.exit("pip install openpyxl")
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Missing clips"
    ws.append(COLUMNS)
    for row in batch:
        ws.append([row[c] for c in COLUMNS])
    # Width from the content, capped: the exercise names run long and a
    # default-width column shows the reader "Barbell Bulgarian Sp...".
    for i, col in enumerate(COLUMNS, start=1):
        longest = max([len(col)] + [len(str(r[col])) for r in batch])
        ws.column_dimensions[
            openpyxl.utils.get_column_letter(i)
        ].width = min(longest + 2, 60)
    ws.freeze_panes = "A2"
    wb.save(path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--group", help="muscle group to export, e.g. Legs")
    ap.add_argument("--write", action="store_true", help="write the files")
    ap.add_argument("--list-groups", action="store_true")
    ap.add_argument("--date", default="2026-08-06", help="stamp for the file name")
    args = ap.parse_args()

    rows = load_gaps()
    if args.list_groups:
        for name, n in groups(rows).most_common():
            print(f"{n:>5}  {name}")
        return 0

    if not args.group:
        ap.error("--group is required unless --list-groups")

    available = groups(rows)
    if args.group not in available:
        print(f"no such group: {args.group}", file=sys.stderr)
        print("known:", ", ".join(sorted(available)), file=sys.stderr)
        return 1

    batch = build(rows, args.group)
    clashes = ambiguous_titles(batch)

    print(f"{args.group}: {len(batch)} rows")
    for version, n in collections.Counter(
        r["Missing Version"] for r in batch
    ).most_common():
        print(f"  missing {version.lower()}: {n}")
    if clashes:
        print(
            f"  WARNING: {len(clashes)} duplicated exercise names -- "
            "Variation Notes must be filled for these before sending:"
        )
        for t in clashes:
            print(f"    {t}")
    else:
        print("  no duplicated names, so blank Variation Notes is safe")

    slug = args.group.lower().replace(" ", "_").replace("-", "_")
    stem = OUT_DIR / f"{slug}_{args.date}"
    if not args.write:
        print(f"\ndry run -- would write {stem}.xlsx, {stem}.csv, {stem}.md")
        print("re-run with --write")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # CSV twin of the xlsx: the spreadsheet is what the vendor asked for, the
    # CSV is what a diff can read.
    with (stem.with_suffix(".csv")).open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(batch)
    write_xlsx(stem.with_suffix(".xlsx"), batch)
    (stem.with_suffix(".md")).write_text(
        cover_note(args.group, batch, args.date), encoding="utf-8"
    )
    print(f"\nwrote {stem}.xlsx, {stem}.csv, {stem}.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
