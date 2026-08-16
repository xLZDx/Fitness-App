"""Give an exercise that names a machine an equipment label that agrees with it.

78 of the 1,887 rows carry `equipmentLabel: "None"` while `equipmentId` names a
real machine in the registry -- 25 of them a weight bench, 19 a cable machine.
That is not a cosmetic mismatch. Two places read it:

* `exercise_reference.dart:315` renders the label verbatim on the exercise card,
  so 78 exercises tell the user they need nothing and then ask for a cable
  machine in step one;
* `exercise_filter.dart:459-465` already carries a workaround for exactly this
  contradiction, with the comment "the label says nothing is needed while an
  `equipmentId` names a machine. Believe the id." The filter is therefore
  already correct -- but a guard written around corrupt data is evidence of the
  corruption, not a substitute for fixing it.

## The repair

`equipment.json` is the registry, and every one of the 78 ids resolves in it, so
the label is derived rather than authored: `equipmentLabel = registry name`.

## The three states, kept distinct

The point of this tool is that "no equipment" and "equipment we cannot name" are
different facts and must not both be written as `None`:

* `NO_EQUIPMENT`    -- no `equipmentId`. The label is the vendor's own free text
                       and is left alone: "None", "Yoga Mat", "Wall", "Chair".
                       `ExerciseItem.needsEquipment` already reads these.
* `KNOWN_EQUIPMENT` -- `equipmentId` resolves in the registry. The label must
                       name it. This is what gets repaired.
* `UNKNOWN_EQUIPMENT` -- `equipmentId` set and NOT in the registry. Zero rows
                       today. It is still a **refusal** rather than a skip,
                       because inventing a label for an id nothing resolves
                       would write a confident-looking guess into the catalogue.

Usage:
    python tools/catalog/repair_equipment_label.py --check
    python tools/catalog/repair_equipment_label.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from json_io import dump_json, load_json

ROOT = Path(__file__).resolve().parents[2]
EN_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
EQUIPMENT_PATH = ROOT / "mobile" / "assets" / "data" / "equipment.json"

# The labels that assert "nothing is needed". Compared case-insensitively
# because the catalogue holds both "None" and "none".
SAYS_NOTHING = {"none", ""}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="report only; write nothing"
    )
    args = parser.parse_args()

    rows = load_json(EN_PATH)
    registry = {e["id"]: e.get("name") for e in load_json(EQUIPMENT_PATH)}

    no_equipment = 0
    known = 0
    repaired: list[tuple[str, str, str]] = []
    refusals: list[str] = []

    for row in rows:
        eid = row.get("equipmentId")
        if eid is None:
            no_equipment += 1
            continue
        if eid not in registry:
            refusals.append(
                f"{row['id']}: equipmentId {eid!r} is in no registry entry — "
                f"UNKNOWN_EQUIPMENT, and no label can be derived for it"
            )
            continue
        known += 1
        name = registry[eid]
        if not name or not str(name).strip():
            refusals.append(f"{row['id']}: registry entry {eid!r} has no name")
            continue
        label = (row.get("equipmentLabel") or "").strip().lower()
        if label in SAYS_NOTHING:
            repaired.append((row["id"], eid, name))
            if not args.check:
                row["equipmentLabel"] = name

    print(f"{len(rows)} rows: {no_equipment} NO_EQUIPMENT, {known} KNOWN_EQUIPMENT, "
          f"{len(refusals)} UNKNOWN_EQUIPMENT")
    print(f"{len(repaired)} claim no equipment while naming a machine")

    for r in refusals:
        print(f"REFUSED  {r}")
    if refusals:
        print(f"\n{len(refusals)} refusal(s); nothing written")
        return 1

    if args.check:
        for ex_id, eid, name in repaired[:10]:
            print(f"  would set {ex_id}: None -> {name!r} ({eid})")
        if len(repaired) > 10:
            print(f"  ... and {len(repaired) - 10} more")
        return 1 if repaired else 0

    if repaired:
        dump_json(EN_PATH, rows)
        print(f"repaired {len(repaired)} labels in {EN_PATH.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
