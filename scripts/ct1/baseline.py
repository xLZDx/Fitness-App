# -*- coding: utf-8 -*-
"""CT-1 deterministic content-QA baseline.

    python scripts/ct1/baseline.py            # report against the shipped catalogue
    python -m pytest scripts/ct1/test_ct1.py -q

This is the CHAMPION. Not a placeholder for one — the champion, until something
beats it on the metrics in ``core/ml/CT1_CONTENT_QA.md``.

Every check here is exact. It fires when a stated condition holds and never
otherwise, so its precision against its own definition is 1.0 by construction
and reporting that number would be meaningless. What is worth measuring is
whether a human agrees the flagged row is actually a defect worth fixing, and
that requires reviewed labels this repository does not yet have —
``EVALUATION_LABEL_GAP``, reported rather than papered over.

## Why rules and not a model, stated once

A model is worth its cost when the rule cannot be written down. "This row has
no contraindications tag" is a rule. So is "these two rows share a steps
block". Training a classifier to detect a missing key would be a slower, less
precise, unexplainable reimplementation of ``'contraindications' not in row``,
and the honest reading of the CT-1 scorecard is that most of the value in this
catalogue is in that category.

The place a model earns its keep is where the judgement is genuinely fuzzy:
does the description match the title, do the steps contradict the equipment,
is this translation a translation. Those are the checks that are ABSENT below,
deliberately — they are what a challenger has to bring.
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from label_contract import Label, LabelSource  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "mobile" / "assets" / "data"

#: The nine-value region vocabulary the catalogue actually uses. Measured, not
#: chosen: this is the closed set the eligibility layer maps restrictions onto,
#: and a tag outside it is invisible to every safety filter in the app.
REGION_TAGS = frozenset({
    "shoulder", "hip", "elbow", "knee",
    "lower_back", "upper_back", "ankle", "wrist", "neck",
})

#: Fields every row must carry a non-empty value for. Derived from measurement
#: rather than aspiration: all four are populated on all 1,887 rows today, so a
#: violation is a regression and not a backlog.
REQUIRED_NON_EMPTY = ("id", "title", "summary", "steps")

#: Fields whose absence is a real content gap but not a regression, because
#: many rows already lack them. Counted, never asserted on.
OPTIONAL_TRACKED = ("contraindications", "tips", "muscles", "primaryMuscles")


def load(en_path: Path, ru_path: Path, eq_path: Path) -> tuple[list, dict, list]:
    en = json.loads(en_path.read_text(encoding="utf-8"))
    ru = json.loads(ru_path.read_text(encoding="utf-8"))
    eq = json.loads(eq_path.read_text(encoding="utf-8"))
    return en, ru, eq


def run_checks(en: list, ru: dict, eq: list) -> list[Label]:
    """Every deterministic finding, as contract-checked labels."""
    out: list[Label] = []
    equipment_ids = {e["id"] for e in eq}

    def obs(item_id: str, check: str, **evidence: Any) -> None:
        out.append(Label(item_id, check, LabelSource.OBSERVATION,
                         evidence=evidence))

    def flag(item_id: str, check: str, **evidence: Any) -> None:
        out.append(Label(item_id, check, LabelSource.AUTO_HEURISTIC_FLAG,
                         evidence=evidence))

    # --- structural completeness -------------------------------------------
    for row in en:
        rid = row.get("id") or "<missing-id>"
        for f in REQUIRED_NON_EMPTY:
            if not row.get(f):
                obs(rid, f"required_field_empty:{f}")
        for f in OPTIONAL_TRACKED:
            if f not in row:
                obs(rid, f"field_absent:{f}")
            elif not row[f]:
                # The third state, and the reason it is separate: an absent key
                # means nobody has tagged this row, an empty list means someone
                # tagged it as having none. Collapsing them loses the only
                # record of a decision having been made.
                obs(rid, f"field_present_but_empty:{f}")

    # --- taxonomy ----------------------------------------------------------
    for row in en:
        rid = row.get("id", "")
        equip = row.get("equipmentId")
        if equip is not None and equip not in equipment_ids:
            flag(rid, "dangling_equipment_ref", equipmentId=equip)
        for tag in row.get("contraindications") or []:
            if tag not in REGION_TAGS:
                # Invisible to every safety filter, because the eligibility
                # layer only maps restrictions onto the nine.
                flag(rid, "unknown_contraindication_tag", tag=tag)

    # --- identity ----------------------------------------------------------
    by_id = collections.Counter(r.get("id") for r in en)
    for rid, n in by_id.items():
        if n > 1:
            flag(rid or "<missing-id>", "duplicate_id", occurrences=n)

    # --- duplication -------------------------------------------------------
    # Reported on the SECOND and later occurrence only. Flagging all members of
    # a duplicate group doubles the review queue and states the same fact twice.
    for field_name in ("title", "summary"):
        seen: dict[str, str] = {}
        for row in en:
            key = (row.get(field_name) or "").strip().lower()
            if not key:
                continue
            if key in seen:
                flag(row.get("id", ""), f"duplicate_{field_name}",
                     first_seen=seen[key])
            else:
                seen[key] = row.get("id", "")

    seen_steps: dict[str, str] = {}
    for row in en:
        key = json.dumps(row.get("steps") or [], ensure_ascii=False, sort_keys=True)
        if key == "[]":
            continue
        if key in seen_steps:
            flag(row.get("id", ""), "duplicate_steps_block",
                 first_seen=seen_steps[key])
        else:
            seen_steps[key] = row.get("id", "")

    # --- localisation ------------------------------------------------------
    en_ids = {r.get("id") for r in en}
    for rid in sorted(en_ids - set(ru)):
        flag(rid or "", "locale_row_missing", locale="ru")
    for rid in sorted(set(ru) - en_ids):
        flag(rid, "locale_row_orphan", locale="ru")

    for row in en:
        rid = row.get("id", "")
        tr = ru.get(rid)
        if not tr:
            continue
        for f in ("title", "summary", "steps", "tips", "purpose"):
            has_en = bool(row.get(f))
            has_ru = bool(tr.get(f))
            if has_en and not has_ru:
                flag(rid, "locale_field_missing", field=f, locale="ru")
            elif has_ru and not has_en:
                # The direction that surprises people: the translation carries
                # content the source does not.
                flag(rid, "locale_field_orphan", field=f, locale="ru")
        for f in ("title", "summary"):
            a, b = row.get(f), tr.get(f)
            if a and b and a.strip() == b.strip():
                flag(rid, "locale_value_identical", field=f)

    return out


def corpus_observations(en: list) -> list[dict[str, Any]]:
    """Facts about the corpus rather than about any row.

    Kept separate from labels on purpose. "99.5% of rows say beginner" is not a
    defect in any one row, and filing it as 1,877 labels would bury every real
    per-row finding underneath it. It is one fact and belongs in a report.
    """
    out = []
    for field_name in ("difficulty", "vendorGroup", "isStretch"):
        counts = collections.Counter(
            json.dumps(r.get(field_name), ensure_ascii=False) for r in en
        )
        top_value, top_n = counts.most_common(1)[0]
        share = top_n / len(en) if en else 0.0
        out.append({
            "field": field_name,
            "distinct_values": len(counts),
            "dominant_value": json.loads(top_value),
            "dominant_share": round(share, 4),
            # A field where one value covers almost everything is carrying no
            # information, whatever it was meant to carry. Flagged as a
            # corpus-level observation so somebody decides whether it is a
            # vendor default that was never reviewed.
            #
            # No `and len(counts) > 1` guard: the first version had one, which
            # exempted a field holding a SINGLE value everywhere -- the most
            # degenerate case there is, and the one it would most matter to
            # catch.
            "degenerate": share >= 0.95,
        })
    return out


def summarise(labels: Iterable[Label]) -> dict[str, Any]:
    labels = list(labels)
    by_check = collections.Counter(l.check for l in labels)
    by_source = collections.Counter(l.source.value for l in labels)
    return {
        "total": len(labels),
        "distinct_items": len({l.item_id for l in labels}),
        "by_source": dict(sorted(by_source.items())),
        "by_check": dict(sorted(by_check.items(), key=lambda kv: (-kv[1], kv[0]))),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--en", type=Path, default=DATA / "exercises_vendor.json")
    ap.add_argument("--ru", type=Path, default=DATA / "exercises_vendor.ru.json")
    ap.add_argument("--equipment", type=Path, default=DATA / "equipment.json")
    ap.add_argument("--out", type=Path, default=None,
                    help="write the full label set as JSON")
    args = ap.parse_args(argv)

    en, ru, eq = load(args.en, args.ru, args.equipment)
    labels = run_checks(en, ru, eq)
    report = {
        "rows": len(en),
        "summary": summarise(labels),
        "corpus": corpus_observations(en),
    }
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(
            json.dumps({**report, "labels": [l.to_json() for l in labels]},
                       ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
