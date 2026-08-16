"""Correct exercise text that is already in the catalogue and is wrong.

`merge_exercise_text.py` fills gaps and refuses, fatally, to overwrite text that
is already there. That refusal is right: "merge" is the operation that quietly
destroys authored work when it is allowed to overwrite. But it leaves no way at
all to fix text that shipped wrong, and four cards in the 2026-08-15 audit are
wrong in ways that matter -- a strength parity that does not exist, a claim about
which part of the body a stretch avoids that is backwards, an implication that
every knee adapts, and a Russian title describing a different exercise.

So this is the other half, and it is deliberately not a flag on that tool.
Overwriting needs a different safety property than filling, and mixing the two
would mean one `--force` away from the data loss the other tool's docstring is
about.

## The guard

Every correction states the text it expects to find. If the catalogue does not
hold that text byte for byte, the correction is refused and nothing is written.

That makes the tool safe in the case that actually happens: someone re-runs a
catalogue build, the vendor text changes underneath, and a correction written
against the old wording would otherwise overwrite the new one with a fix for a
problem that no longer exists. Here it fails loudly instead, and a human decides
whether the correction still applies.

It also makes the tool idempotent in a useful way -- a second run reports every
correction as already applied, because `before` no longer matches, and that is a
success rather than an error. `--check` distinguishes the two.

## The source batches are corrected too

`tools/catalog/batches/*.json` are the authored source for this text. A
correction applied only to the shipped catalogue would be undone by anyone who
re-ran `merge_exercise_text.py` against an emptied row. So this also rewrites the
matching batch entry.

The two are NOT assumed to agree. The first run of this tool found they already
do not: the batches still hold the superlative first drafts ("the side almost
nothing else works", "The best shape for..."), which were softened in the shipped
catalogue and never written back. A correction may therefore carry a
`batch_before` alongside `before`, and where the batch has drifted the tool
refuses until one is supplied rather than guessing which of the two texts it is
looking at.

Usage:
    python tools/catalog/correct_exercise_text.py --check corrections/c1.json
    python tools/catalog/correct_exercise_text.py corrections/c1.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EN_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
RU_PATH = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.ru.json"
BATCH_DIR = Path(__file__).resolve().parent / "batches"


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _dump_json(path: Path, data) -> None:
    """Rewrite [path], preserving its indent and line endings.

    Not cosmetic. The first version wrote `indent=2` with the platform's default
    newline translation, against a catalogue file indented by one space and
    stored with LF. Three corrected strings produced a 54,000-line diff -- the
    real change was still in there, and nobody would ever have found it.

    A formatting-only diff over a data file is worse than no diff: it defeats
    review, it defeats `git blame`, and it makes the next person's genuine
    change look identical to this one.
    """
    raw = path.read_bytes()
    newline = "\r\n" if b"\r\n" in raw.split(b"\n", 2)[0] + b"\n" else "\n"
    # Indent is read from the first nested line rather than assumed. The two
    # catalogue files do not agree with each other, which is exactly why this
    # cannot be a constant.
    indent = 2
    for line in raw.decode("utf-8").splitlines()[1:]:
        stripped = line.lstrip(" ")
        if stripped and stripped != line:
            indent = len(line) - len(stripped)
            break
    with open(path, "w", encoding="utf-8", newline=newline) as fh:
        fh.write(json.dumps(data, ensure_ascii=False, indent=indent) + "\n")


class Refusal(Exception):
    """A correction that cannot be applied safely. Never downgraded to a warning."""


def _apply_field(holder: dict, field: str, spec: dict, where: str, key: str = "before") -> bool:
    """Return True if written, False if already correct. Raise on a mismatch."""
    current = holder.get(field)
    if current == spec["after"]:
        return False
    expected = spec.get(key)
    if expected is None:
        raise Refusal(
            f"{where}.{field}: this correction records no '{key}'. The authored "
            f"batch has drifted from the shipped catalogue, so the tool cannot "
            f"tell which text it is looking at.\n"
            f"  found: {current!r}"
        )
    if current != expected:
        raise Refusal(
            f"{where}.{field}: does not hold the text this correction was "
            f"written against.\n"
            f"  expected: {expected!r}\n"
            f"  found:    {current!r}"
        )
    holder[field] = spec["after"]
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corrections", nargs="+", type=Path)
    parser.add_argument(
        "--check", action="store_true", help="report only; write nothing"
    )
    args = parser.parse_args()

    en = _load_json(EN_PATH)
    ru = _load_json(RU_PATH)
    en_by_id = {row["id"]: row for row in en}

    batches: dict[Path, dict] = {}
    # Only the batches this run actually changed are written back. Dumping every
    # batch that was merely READ would reformat files this correction has nothing
    # to do with, and a reformatting diff is the kind nobody reads carefully.
    touched: set[Path] = set()
    written = 0
    already = 0
    refusals: list[str] = []

    for path in args.corrections:
        doc = _load_json(path)
        for ex_id, spec in doc.items():
            if ex_id not in en_by_id:
                refusals.append(f"{ex_id}: not in the catalogue")
                continue
            if ex_id not in ru:
                refusals.append(f"{ex_id}: not in the Russian overlay")
                continue
            if not spec.get("reason", "").strip():
                refusals.append(f"{ex_id}: no reason recorded")
                continue

            for lang, holder in (("en", en_by_id[ex_id]), ("ru", ru[ex_id])):
                for field, fspec in (spec.get(lang) or {}).items():
                    try:
                        if _apply_field(holder, field, fspec, f"{ex_id}/{lang}"):
                            written += 1
                            print(f"  fix   {ex_id}/{lang}.{field}")
                        else:
                            already += 1
                            print(f"  ok    {ex_id}/{lang}.{field} already correct")
                    except Refusal as exc:
                        refusals.append(str(exc))

            # The authored source, so a rebuild does not undo the fix.
            for batch_path in sorted(BATCH_DIR.glob("*.json")):
                batch = batches.setdefault(batch_path, _load_json(batch_path))
                if ex_id not in batch:
                    continue
                for lang in ("en", "ru"):
                    block = batch[ex_id].get(lang) or {}
                    for field, fspec in (spec.get(lang) or {}).items():
                        if field not in block:
                            continue
                        key = "batch_before" if "batch_before" in fspec else "before"
                        try:
                            if _apply_field(
                                block,
                                field,
                                fspec,
                                f"{batch_path.name}:{ex_id}/{lang}",
                                key,
                            ):
                                written += 1
                                touched.add(batch_path)
                                print(
                                    f"  fix   {batch_path.name}:{ex_id}/{lang}.{field}"
                                )
                        except Refusal as exc:
                            refusals.append(str(exc))

    if refusals:
        print()
        for r in refusals:
            print(f"REFUSED  {r}")
        print(f"\n{len(refusals)} refusal(s); nothing written")
        return 1

    print(f"\n{written} correction(s) to write, {already} already correct")
    if args.check:
        print("--check: nothing written")
        return 0
    if written:
        _dump_json(EN_PATH, en)
        _dump_json(RU_PATH, ru)
        for path in sorted(touched):
            _dump_json(path, batches[path])
        print(f"wrote {EN_PATH.name}, {RU_PATH.name} and {len(touched)} batch file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
