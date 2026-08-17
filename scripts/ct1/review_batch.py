# -*- coding: utf-8 -*-
"""CT-1 human-label acquisition — the batch, the schema, and the importer.

    python scripts/ct1/review_batch.py --out core/ml/review
    python -m pytest scripts/ct1/test_review_batch.py -q

CT-1 has a deterministic champion, a reproducible dataset and an evaluation
that reports ``EVALUATION_LABEL_GAP`` — because there are no reviewed labels at
all. Every label in the corpus is an ``OBSERVATION`` or an
``AUTO_HEURISTIC_FLAG``, and neither may be a training target. This module is
the only way that changes.

## The one rule everything here is shaped by

A reviewer who can see the machine's answer is not producing an independent
label. They are producing an agreement rate, and an agreement rate trained on
looks exactly like a human label while being a slightly noisier copy of the
rule that generated it. That is the feedback loop ``label_contract`` refuses at
the training step; refusing it there and then handing reviewers the machine's
output is refusing it in the one place it cannot happen.

So the batch is **blind**. The exported item carries the catalogue content a
person needs in order to judge it and carries no label, no score, no flag and
no hint that a rule fired on it. The baseline's own labels for the same items
are written to a separate sealed file, which exists so the batch can be
EVALUATED afterwards and is not part of what a reviewer opens.

## Why the sampling is stratified rather than random

A batch drawn at random from the holdout is roughly 86% rows on which no rule
fired. Reviewing it would measure the rules' precision on a handful of rows and
say nothing at all about what they MISS, which is the more expensive error: a
false negative is a bad catalogue row shipped, a false positive is a queue item
somebody dismisses in four seconds.

So the batch is drawn deliberately: flagged rows and unflagged rows in a stated
ratio, flagged rows spread across check families so no single rule dominates,
and both locales represented. The ratio is recorded in the manifest, because a
metric computed on a deliberately non-representative sample must never be
reported as if it came from a random one.

## What this module cannot do

It cannot establish that a reviewer is a person. Nothing in a file format can.
``reviewer_kind`` records a CLAIM, and the importer refuses the values this
project knows are machine-shaped — but a determined mislabel would pass. The
protection that actually holds is procedural and lives in
``core/ml/CT1_CONTENT_QA.md``: a label is trainable only when a named human
took responsibility for it, and no agent, model or heuristic in this repository
may enter that name. See section 29 of the programme brief and
``label_contract.CLINICALLY_VALIDATED_LABEL`` for the stronger case of the same
rule.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baseline import DATA, REPO, load, run_checks  # noqa: E402
from build_dataset import file_digest, git_commit, source_ref, split_for  # noqa: E402
from label_contract import (  # noqa: E402
    Label,
    LabelContractError,
    LabelSource,
)

SCHEMA_VERSION = 1
BATCH_ID = "CT1_REVIEW_BATCH_001"

#: How many items a reviewer is asked to look at.
#:
#: 150-200 was the brief. 180 is the middle, and it divides evenly by the
#: stratum weights below, which matters more than the exact figure: a target
#: that does not divide forces a rounding rule, and a rounding rule is a place
#: for a stratum to quietly become empty.
BATCH_SIZE = 180

#: Share of the batch drawn from rows on which at least one rule fired.
#:
#: Not 1.0, and that is the whole design. An all-flagged batch measures the
#: rules' PRECISION and cannot, even in principle, discover a row the rules
#: missed. Two thirds / one third is a judgement, stated so it can be argued
#: with: the flagged side has more to say per row, the unflagged side is the
#: only source of evidence about recall, and 60 unflagged rows is enough to
#: notice a systematic miss without being enough to waste a reviewer's day.
FLAGGED_SHARE = 2 / 3

#: Share of the batch given to a SECOND reviewer, for agreement measurement.
#:
#: Every item double-reviewed would halve the corpus for the same effort;
#: none double-reviewed leaves the label quality unmeasurable, which is the
#: state CT-1 is trying to leave. 20% is the smallest share that still gives a
#: usable agreement figure on each verdict field.
DOUBLE_REVIEW_SHARE = 0.2

#: The questions a reviewer answers, and the only ones an import will accept.
#:
#: Each is about CONTENT, which is what `HUMAN_REVIEWED_QA_LABEL` is defined to
#: cover. None of them asks whether an exercise is SAFE for anybody: that is
#: clinical authority, it is unreachable from here by construction, and a
#: question that invites the answer is how a content label gets read as one.
#: See D1 and H3.
REVIEW_QUESTIONS = (
    "steps_match_title",
    "steps_are_complete",
    "equipment_is_correct",
    "translation_is_faithful",
    "summary_is_accurate",
)

#: The answers a question may take.
#:
#: ``cannot_judge`` is not politeness. Forcing a verdict on a row the reviewer
#: cannot assess manufactures a label, and a manufactured label is
#: indistinguishable from a real one once it is in the file. It is imported as
#: an ABSTENTION and never as a target.
VERDICTS = ("ok", "problem", "cannot_judge")

#: Reviewer identities the importer refuses outright.
#:
#: A blocklist is weak and is not the protection -- see the module docstring.
#: It exists because the cheapest way for a machine label to enter this corpus
#: is somebody putting the tool's name in the field without thinking about it,
#: and that specific mistake is worth catching at the point it is made.
MACHINE_REVIEWER_MARKERS = (
    "claude", "gpt", "codex", "gemini", "llm", "model", "agent", "bot",
    "auto", "heuristic", "script", "baseline",
)


def _bucket(item_id: str, salt: str, buckets: int) -> int:
    """Deterministic bucket for `item_id` under `salt`.

    Hash-based rather than seeded RNG, for the reason the dataset builder gives
    for the same choice: a seeded shuffle is stable for a fixed corpus and
    silently is not the moment a row is added.
    """
    h = hashlib.sha256(f"{salt}:{item_id}".encode("utf-8")).hexdigest()
    return int(h[:12], 16) % buckets


def _rank(item_id: str, salt: str) -> int:
    """A stable order within a stratum, independent of catalogue order."""
    return int(hashlib.sha256(f"{salt}:{item_id}".encode("utf-8")).hexdigest()[:16], 16)


def _families(checks: set[str]) -> set[str]:
    """Check family = the part before the first colon, e.g. `field_absent`."""
    return {c.split(":", 1)[0] for c in checks}


def select(
    en: list, ru: dict, eq: list, *, size: int = BATCH_SIZE,
    flagged_share: float = FLAGGED_SHARE,
) -> dict[str, Any]:
    """The batch: which holdout rows a reviewer is asked to look at, and why.

    Holdout only. A reviewed label on a training row would be usable as a
    target and unusable as evaluation, and this batch exists to close
    ``EVALUATION_LABEL_GAP`` first -- there is no point training against a
    number nobody can check.
    """
    labels = run_checks(en, ru, eq)
    checks_by_item: dict[str, set[str]] = collections.defaultdict(set)
    for l in labels:
        if l.source is LabelSource.AUTO_HEURISTIC_FLAG:
            checks_by_item[l.item_id].add(l.check)

    holdout = [r for r in en if r.get("id") and split_for(r["id"]) == "holdout"]
    # Deduplicated the same way the dataset builder does, so the batch cannot
    # contain a row the dataset excluded.
    seen: set[str] = set()
    rows = []
    for r in holdout:
        if r["id"] in seen:
            continue
        seen.add(r["id"])
        rows.append(r)

    flagged = [r for r in rows if checks_by_item.get(r["id"])]
    unflagged = [r for r in rows if not checks_by_item.get(r["id"])]

    # Backfill in both directions, and record that it happened.
    #
    # The first version took `min(available, share)` from each stratum
    # independently and returned whatever that summed to. Found by a test
    # rather than by reading: on a corpus where every holdout row is flagged it
    # produced a 40-item batch for a requested 60, silently, while 48 unused
    # flagged rows sat there. A short batch that does not say it is short is
    # the same lie as a capped export claiming to be whole.
    #
    # The ratio is a preference, not an invariant. What is an invariant is that
    # the batch is the size it was asked for whenever the corpus can supply it.
    want_flagged = min(len(flagged), round(size * flagged_share))
    want_unflagged = min(len(unflagged), size - want_flagged)
    if want_flagged + want_unflagged < size:
        shortfall = size - want_flagged - want_unflagged
        take_more_flagged = min(shortfall, len(flagged) - want_flagged)
        want_flagged += take_more_flagged
        shortfall -= take_more_flagged
        want_unflagged += min(shortfall, len(unflagged) - want_unflagged)

    # Flagged rows spread across families: take them family by family in a
    # stable order, so one prolific rule cannot fill the batch on its own.
    by_family: dict[str, list[dict]] = collections.defaultdict(list)
    for r in flagged:
        for fam in sorted(_families(checks_by_item[r["id"]])):
            by_family[fam].append(r)
    for fam in by_family:
        by_family[fam].sort(key=lambda r: _rank(r["id"], "flagged"))

    picked_flagged: list[dict] = []
    taken: set[str] = set()
    families = sorted(by_family)
    i = 0
    while len(picked_flagged) < want_flagged and families:
        fam = families[i % len(families)]
        pool = by_family[fam]
        while pool and pool[0]["id"] in taken:
            pool.pop(0)
        if not pool:
            families.remove(fam)
            i = 0 if not families else i
            continue
        row = pool.pop(0)
        taken.add(row["id"])
        picked_flagged.append(row)
        i += 1

    picked_unflagged = sorted(
        unflagged, key=lambda r: _rank(r["id"], "unflagged")
    )[:want_unflagged]

    items = sorted(picked_flagged + picked_unflagged, key=lambda r: r["id"])

    # Blind: what a reviewer opens. The catalogue content they need to judge
    # the row, and nothing about what any rule concluded.
    blind_items = []
    for r in items:
        rid = r["id"]
        blind_items.append({
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
            "double_review": _bucket(rid, "double", 100)
            < round(DOUBLE_REVIEW_SHARE * 100),
        })

    # Sealed: the baseline's own labels for the same items. Kept so the batch
    # can be evaluated afterwards; NOT part of what a reviewer opens.
    sealed = {
        r["id"]: sorted(checks_by_item.get(r["id"], set())) for r in items
    }

    doubles = [i["item_id"] for i in blind_items if i["double_review"]]
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "batch_id": BATCH_ID,
        "source_commit": git_commit(),
        "split": "holdout",
        "requested_size": size,
        "size": len(blind_items),
        # `flagged_wanted` is what the ratio asked for; `flagged_available` is
        # how many flagged rows the holdout split HAS. Recorded separately
        # because they differ, and the difference is the most useful fact in
        # this manifest: when the whole flagged population fits in the batch,
        # the precision measurement is exhaustive for the holdout rather than
        # a sample of it, and the shortfall is a property of the corpus rather
        # than a failure of the sampler. A single "selected" figure invites the
        # opposite reading.
        "flagged_wanted": round(size * flagged_share),
        # True when one stratum could not supply its share and the other made
        # up the difference. The ratio in `sampling` below then describes the
        # intent rather than the batch, and a reader has to be told which.
        "backfilled": want_flagged != round(size * flagged_share),
        "short": len(blind_items) < size,
        "flagged_available": len(flagged),
        "flagged_selected": len(picked_flagged),
        "flagged_exhausted": len(picked_flagged) == len(flagged),
        "unflagged_available": len(unflagged),
        "unflagged_selected": len(picked_unflagged),
        "holdout_rows": len(rows),
        "family_counts": {
            fam: sum(
                1 for r in picked_flagged
                if fam in _families(checks_by_item[r["id"]])
            )
            for fam in sorted(by_family)
        },
        "double_review_items": len(doubles),
        "questions": list(REVIEW_QUESTIONS),
        "verdicts": list(VERDICTS),
        "blind": True,
        "sampling": (
            "STRATIFIED, NOT RANDOM. Flagged and unflagged rows are drawn in a "
            "stated ratio and flagged rows are spread across check families. "
            "Any rate computed on this batch describes THIS batch and must not "
            "be reported as a corpus rate."
        ),
        "source": {
            "catalogue_en": source_ref(DATA / "exercises_vendor.json"),
            "sha256": {
                "catalogue_en": file_digest(DATA / "exercises_vendor.json"),
            },
        },
    }
    return {"manifest": manifest, "items": blind_items, "sealed": sealed}


class ReviewImportError(ValueError):
    """A submitted review that would put an unusable label in the corpus."""


def import_reviews(
    submission: dict[str, Any], batch: dict[str, Any]
) -> list[Label]:
    """Validates one reviewer's returned file and turns it into labels.

    Refuses rather than repairs. Every rejection below is a case where the
    alternative is a label that looks exactly like a good one.
    """
    if submission.get("batch_id") != batch["manifest"]["batch_id"]:
        raise ReviewImportError(
            f"submission is for batch {submission.get('batch_id')!r}, this is "
            f"{batch['manifest']['batch_id']!r}"
        )
    reviewer = submission.get("reviewer")
    if not isinstance(reviewer, str) or not reviewer:
        raise ReviewImportError("reviewer identity is required")
    low = reviewer.lower()
    for marker in MACHINE_REVIEWER_MARKERS:
        if marker in low:
            raise ReviewImportError(
                f"reviewer {reviewer!r} contains {marker!r}. A machine-produced "
                "label may not enter the corpus as a reviewed one; see "
                "label_contract.TRAINABLE_SOURCES"
            )
    if submission.get("reviewer_kind") != "HUMAN":
        raise ReviewImportError(
            "reviewer_kind must be the literal 'HUMAN'. This records a CLAIM "
            "and proves nothing; it exists so that submitting a machine's "
            "output requires stating something untrue rather than omitting a "
            "field"
        )

    known = {i["item_id"] for i in batch["items"]}
    out: list[Label] = []
    for entry in submission.get("reviews") or []:
        item_id = entry.get("item_id")
        if item_id not in known:
            raise ReviewImportError(
                f"{item_id!r} is not in this batch. A review of a row nobody "
                "was asked about has no sampling provenance and cannot be "
                "used as evaluation"
            )
        answers = entry.get("answers") or {}
        unknown = sorted(set(answers) - set(REVIEW_QUESTIONS))
        if unknown:
            raise ReviewImportError(
                f"{item_id}: answers to questions that were not asked: {unknown}"
            )
        missing = sorted(set(REVIEW_QUESTIONS) - set(answers))
        if missing:
            raise ReviewImportError(
                f"{item_id}: no answer for {missing}. A partially reviewed row "
                "imported as fully reviewed would silently read as agreement"
            )
        for question, verdict in sorted(answers.items()):
            if verdict not in VERDICTS:
                raise ReviewImportError(
                    f"{item_id}.{question}: {verdict!r} is not one of {VERDICTS}"
                )
            if verdict == "cannot_judge":
                # An abstention, kept out of the label set entirely. Importing
                # it as a value would make "we do not know" a class.
                continue
            out.append(
                Label(
                    item_id=item_id,
                    check=question,
                    source=LabelSource.HUMAN_REVIEWED_QA_LABEL,
                    value=(verdict == "ok"),
                    reviewer=reviewer,
                    evidence={"batch_id": submission["batch_id"]},
                )
            )
    return out


def agreement(a: list[Label], b: list[Label]) -> dict[str, Any]:
    """Where two reviewers looked at the same item and question.

    Reports disagreement; does NOT resolve it. An automatic tie-break would be
    a machine deciding which human was right, which is the same substitution
    this whole module exists to prevent. Disagreements go back to a third
    reviewer, named in the procedure, not to a rule.
    """
    left = {(l.item_id, l.check): l.value for l in a}
    right = {(l.item_id, l.check): l.value for l in b}
    shared = sorted(set(left) & set(right))
    disagreements = [k for k in shared if left[k] != right[k]]
    return {
        "compared": len(shared),
        "agreed": len(shared) - len(disagreements),
        "disagreed": len(disagreements),
        "rate": (len(shared) - len(disagreements)) / len(shared) if shared else None,
        "items": [{"item_id": i, "check": c} for i, c in disagreements],
        "resolution": "THIRD_REVIEWER_REQUIRED",
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(REPO / "core" / "ml" / "review"))
    ap.add_argument("--size", type=int, default=BATCH_SIZE)
    args = ap.parse_args(argv)

    en, ru, eq = load(
        DATA / "exercises_vendor.json",
        DATA / "exercises_vendor.ru.json",
        DATA / "equipment.json",
    )
    batch = select(en, ru, eq, size=args.size)

    target = Path(args.out) / BATCH_ID.lower()
    target.mkdir(parents=True, exist_ok=True)
    for name, payload in (
        ("manifest.json", batch["manifest"]),
        ("items.json", batch["items"]),
        ("sealed_baseline_labels.json", batch["sealed"]),
    ):
        (target / name).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
            + "\n",
            encoding="utf-8",
        )

    m = batch["manifest"]
    print(f"{m['batch_id']}  {m['size']} items from the holdout split")
    print(f"  flagged   {m['flagged_selected']}")
    print(f"  unflagged {m['unflagged_selected']}")
    print(f"  families  {m['family_counts']}")
    print(f"  double    {m['double_review_items']}")
    print(f"  commit    {m['source_commit']}")
    print(f"  -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
