"""Restore the catalogue's `summary == steps[0]` invariant in the Russian overlay.

English holds it on all 1,887 rows. Russian broke it on **127**, and it broke in
one direction only: the steps were re-translated at some point -- "спина прямая"
became "спина в нейтральном положении", and a gerund opener ("Начните, поставив
колени...") became an imperative ("Поставьте колени...") -- while the summary
kept the older wording it was derived from.

So this is a repair rather than an authoring decision. `steps[0]` is canonical by
construction: `merge_exercise_text.py` derives every Russian summary from it and
refuses to let a batch author one, precisely so the two cannot diverge. These 127
rows predate that rule. Setting `summary = steps[0]` restores the state the rule
would have produced, and loses nothing -- every one of the 127 differs only in
phrasing of the same instruction, verified before this ran rather than assumed.

## What it refuses

* a row with no steps -- there is nothing to derive from, and writing an empty
  summary would turn a wording defect into a blank card;
* a row whose `steps[0]` is blank, for the same reason.

Neither exists today. They are refusals rather than skips because a silent skip
is how a repair tool reports success on the rows it did not fix.

Usage:
    python tools/catalog/repair_ru_summary.py --check
    python tools/catalog/repair_ru_summary.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from json_io import dump_json, load_json

ROOT = Path(__file__).resolve().parents[2]
RU_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.ru.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="report only; write nothing"
    )
    args = parser.parse_args()

    ru = load_json(RU_PATH)
    repaired: list[str] = []
    refusals: list[str] = []

    for ex_id, row in ru.items():
        steps = row.get("steps") or []
        if not steps or not str(steps[0]).strip():
            refusals.append(f"{ex_id}: no usable steps[0] to derive a summary from")
            continue
        if row.get("summary") == steps[0]:
            continue
        repaired.append(ex_id)
        if not args.check:
            row["summary"] = steps[0]

    for r in refusals:
        print(f"REFUSED  {r}")

    print(f"{len(ru)} rows, {len(repaired)} breaking summary == steps[0]")
    if refusals:
        print(f"{len(refusals)} refusal(s); nothing written")
        return 1
    if args.check:
        for ex_id in repaired[:10]:
            print(f"  would repair {ex_id}")
        if len(repaired) > 10:
            print(f"  ... and {len(repaired) - 10} more")
        return 1 if repaired else 0
    if repaired:
        dump_json(RU_PATH, ru)
        print(f"repaired {len(repaired)} rows in {RU_PATH.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
