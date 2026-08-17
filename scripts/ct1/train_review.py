# -*- coding: utf-8 -*-
"""CT-1 — human labels from the TRAIN split, which is a different job.

    python scripts/ct1/train_review.py --plan          # what it would draw
    python scripts/ct1/train_review.py --out core/ml/review --issue
    python -m pytest scripts/ct1/test_train_review.py -q

``review_batch`` draws from the holdout, because CT-1's first problem is that no
metric can be checked. This draws from TRAIN, because the second problem is that
a challenger has nothing to learn from — and the two must never be the same rows.

## Why this is a separate module rather than a flag

A boolean that switches which split a batch is drawn from is one edit away from
drawing the wrong one, and the edit would look correct. The invariant that
matters here — ``TRAIN REVIEW ROWS ∩ HOLDOUT ROWS = ∅`` — is worth a module
boundary: this file cannot produce a holdout row because it never asks for one,
and ``leakage_guard`` refuses the result if it somehow did.

## Why the batch is NOT issued yet

Deliberate, and the reason is not caution for its own sake. What a training set
should over-sample depends on where the baseline is WRONG, and nobody knows that
until the holdout review comes back — the whole point of
``CT1_REVIEW_BATCH_003``. Sampling a training batch now would either mirror the
holdout's stratification (which encodes the rules' current opinion, the feedback
loop this project keeps refusing) or be uniform (which spends most of a
reviewer's day on rows nothing is wrong with).

So the tooling is complete and the targeting is a parameter. ``--plan`` prints
what a draw would look like under a stated strategy and writes nothing.
``--issue`` is required to produce a batch, and it records which strategy was
chosen and on what evidence.

## What this can never be used for

The rows it draws are trainable. The rows ``review_batch`` draws are not, ever:
``CT1_REVIEW_BATCH_003`` and ``CT1_HUMAN_EVAL_V1`` are evaluation, and training
on them destroys the only measurement CT-1 has. That is enforced in
``leakage_guard``, asserted here, and mutation-tested in both places.
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baseline import DATA, REPO, load, run_checks  # noqa: E402
from build_dataset import file_digest, git_commit, source_ref, split_for  # noqa: E402
from label_contract import LabelSource  # noqa: E402
from review_batch import (  # noqa: E402
    DOUBLE_REVIEW_SHARE,
    REASON_CODES,
    REVIEW_QUESTIONS,
    REVIEW_SCHEMA_VERSION,
    REVIEW_STATUSES,
    SCHEMA_VERSION,
    VERDICTS,
    _bucket,
    _families,
    _rank,
    assign,
    content_version,
    is_double,
)

BATCH_ID = "CT1_TRAIN_REVIEW_BATCH_001"

#: How rows are chosen, and what each choice assumes.
#:
#: Named rather than parameterised as a ratio, because the choice is an
#: argument about what the challenger needs to learn and should be quotable in
#: a model card as one word plus a reason.
STRATEGIES = {
    # Every row equally likely. Assumes nothing, learns slowly: on a corpus
    # where most rows are fine, most of a reviewer's day produces `ok`.
    "uniform": (
        "Every train row equally likely. Assumes nothing about where defects "
        "are, and spends most of the reviewer's effort confirming clean rows. "
        "The honest default when nothing is known about baseline error."
    ),
    # Mirrors the holdout batch's flagged/unflagged ratio.
    "mirror_baseline": (
        "Draws flagged and unflagged rows in the holdout batch's ratio. "
        "ENCODES THE RULES' CURRENT OPINION: a challenger trained on it learns "
        "where the rules already look, which is the feedback loop this project "
        "refuses elsewhere. Defensible only as a deliberate, stated choice."
    ),
    # Targets the baseline's measured errors.
    "error_targeted": (
        "Over-samples the regions where the baseline was measured WRONG on the "
        "holdout. Requires CT1_HUMAN_EVAL_V1 to exist; unavailable until the "
        "holdout review returns. This is the strategy the design expects."
    ),
}
DEFAULT_STRATEGY = "uniform"


class TrainReviewError(RuntimeError):
    """A train-review batch that would poison the evaluation it is measured by."""


def train_rows(en: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Train-split rows, deduplicated the way the dataset builder does.

    The ONLY place this module decides which rows it may see. Everything below
    consumes this, so a holdout row cannot enter by a later edit without this
    function changing.
    """
    seen: set[str] = set()
    out = []
    for row in en:
        rid = row.get("id")
        if not rid or rid in seen or split_for(rid) != "train":
            continue
        seen.add(rid)
        out.append(row)
    return out


def select(
    en: list, ru: dict, eq: list, *, size: int = 180,
    strategy: str = DEFAULT_STRATEGY, flagged_share: float | None = None,
) -> dict[str, Any]:
    """Draw a train-split review batch under a named strategy."""
    if strategy not in STRATEGIES:
        raise TrainReviewError(
            f"{strategy!r} is not a strategy. Choose from {sorted(STRATEGIES)} "
            "-- the choice is an argument about what the challenger needs to "
            "learn and must be recorded, not defaulted into"
        )
    if strategy == "error_targeted":
        raise TrainReviewError(
            "error_targeted needs CT1_HUMAN_EVAL_V1, which does not exist: the "
            "holdout review has not returned. BLOCKER = "
            "HUMAN_REVIEW_LABELS_REQUIRED. Choose uniform or mirror_baseline "
            "deliberately, or wait -- do not approximate this one"
        )

    labels = run_checks(en, ru, eq)
    checks_by_item: dict[str, set[str]] = collections.defaultdict(set)
    for l in labels:
        if l.source is LabelSource.AUTO_HEURISTIC_FLAG:
            checks_by_item[l.item_id].add(l.check)

    rows = train_rows(en)
    flagged = [r for r in rows if checks_by_item.get(r["id"])]
    unflagged = [r for r in rows if not checks_by_item.get(r["id"])]

    if strategy == "uniform":
        picked = sorted(rows, key=lambda r: _rank(r["id"], "train"))[:size]
    else:
        share = DEFAULT_FLAGGED_SHARE if flagged_share is None else flagged_share
        want_flagged = min(len(flagged), round(size * share))
        want_unflagged = min(len(unflagged), size - want_flagged)
        picked = (
            sorted(flagged, key=lambda r: _rank(r["id"], "train_flagged"))[:want_flagged]
            + sorted(unflagged, key=lambda r: _rank(r["id"], "train_unflagged"))[:want_unflagged]
        )

    picked = sorted(picked, key=lambda r: r["id"])

    items = []
    for r in picked:
        rid = r["id"]
        item = {
            "item_id": rid,
            "title": r.get("title"),
            "summary": r.get("summary"),
            "steps": list(r.get("steps") or []),
            "tips": list(r.get("tips") or []),
            "equipment_id": r.get("equipmentId"),
            "muscles": list(r.get("muscles") or []),
            "difficulty": r.get("difficulty"),
            "is_stretch": bool(r.get("isStretch")),
            "ru": ru.get(rid),
        }
        item["source_content_version"] = content_version(item)
        items.append(item)

    # The invariant, checked HERE as well as in `leakage_guard`.
    #
    # Not redundancy for its own sake: the guard runs at training time, which is
    # after a reviewer has already spent a day on the wrong rows. This one runs
    # while the mistake is still free to fix.
    holdout = {r["id"] for r in en if r.get("id") and split_for(r["id"]) == "holdout"}
    overlap = sorted({i["item_id"] for i in items} & holdout)
    if overlap:
        raise TrainReviewError(
            f"{len(overlap)} row(s) are in the holdout, e.g. {overlap[:5]}. A "
            "human label on a holdout row is a valid label that destroys the "
            "only evaluation this project has"
        )

    sealed = {r["id"]: sorted(checks_by_item.get(r["id"], set())) for r in picked}
    doubles = [i["item_id"] for i in items if is_double(i["item_id"])]

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "review_schema_version": REVIEW_SCHEMA_VERSION,
        "batch_id": BATCH_ID,
        "purpose": "TRAINING_LABEL_ACQUISITION",
        "split": "train",
        "strategy": strategy,
        "strategy_rationale": STRATEGIES[strategy],
        "source_commit": git_commit(),
        "requested_size": size,
        "size": len(items),
        "short": len(items) < size,
        "train_rows_available": len(rows),
        "flagged_available": len(flagged),
        "unflagged_available": len(unflagged),
        "flagged_selected": sum(1 for r in picked if checks_by_item.get(r["id"])),
        "double_review_items": len(doubles),
        "questions": list(REVIEW_QUESTIONS),
        "verdicts": list(VERDICTS),
        "reason_codes": list(REASON_CODES),
        "review_statuses": list(REVIEW_STATUSES),
        "blind": True,
        "holdout_intersection": 0,
        "family_counts": {
            fam: sum(
                1 for r in picked
                if fam in _families(checks_by_item.get(r["id"], set()))
            )
            for fam in sorted({
                f for r in picked
                for f in _families(checks_by_item.get(r["id"], set()))
            })
        },
        "use": (
            "TRAINING ONLY. These rows are in the train split, so a reviewed "
            "label on one is a legitimate training target. It is NOT evaluation: "
            "reporting a metric on rows a model trained on reports its memory."
        ),
        "not_for": (
            "CT1_REVIEW_BATCH_003 and CT1_HUMAN_EVAL_V1 are evaluation and must "
            "never be trained on. leakage_guard refuses any label carrying "
            "split=holdout regardless of how good the label is."
        ),
        "sampling": (
            "See `strategy`. A rate computed on this batch describes this batch "
            "and is not a corpus rate; this batch exists to teach, not to measure."
        ),
        "source": {
            "catalogue_en": source_ref(DATA / "exercises_vendor.json"),
            "sha256": {
                "catalogue_en": file_digest(DATA / "exercises_vendor.json"),
            },
        },
    }
    return {"manifest": manifest, "items": items, "sealed": sealed}


#: Used only by `mirror_baseline`, and named so the number is arguable.
DEFAULT_FLAGGED_SHARE = 2 / 3


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(REPO / "core" / "ml" / "review"))
    ap.add_argument("--size", type=int, default=180)
    ap.add_argument("--strategy", default=DEFAULT_STRATEGY, choices=sorted(STRATEGIES))
    ap.add_argument(
        "--issue", action="store_true",
        help="actually write the batch. Without it this is a dry run, because "
             "issuing a training batch before baseline error analysis is a "
             "decision and should look like one",
    )
    args = ap.parse_args(argv)

    en, ru, eq = load(
        DATA / "exercises_vendor.json",
        DATA / "exercises_vendor.ru.json",
        DATA / "equipment.json",
    )
    batch = select(en, ru, eq, size=args.size, strategy=args.strategy)
    m = batch["manifest"]
    print(f"{m['batch_id']}  strategy={m['strategy']}")
    print(f"  train rows available {m['train_rows_available']}")
    print(f"  would draw           {m['size']} ({m['flagged_selected']} flagged)")
    print(f"  double review        {m['double_review_items']}")
    print(f"  holdout intersection {m['holdout_intersection']}")

    if not args.issue:
        print("\nDRY RUN. Nothing written.")
        print(
            "  The strategy this design expects is `error_targeted`, which needs\n"
            "  CT1_HUMAN_EVAL_V1 and therefore the holdout review. Issuing a\n"
            "  training batch before knowing where the baseline is wrong either\n"
            "  mirrors the rules' own opinion or spends a reviewer's day on rows\n"
            "  nothing is wrong with. Pass --issue to override deliberately."
        )
        return 0

    batch["assignments"] = assign(batch["items"])
    target = Path(args.out) / BATCH_ID.lower()
    target.mkdir(parents=True, exist_ok=True)
    for name, payload in (
        ("manifest.json", batch["manifest"]),
        ("items.json", batch["items"]),
        ("sealed_baseline_labels.json", batch["sealed"]),
        ("assignments.json", batch["assignments"]),
    ):
        (target / name).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(f"  -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
