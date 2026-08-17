# -*- coding: utf-8 -*-
"""CT-1 evaluation — including the part where it says it cannot evaluate.

    python scripts/ct1/evaluate.py
    python -m pytest scripts/ct1/test_ct1.py -q

Precision and recall are not reported here, and their absence is the finding
rather than an omission. Both require knowing which flagged rows a competent
reviewer would call real defects, and this repository has **zero** reviewed
labels. A number computed against the baseline's own output would measure the
baseline's agreement with itself, which is exactly the self-referential loop
``label_contract.py`` exists to prevent — computing it here while forbidding it
there would be an odd sort of principle.

So the report states ``EVALUATION_LABEL_GAP`` and quantifies what is genuinely
measurable without a ground truth:

* **coverage** — the share of the catalogue the baseline has any opinion about.
* **queue shape** — how much review the flags actually ask for, per check.
* **precision-by-construction** — the checks whose definition makes them exact,
  named explicitly so that "exact" is never mistaken for "important". A rule
  that fires exactly when a key is missing is perfectly precise about the key
  and says nothing about whether the missing key matters.
* **slices** — where the flags concentrate, which is what tells a reviewer
  where to start and a challenger where the baseline is weakest.

For content QA a false positive is the expensive error: a pipeline that flags
everything is a pipeline nobody reads. That is why queue shape is reported per
check and why the largest checks are named — 451 rows for one missing field is
not a review queue, it is a migration.
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baseline import DATA, REPO, corpus_observations, load, run_checks  # noqa: E402
from label_contract import LabelSource, may_train_on  # noqa: E402

#: Checks whose precision is 1.0 against their own definition, because the
#: definition is a property of the data rather than a judgement about it.
#: Listed so the claim stays narrow: exact is not the same as actionable.
EXACT_BY_CONSTRUCTION = frozenset({
    "field_absent", "field_present_but_empty", "required_field_empty",
    "duplicate_id", "duplicate_title", "duplicate_summary",
    "duplicate_steps_block", "dangling_equipment_ref",
    "unknown_contraindication_tag", "locale_row_missing",
    "locale_row_orphan", "locale_field_missing", "locale_field_orphan",
    "locale_value_identical",
})

#: What a challenger has to bring, because no rule can express it. Recorded in
#: the report so the gap is visible next to the metrics rather than only in
#: prose somewhere.
REQUIRES_JUDGEMENT = (
    "steps contradict the title",
    "description promises equipment the row does not use",
    "cues are unsafe in wording without naming a clinical claim",
    "a translation that is fluent but not a translation of this row",
    "instructions that are correct but for a different movement",
)


def check_family(check: str) -> str:
    return check.split(":", 1)[0]


def evaluate(en, ru, eq) -> dict[str, Any]:
    labels = run_checks(en, ru, eq)
    total_rows = len(en)
    flagged_items = {l.item_id for l in labels}
    heuristics = [l for l in labels if l.source is LabelSource.AUTO_HEURISTIC_FLAG]
    observations = [l for l in labels if l.source is LabelSource.OBSERVATION]

    per_check = collections.Counter(l.check for l in labels)
    families = {check_family(c) for c in per_check}
    unclassified = sorted(families - EXACT_BY_CONSTRUCTION)

    reviewed = [l for l in labels if may_train_on(l.source)]

    # Where the queue actually is. Sorted descending, because the top three
    # checks are the whole cost of the queue and averaging hides that.
    queue = sorted(per_check.items(), key=lambda kv: (-kv[1], kv[0]))

    slices = {}
    for name, key in (
        ("has_equipment", lambda r: r.get("equipmentId") is not None),
        ("is_stretch", lambda r: bool(r.get("isStretch"))),
        ("has_ru", lambda r: r.get("id") in ru),
    ):
        buckets: dict[str, dict[str, int]] = collections.defaultdict(
            lambda: {"rows": 0, "flagged": 0})
        for row in en:
            b = buckets[str(key(row))]
            b["rows"] += 1
            if row.get("id") in flagged_items:
                b["flagged"] += 1
        slices[name] = {
            k: {**v, "flagged_share": round(v["flagged"] / v["rows"], 4)}
            for k, v in sorted(buckets.items())
        }

    return {
        "evaluation_label_gap": {
            "state": "EVALUATION_LABEL_GAP",
            "reviewed_labels": len(reviewed),
            "reason": "no human-reviewed QA labels exist in this repository, "
                      "so precision, recall and false-positive rate cannot be "
                      "computed against a ground truth. Numbers derived from "
                      "the baseline's own output would measure it against "
                      "itself.",
            "what_would_close_it": "a reviewed sample drawn from the holdout "
                                   "split; see core/ml/CT1_CONTENT_QA.md for "
                                   "the size that would make a challenger "
                                   "comparison meaningful",
            "blocks": ["precision", "recall", "false_positive_rate",
                       "calibration", "novel_defect_yield"],
        },
        "coverage": {
            "rows": total_rows,
            "rows_with_any_finding": len(flagged_items),
            "share": round(len(flagged_items) / total_rows, 4) if total_rows else 0.0,
            "observations": len(observations),
            "heuristic_flags": len(heuristics),
        },
        "queue_shape": [
            {"check": c, "items": n,
             "share_of_queue": round(n / len(labels), 4) if labels else 0.0,
             "exact_by_construction": check_family(c) in EXACT_BY_CONSTRUCTION}
            for c, n in queue
        ],
        "unclassified_check_families": unclassified,
        "requires_judgement_not_covered": list(REQUIRES_JUDGEMENT),
        "slices": slices,
        "corpus": corpus_observations(en),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--en", type=Path, default=DATA / "exercises_vendor.json")
    ap.add_argument("--ru", type=Path, default=DATA / "exercises_vendor.ru.json")
    ap.add_argument("--equipment", type=Path, default=DATA / "equipment.json")
    ap.add_argument("--out", type=Path,
                    default=REPO / "core" / "ml" / "datasets" /
                            "content_qa_catalogue_v1" / "evaluation.json")
    args = ap.parse_args(argv)

    en, ru, eq = load(args.en, args.ru, args.equipment)
    report = evaluate(en, ru, eq)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8")

    gap = report["evaluation_label_gap"]
    cov = report["coverage"]
    print(f"state      {gap['state']} ({gap['reviewed_labels']} reviewed labels)")
    print(f"coverage   {cov['rows_with_any_finding']}/{cov['rows']} rows "
          f"({cov['share']:.1%})")
    print("top checks:")
    for row in report["queue_shape"][:5]:
        print(f"  {row['items']:5d}  {row['check']}")
    print(f"-> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
