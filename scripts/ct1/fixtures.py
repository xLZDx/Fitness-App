# -*- coding: utf-8 -*-
"""Synthetic material for exercising the post-label pipeline. Never real data.

    python scripts/ct1/fixtures.py          # describe what it generates
    python scripts/ct1/pipeline.py --fixtures

Every batch this produces carries a ``TEST_`` batch id, and `pipeline.run`
refuses to mix the two directions: fixture mode will not touch a real batch,
production mode will not accept a fixture one, and fixture output may not be
written anywhere inside ``core/ml/``.

## Why this is in the production tree and not in a test file

`scripts/ct1/pipeline.py --fixtures` is the only way anybody can see the seven
stages run today, and it will stay that way until human labels come back. A
runnable demonstration that lives only inside a test module is one that nobody
outside a pytest session can execute — and the person who most needs to run it
is the operator deciding whether the chain is ready, not a CI job.

## The one thing these fixtures must not be mistaken for

**Generated answers are not labels.** `_answer` below decides what a synthetic
reviewer says using a rule over the row's own content. That is a machine
labelling its own data — precisely the feedback loop `label_contract` refuses —
and it is acceptable here only because the output can never leave a fixture
run. Every submission is stamped ``reviewer_kind: "SYNTHETIC"`` and every
reviewer name starts with ``synthetic.``, so a file that escaped into a real
directory would still say what it is on every row.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from review_batch import (  # noqa: E402
    REVIEW_QUESTIONS,
    REVIEW_SCHEMA_VERSION,
    assign,
    select,
)

FIXTURE_BATCH_ID = "TEST_CT1_REVIEW_FIXTURE"
NOW = "2026-01-01T00:00:00+00:00"

#: How the two synthetic reviewers differ.
#:
#: Not a cosmetic difference. If both answered identically the pipeline's
#: agreement statistic would be 1.0 on every run, the adjudication branch would
#: never execute, and a test asserting "disagreements are surfaced" would pass
#: against an implementation that cannot surface them. R2 disagrees on a fixed
#: share of the rows it shares with R1.
DISAGREE_EVERY = 4


def _corpus(n: int = 400, dup_every: int = 5) -> tuple[list, dict, list]:
    """A synthetic catalogue with both strata populated.

    ``dup_every=5`` rather than 2 on purpose: at 2 the flagged and unflagged
    strata come out the same size, which makes a population-weighted estimate
    numerically identical to an unweighted mean and a test of the weighting
    unable to fail. That was a real survived mutation in this programme.
    """
    en, ru = [], {}
    for i in range(n):
        rid = f"fixture{i:04d}"
        dup = i % dup_every == 1
        en.append({
            "id": rid,
            "title": f"Fixture exercise {i}",
            "summary": "Shared summary." if dup else f"Summary {i}.",
            # Unique per row: identical steps everywhere would fire
            # duplicate_steps_block on the whole corpus and leave the unflagged
            # stratum empty -- the fixture guaranteeing its own outcome again.
            "steps": [f"Set up {i}", f"Move {i}"],
            "equipmentId": "bench",
            "contraindications": ["shoulder"],
            "tips": ["Brace"],
            "muscles": ["chest"],
            "primaryMuscles": ["chest"],
            "difficulty": "beginner",
            "vendorGroup": "Chest",
            "isStretch": False,
        })
        ru[rid] = {
            "title": f"Фикстура {i}", "summary": "Описание.",
            "steps": ["Готовься", "Двигайся"], "tips": ["Напрягись"],
        }
    return en, ru, [{"id": "bench"}]


def batch(size: int = 60) -> dict[str, Any]:
    """A review batch that is visibly not a real one."""
    material = select(*_corpus(), size=size)
    material["manifest"] = {
        **material["manifest"],
        "batch_id": FIXTURE_BATCH_ID,
        "synthetic": True,
        "note": (
            "GENERATED. Every row is invented and every answer against it is "
            "produced by a rule, not a person. Not a review, not evidence, and "
            "not admissible as a label anywhere."
        ),
    }
    material["assignments"] = assign(material["items"])
    return material


def _answer(item: dict[str, Any], question: str, *, flip: bool) -> str:
    """What a synthetic reviewer says. A rule over content, and nothing more.

    Deterministic on purpose — a fixture that varies between runs makes a
    pipeline failure unreproducible, which defeats the point of running it.
    """
    seed = sum(ord(c) for c in item["item_id"] + question)
    verdict = "problem" if seed % 7 == 0 else "ok"
    if flip and seed % DISAGREE_EVERY == 0:
        verdict = "ok" if verdict == "problem" else "problem"
    return verdict


def submission(
    material: dict[str, Any], slot: str, *, flip: bool = False
) -> dict[str, Any]:
    """One synthetic reviewer's package, answered in full."""
    assignments = material["assignments"]
    items = {i["item_id"]: i for i in material["items"]}
    mine = sorted(assignments["packages"][slot])
    reviews = []
    for item_id in mine:
        item = items[item_id]
        answers = {q: _answer(item, q, flip=flip) for q in REVIEW_QUESTIONS}
        reviews.append({
            "item_id": item_id,
            "source_content_version": item["source_content_version"],
            "review_timestamp": NOW,
            "review_status": "COMPLETE",
            "answers": answers,
            # `other` requires a note, and the importer refuses one without it
            # — so the fixture has to supply one, which is the guard working.
            "reason_codes": (
                ["other"] if any(v == "problem" for v in answers.values()) else []
            ),
            "note": (
                "Generated by scripts/ct1/fixtures.py. Not a reviewer's note."
                if any(v == "problem" for v in answers.values()) else ""
            ),
            "needs_domain_review": False,
        })
    return {
        "batch_id": material["manifest"]["batch_id"],
        "review_schema_version": REVIEW_SCHEMA_VERSION,
        "reviewer": f"synthetic.{slot.lower()}",
        "reviewer_slot": slot,
        # Not "HUMAN". A generated answer that claimed to be human would be the
        # exact artefact this programme refuses to produce.
        "reviewer_kind": "SYNTHETIC",
        "submitted_at": NOW,
        "reviews": reviews,
    }


def synthetic_run(size: int = 60) -> dict[str, Any]:
    """Everything the pipeline needs for one end-to-end fixture run."""
    material = batch(size=size)
    slots = sorted(material["assignments"]["packages"])
    return {
        "batch": {"manifest": material["manifest"], "items": material["items"]},
        "assignments": material["assignments"],
        "sealed": material["sealed"],
        "submissions": [
            # Only the second reviewer flips, so the double-reviewed rows carry
            # real disagreements and the adjudication branch actually runs.
            submission(material, slot, flip=(index == 1))
            for index, slot in enumerate(slots)
        ],
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--size", type=int, default=60)
    args = ap.parse_args(argv)
    material = synthetic_run(size=args.size)
    print(f"  batch      {material['batch']['manifest']['batch_id']}")
    print(f"  items      {len(material['batch']['items'])}")
    print(f"  reviewers  "
          f"{[s['reviewer'] for s in material['submissions']]}")
    print(f"  answers    "
          f"{sum(len(s['reviews']) for s in material['submissions'])}")
    print("\n  GENERATED. Not a review, not evidence, and not a label.")
    print("  Run the chain with: python scripts/ct1/pipeline.py --fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
