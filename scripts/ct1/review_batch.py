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
from label_contract import LabelSource  # noqa: E402

#: The manifest/export SHAPE.
#:
#: 2, because the shape moved: v2 manifests carry `review_schema_version`,
#: `supersedes`, `supersession`, `reason_codes` and `review_statuses`, none of
#: which a v1 manifest has. Leaving this at 1 while adding fields is how a
#: consumer that dispatches on it ends up unable to tell a 001 manifest (verdict
#: `cannot_judge`, no reason codes) from a 002 one. Raised in gate review.
SCHEMA_VERSION = 2

#: The version of the ANSWER schema — what a reviewer is asked and may return.
#:
#: Separate from ``SCHEMA_VERSION`` (the manifest/export shape) because the two
#: change for different reasons and only this one invalidates returned work. A
#: review answered under v1 cannot be read as a v2 answer: v2 adds required
#: reason codes, renames the abstention, and carries a content digest per row.
REVIEW_SCHEMA_VERSION = 2

#: The batch a reviewer is working on.
#:
#: A new id each time row assignments change, rather than a rebuild under an id
#: somebody may already hold a package for. Section 45.
#:
#: 002 replaced 001 for a schema change that did not move the rows. 003 replaces
#: 002 because the rows DID move: the baseline's duplicate checks reported the
#: second and later occurrence in FILE ORDER, so which member of a duplicate
#: group got flagged was a fact about the catalogue's layout rather than its
#: content. Fixed to a deterministic representative, which changed the flagged
#: holdout population from 56 to 55 and moved two rows in and out of the batch.
#:
#: Rebuilding 002 in place was the tempting alternative: it was committed the
#: same afternoon, never pushed, and no reviewer had returned anything. That
#: reasoning was rejected because it rests on "nobody has a copy", and this
#: checkout is shared -- the 002 reviewer pages existed on disk where anyone
#: could have opened one. A claim I cannot check is not allowed to be the thing
#: a rule hangs on. A new directory costs nothing and needs no such claim.
BATCH_ID = "CT1_REVIEW_BATCH_003"

#: The batch this one replaces, and why.
SUPERSEDES = "CT1_REVIEW_BATCH_002"
SUPERSESSION = (
    "SUPERSEDED_BEFORE_REVIEW. No reviewer returned a submission against "
    "CT1_REVIEW_BATCH_002 or CT1_REVIEW_BATCH_001. 002 superseded 001 for a "
    "review-schema change that left the row selection identical. 003 supersedes "
    "002 for a defect in the baseline's duplicate checks, which selected the "
    "flagged member of a duplicate group by position in the catalogue file "
    "rather than by a property of the rows; the fix changed the flagged holdout "
    "population from 56 to 55 and moved two rows. A submission against 001 or "
    "002 is NOT importable here: the row assignments differ, and 001 predates "
    "the fields review schema v2 requires."
)

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
#: Widened at review schema v2 from five questions to the eight content
#: dimensions this repository can actually supply evidence for. Each names a
#: comparison a reviewer can make from the row in front of them, against
#: something else in the same row. None of them can be answered "correctly" by
#: knowing the exercise; they are answerable by reading.
REVIEW_QUESTIONS = (
    # Title/content agreement.
    "title_matches_content",
    # Content completeness.
    "content_is_complete",
    # Structural consistency: numbering, ordering, formatting of the steps.
    "structure_is_consistent",
    # Internal instruction consistency: steps and tips not contradicting.
    "instructions_are_consistent",
    # Duplicate content.
    "content_is_not_duplicated",
    # Equipment/content agreement.
    "equipment_matches_content",
    # Localisation quality.
    "localisation_is_faithful",
    # Metadata/content consistency: muscles, difficulty, stretch flag.
    "metadata_matches_content",
)

#: The answers a question may take.
#:
#: ``unsure`` is not politeness. Forcing a verdict on a row the reviewer cannot
#: assess manufactures a label, and a manufactured label is indistinguishable
#: from a real one once it is in the file. It is imported as an ABSTENTION and
#: never as a target. Renamed from v1's ``cannot_judge`` because the reviewer
#: interface says UNSURE and a stored value that disagrees with the button that
#: produced it is a decoding error waiting to be argued about.
VERDICTS = ("ok", "problem", "unsure")

#: What a reviewer may say is WRONG, as a closed vocabulary.
#:
#: A free-text note alone cannot be counted, compared between reviewers, or
#: turned into a stratum; a closed vocabulary can. ``other`` exists so the
#: vocabulary being incomplete shows up as a countable category instead of as
#: reviewers forcing a near-miss code, and the importer requires a note with it.
#:
#: These are shown identically on every row, so they carry no information about
#: any particular row. That is what keeps them compatible with blindness: the
#: reviewer learns the shape of the defects this catalogue can have, which is
#: training, and learns nothing about whether a rule fired on the row open in
#: front of them, which is the leak.
REASON_CODES = (
    "steps_missing",
    "steps_truncated",
    "steps_out_of_order",
    "steps_contradict_each_other",
    "title_describes_different_movement",
    "duplicate_of_another_row",
    "duplicate_text_within_row",
    "equipment_not_used_by_steps",
    "equipment_required_but_absent",
    "translation_missing",
    "translation_left_in_source_language",
    "translation_changes_meaning",
    "muscles_do_not_match_content",
    "difficulty_does_not_match_content",
    "formatting_broken",
    "other",
)

#: What happened to a row, as distinct from what the reviewer concluded.
#:
#: Section 48: ``UNKNOWN`` may not collapse into "reviewed, nothing found".
#: A row nobody returned is absent from the submission entirely and is counted
#: as ``NOT_RETURNED`` by the importer; the two states below are the ones a
#: reviewer can assert. ``SKIPPED`` carries no answers by construction.
REVIEW_STATUSES = ("COMPLETE", "SKIPPED")

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


#: Fields whose value the reviewer's answer is ABOUT.
#:
#: The digest covers these and nothing else, so that an unrelated catalogue edit
#: -- a field this batch never showed anyone -- does not invalidate returned
#: work. Widening this tuple invalidates every outstanding review, which is
#: correct and should be a decision rather than a side effect.
REVIEWED_FIELDS = (
    "title", "summary", "steps", "tips", "equipment_id", "muscles",
    "difficulty", "is_stretch", "ru",
)


def content_version(item: dict[str, Any]) -> str:
    """A digest of exactly the content a reviewer was shown."""
    payload = {k: item.get(k) for k in REVIEWED_FIELDS}
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                           separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]


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
        # What the reviewer actually looked at, as one value.
        #
        # Section 12: if the row changed after the batch was built, the review
        # describes content that is no longer there. Importing it anyway is the
        # quietest way to get a label that is wrong about the current catalogue
        # and indistinguishable from one that is right. The importer compares
        # this digest and marks a mismatch STALE rather than repairing it.
        item["source_content_version"] = content_version(item)
        blind_items.append(item)

    # Deliberately NOT on the item: which rows are double-reviewed.
    #
    # A reviewer who can see that a row is also going to somebody else answers
    # it differently -- more carefully, or less, but not the same -- and the
    # agreement rate then measures the marking rather than the labelling. The
    # assignment layer knows; the item does not, and `test_review_batch`
    # asserts the key is absent from what gets exported.

    # Sealed: the baseline's own labels for the same items. Kept so the batch
    # can be evaluated afterwards; NOT part of what a reviewer opens.
    sealed = {
        r["id"]: sorted(checks_by_item.get(r["id"], set())) for r in items
    }

    doubles = [i["item_id"] for i in blind_items if is_double(i["item_id"])]
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "review_schema_version": REVIEW_SCHEMA_VERSION,
        "supersedes": SUPERSEDES,
        "supersession": SUPERSESSION,
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
        "reason_codes": list(REASON_CODES),
        "review_statuses": list(REVIEW_STATUSES),
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


class BatchContractError(ValueError):
    """A batch whose recorded contract is not the one this code implements."""


#: Manifest fields that record the review contract, and the constant each must
#: equal. The manifest is the contract between the builder, the page generator,
#: the importer and the evaluator; if it merely DESCRIBES the contract while
#: every consumer reads the code constants instead, it is documentation that
#: cannot be wrong, which is the same as documentation nobody checks.
CONTRACT_FIELDS = {
    "schema_version": lambda: SCHEMA_VERSION,
    "review_schema_version": lambda: REVIEW_SCHEMA_VERSION,
    "questions": lambda: list(REVIEW_QUESTIONS),
    "verdicts": lambda: list(VERDICTS),
    "reason_codes": lambda: list(REASON_CODES),
    "review_statuses": lambda: list(REVIEW_STATUSES),
}


def check_contract(manifest: dict[str, Any]) -> None:
    """Refuse to process a batch this code no longer agrees with.

    Raised in gate review. The scenario is concrete: the constants move to v3,
    somebody regenerates reviewer pages from the committed v2 batch directory —
    which is the documented command — and the pages ask v3 questions over a v2
    batch while stamping v3 on the submissions. The importer then accepts them
    against a manifest that says v2, and nothing anywhere errors.

    Checked field by field rather than by comparing one version number, because
    a version number is only as good as the discipline of bumping it, and the
    field lists are the thing that actually has to match.
    """
    for field, expected in CONTRACT_FIELDS.items():
        want = expected()
        got = manifest.get(field)
        if got != want:
            raise BatchContractError(
                f"batch {manifest.get('batch_id')!r} records {field}={got!r}; "
                f"this code implements {want!r}. Rebuild the batch, or process "
                "it with the code it was built by -- reading it under a "
                "different contract is guessing what the reviewer was asked"
            )


def assert_authoritative(manifest: dict[str, Any]) -> None:
    """Refuse to build reviewer pages or an evaluation set from a dead batch.

    ``check_contract`` above happens to reject 001 and 002 today, because their
    manifests were written at ``schema_version: 1``. That is an accident of
    history, not a rule: a future batch superseded WITHOUT a schema change
    would sail through it. Superseded batches stay in the repository as
    historical evidence — a test rebuilds against them — so something has to
    say which one is live, and it should say so because it is the rule rather
    than because the numbers happen not to match.
    """
    got = manifest.get("batch_id")
    if got != BATCH_ID:
        raise BatchContractError(
            f"{got!r} is not the authoritative batch. {BATCH_ID} is. A "
            "superseded batch is kept as evidence and must not be dealt to a "
            "reviewer or built into an evaluation dataset: its row assignments "
            "are not the live ones, and a submission against it would be "
            "refused on import after the work had already been done"
        )


def is_double(item_id: str) -> bool:
    """Whether this row goes to a second reviewer as well.

    A property of the id, so it is stable across rebuilds and is not a property
    of who opened the file first.
    """
    return _bucket(item_id, "double", 100) < round(DOUBLE_REVIEW_SHARE * 100)


#: The reviewer slots a batch is dealt into.
#:
#: Slots, not people. A slot is bound to a named person in the procedure, in a
#: file this repository does not hold, because binding it here would put a
#: reviewer's identity in a public catalogue artefact for no benefit -- the
#: agreement maths only needs to know that two answers came from two different
#: people.
REVIEWER_SLOTS = ("R1", "R2", "R3")


def assign(
    items: list[dict[str, Any]], slots: tuple[str, ...] = REVIEWER_SLOTS
) -> dict[str, Any]:
    """Deal the batch into per-reviewer packages, reproducibly.

    Derived entirely from the item ids and the slot list, so the same batch
    deals the same way on any machine and a lost package can be regenerated
    rather than reconstructed from somebody's memory of who had what.

    The second reviewer of a doubled row is never its first: picked from the
    remaining slots, so a "double review" cannot degenerate into one person
    answering twice.
    """
    if len(slots) < 2:
        raise ValueError("double review needs at least two reviewer slots")
    primary: dict[str, str] = {}
    secondary: dict[str, str] = {}
    for item in items:
        rid = item["item_id"]
        p = slots[_bucket(rid, "primary", len(slots))]
        primary[rid] = p
        if is_double(rid):
            others = [s for s in slots if s != p]
            secondary[rid] = others[_bucket(rid, "secondary", len(others))]

    packages: dict[str, list[str]] = {s: [] for s in slots}
    for rid, slot in primary.items():
        packages[slot].append(rid)
    for rid, slot in secondary.items():
        packages[slot].append(rid)
    for slot in packages:
        # Sorted by a hash rather than by id: a package ordered by id would put
        # the doubled rows at reproducible positions relative to each other in
        # both reviewers' packages, which is a weak but real signal about which
        # rows are doubled. It also stops a reviewer inferring anything from
        # catalogue order.
        packages[slot].sort(key=lambda r: _rank(r, "package"))

    return {
        "slots": list(slots),
        "primary": primary,
        "secondary": secondary,
        "packages": packages,
        "counts": {s: len(v) for s, v in packages.items()},
        "double_review_items": sorted(secondary),
        "blindness": (
            "A reviewer's package does NOT record which of its rows are also "
            "assigned to somebody else. Marking them would measure the marking "
            "rather than the labelling."
        ),
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
    print(f"  packages  {batch['assignments']['counts']}")
    print(f"  commit    {m['source_commit']}")
    print(f"  -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
