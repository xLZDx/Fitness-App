"""Merge authored exercise text into the shipped catalogue.

B3. The purchased library delivered 403 of its 1,887 rows with `summary` and
`steps` empty in BOTH languages, while every one of those rows DOES carry a
demonstration clip. Nothing in the app is missing: the player renders steps the
moment they exist. What is missing is the prose, and writing it is authoring.

This merges a batch of authored text into `exercises_vendor.json` (English) and
`exercises_vendor.ru.json` (Russian overlay, a dict keyed by exercise id).

Batch file shape:

    {
      "ea_kettlebell_wrist_curl": {
        "en": {"purpose": "why anyone does this", "steps": ["...", "..."]},
        "ru": {"purpose": "...", "steps": ["...", "..."]}
      }
    }

`summary` is NOT authored. The catalogue's own invariant is that a row's
`summary` is byte-identical to its first step -- the Russian overlay stores only
`title` and `steps` and derives the summary from step one, and
`test/features/equipment/exercise_translations_test.dart` fails the build if the
two ever diverge. So this tool derives it, and a batch cannot break the rule by
hand even if its author forgets the rule exists.

`purpose` is a NEW field, added by B3 for the same reason: the catalogue had
nowhere to say what an exercise is FOR. Operator, 2026-08-13, asking for the
steps and "для чего это нужно" -- the second half had no field to live in.

Refusals, all of them deliberate and all of them fatal rather than warned:

* an id the catalogue does not contain -- a typo in a batch would otherwise
  write text nobody ever reads and report success;
* an id whose text is ALREADY non-empty -- this tool fills gaps, it never
  overwrites what the vendor shipped, and "merge" is exactly the operation that
  quietly destroys data when it is allowed to;
* a batch missing either language -- shipping English-only text means a Russian
  user sees an empty card, which is the state we are fixing.

Usage:
    python tools/catalog/merge_exercise_text.py batches/b3_forearms.json
    python tools/catalog/merge_exercise_text.py --check batches/*.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EN_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
RU_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.ru.json"

MIN_STEPS = 3


def _is_empty(value) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, list):
        return not [s for s in value if str(s).strip()]
    return False


def _load():
    en = json.loads(EN_PATH.read_text(encoding="utf-8"))
    ru = json.loads(RU_PATH.read_text(encoding="utf-8"))
    return en, ru


def _validate(batch: dict, en_by_id: dict, ru: dict) -> list[str]:
    problems: list[str] = []
    for ex_id, langs in batch.items():
        if ex_id not in en_by_id:
            problems.append(f"{ex_id}: not in the catalogue")
            continue
        if ex_id not in ru:
            problems.append(f"{ex_id}: not in the Russian overlay")
            continue

        row = en_by_id[ex_id]
        if not _is_empty(row.get("steps")) or not _is_empty(row.get("summary")):
            problems.append(f"{ex_id}: English text already present -- refusing to overwrite")
        ru_row = ru[ex_id]
        if not _is_empty(ru_row.get("steps")) or not _is_empty(ru_row.get("summary")):
            problems.append(f"{ex_id}: Russian text already present -- refusing to overwrite")

        for lang in ("en", "ru"):
            block = langs.get(lang)
            if not isinstance(block, dict):
                problems.append(f"{ex_id}: missing the '{lang}' block")
                continue
            if _is_empty(block.get("purpose")):
                problems.append(f"{ex_id}/{lang}: empty purpose")
            if "summary" in block:
                problems.append(
                    f"{ex_id}/{lang}: do not author 'summary' -- it is derived "
                    f"from step one, see the module docstring"
                )
            steps = block.get("steps")
            if not isinstance(steps, list) or len(steps) < MIN_STEPS:
                problems.append(
                    f"{ex_id}/{lang}: fewer than {MIN_STEPS} steps -- a two-line "
                    f"instruction is not an instruction"
                )
            elif any(not str(s).strip() for s in steps):
                # Counting only the non-blank entries would let
                # ["", "step", "step", "step"] through: four entries, three of
                # them real, validation satisfied. `summary` is then derived
                # from index 0 below and written as the empty string, which is
                # the exact B3 defect this tool exists to remove -- reported as
                # success, because the count was met. Every entry must be real.
                problems.append(
                    f"{ex_id}/{lang}: a blank step -- summary is taken from "
                    f"step one, so a blank entry writes an empty summary"
                )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("batches", nargs="+", type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate only; write nothing",
    )
    args = parser.parse_args()

    en, ru = _load()
    en_by_id = {row["id"]: row for row in en}

    merged: dict[str, dict] = {}
    for path in args.batches:
        batch = json.loads(path.read_text(encoding="utf-8"))
        overlap = merged.keys() & batch.keys()
        if overlap:
            print(f"FAIL {path}: ids repeated across batches: {sorted(overlap)}")
            return 1
        merged.update(batch)

    problems = _validate(merged, en_by_id, ru)
    if problems:
        print(f"FAIL: {len(problems)} problem(s)")
        for p in problems:
            print("  -", p)
        return 1

    print(f"OK: {len(merged)} exercise(s) validated")
    if args.check:
        return 0

    for ex_id, langs in merged.items():
        en_by_id[ex_id]["steps"] = langs["en"]["steps"]
        en_by_id[ex_id]["purpose"] = langs["en"]["purpose"]
        # Derived, never authored — see the module docstring.
        en_by_id[ex_id]["summary"] = langs["en"]["steps"][0]
        ru[ex_id]["steps"] = langs["ru"]["steps"]
        ru[ex_id]["purpose"] = langs["ru"]["purpose"]
        ru[ex_id]["summary"] = langs["ru"]["steps"][0]

    # Each file keeps the formatting it already has, and they do NOT have the
    # same one: the English catalogue is a list at indent 2 in vendor order, the
    # Russian overlay is a dict at indent 1 with its keys sorted. Writing both
    # the same way would reformat 94,000 lines to change twenty, and a diff
    # nobody can read is a diff nobody reviews.
    #
    # Both are serialised and staged BEFORE either is replaced. A crash between
    # two plain writes -- full disk, an antivirus lock on the second file, a
    # Ctrl-C -- would leave English filled and Russian empty, and that state is
    # not merely inconsistent, it is unrecoverable by this tool: re-running the
    # same batch hits the "English text already present" refusal above, so
    # finishing the job would need a hand-edit or a git checkout. Serialising
    # first also means a broken value raises before anything on disk changes.
    en_text = json.dumps(en, ensure_ascii=False, indent=2) + "\n"
    ru_text = json.dumps(ru, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    en_tmp = EN_PATH.with_suffix(EN_PATH.suffix + ".tmp")
    ru_tmp = RU_PATH.with_suffix(RU_PATH.suffix + ".tmp")
    try:
        en_tmp.write_text(en_text, encoding="utf-8")
        ru_tmp.write_text(ru_text, encoding="utf-8")
        # Both complete files now exist on disk. os.replace is atomic per file;
        # the pair is not, but the window is two renames of already-written
        # bytes rather than two full serialisations plus two disk writes.
        os.replace(en_tmp, EN_PATH)
        os.replace(ru_tmp, RU_PATH)
    finally:
        for tmp in (en_tmp, ru_tmp):
            tmp.unlink(missing_ok=True)

    remaining = sum(1 for row in en if _is_empty(row.get("steps")))
    print(f"written. exercises still without steps: {remaining}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
