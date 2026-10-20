# -*- coding: utf-8 -*-
"""Checked-in corrections layer for the vendor exercise catalogue.

WHY THIS EXISTS

`build_vendor_catalog.py --write` regenerates `title`, `muscles`, `steps`,
`summary`, `isStretch` from the vendor sheet on every run (only `equipmentId`,
`contraindications`, `poseTargetId` and keys it never emits survive a merge).
A hand edit to `exercises_vendor.json` therefore dies on the next rebuild.

Corrections live in `scripts/catalog/catalog_corrections.json` instead and are
re-applied after every build (`build_vendor_catalog.py` calls `apply()`), and
can also be applied on their own with no vendor zip:

    python scripts/catalog/catalog_corrections.py            # report only
    python scripts/catalog/catalog_corrections.py --write    # apply to assets

File shape (values are ABSOLUTE, so applying twice changes nothing):

    {"version": 1, "rows": {"<id>": {"en": {<row fields>}, "ru": {<overlay fields>}}}}

`en` may set: title, difficulty, muscles, primaryMuscles, equipmentId, equipmentLabel,
isStretch, steps, purpose. Setting `steps` also sets `summary = steps[0]`
(the catalogue invariant). `ru` may set: title, steps, purpose (summary follows
steps[0]). Anything else is rejected rather than silently written.

`authored_by` generator: `author_catalog_corrections.py` (kept for provenance).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "catalog"))
from json_io import dump_json, load_json  # noqa: E402

DATA = ROOT / "mobile" / "assets" / "data"
EN_PATH = DATA / "exercises_vendor.json"
RU_PATH = DATA / "exercises_vendor.ru.json"
CORRECTIONS = Path(__file__).with_name("catalog_corrections.json")

EN_FIELDS = {
    "title", "muscles", "primaryMuscles", "equipmentId", "equipmentLabel",
    "isStretch", "steps", "purpose", "difficulty",
}
RU_FIELDS = {"title", "steps", "purpose"}


def load_corrections(path: Path = CORRECTIONS) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = data["rows"]
    for rid, c in rows.items():
        bad = set(c.get("en", {})) - EN_FIELDS
        bad_ru = set(c.get("ru", {})) - RU_FIELDS
        if bad or bad_ru:
            raise ValueError(f"{rid}: unsupported correction fields {sorted(bad | bad_ru)}")
    return rows


def apply(rows: list[dict], ru: dict, corrections: dict, strict: bool = True) -> dict[str, int]:
    """Apply [corrections] in place; returns how many rows/fields changed.

    `strict=False` skips ids absent from [rows] (a partial bundle or a test
    fixture); the default raises so a typo in the corrections file is loud."""
    by_id = {r["id"]: r for r in rows}
    changed = {"en_rows": 0, "en_fields": 0, "ru_rows": 0, "ru_fields": 0}
    for rid, c in corrections.items():
        row = by_id.get(rid)
        if row is None:
            if not strict:
                continue
            raise KeyError(f"correction for unknown id {rid}")
        touched = 0
        for key, val in c.get("en", {}).items():
            if row.get(key) != val:
                row[key] = val
                touched += 1
            if key == "steps" and val and row.get("summary") != val[0]:
                row["summary"] = val[0]
                touched += 1
        changed["en_fields"] += touched
        changed["en_rows"] += bool(touched)

        rc = c.get("ru", {})
        if rc:
            entry = ru.setdefault(rid, {})
            touched = 0
            for key, val in rc.items():
                if entry.get(key) != val:
                    entry[key] = val
                    touched += 1
                if key == "steps" and val and entry.get("summary") != val[0]:
                    entry["summary"] = val[0]
                    touched += 1
            if touched:  # keep the overlay's sorted-key layout
                ru[rid] = {k: entry[k] for k in sorted(entry)}
            changed["ru_fields"] += touched
            changed["ru_rows"] += bool(touched)
    return changed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    rows = load_json(EN_PATH)
    ru = load_json(RU_PATH)
    changed = apply(rows, ru, load_corrections())
    print(changed)
    if args.write:
        dump_json(EN_PATH, rows)
        dump_json(RU_PATH, ru)
        print("written")
    elif any(changed.values()):
        print("pending corrections -- pass --write")


if __name__ == "__main__":
    main()
