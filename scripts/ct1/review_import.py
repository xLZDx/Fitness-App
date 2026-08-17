# -*- coding: utf-8 -*-
"""CT-1 — validating returned human reviews, and adjudicating the doubled ones.

    python -m pytest scripts/ct1/test_review_import.py -q

``review_batch`` decides what a person is asked. This decides what comes back,
and it refuses rather than repairs. Every rejection below is a case where the
alternative is a label that looks exactly like a good one — which is the only
kind of bad label that matters, because a malformed one gets noticed.

## What it will not do

**It will not resolve a disagreement.** Two reviewers who answered differently
produce ``DISAGREE_UNADJUDICATED`` and stay there until a third person records
an adjudication. Majority-wins and first-reviewer-wins are both a machine
deciding which human was right, and either would let the corpus contain a
"human label" no human agreed to.

**It will not import a review of content that has since changed.** The batch
recorded a digest of exactly the fields it showed; a mismatch means the reviewer
judged text that is no longer there. That review is returned as ``STALE`` with
``RE_REVIEW_REQUIRED``, never merged and never silently dropped.

**It will not treat silence as a verdict.** A row nobody returned is
``NOT_RETURNED``, which is an unknown, not a clean row. Section 48.
"""
from __future__ import annotations

import collections
import datetime as dt
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from label_contract import Label, LabelSource  # noqa: E402
from review_batch import (  # noqa: E402
    MACHINE_REVIEWER_MARKERS,
    check_contract,
    REASON_CODES,
    REVIEW_QUESTIONS,
    REVIEW_SCHEMA_VERSION,
    REVIEW_STATUSES,
    VERDICTS,
)

#: Adjudication states. Explicit, and none of them means "we sorted it out".
#:
#: SINGLE                  one reviewer was asked; nothing to adjudicate
#: AGREE                   two reviewers, same answer
#: DISAGREE_UNADJUDICATED  two reviewers, different answers, nobody has ruled
#: ADJUDICATED             a third reviewer recorded a decision
#: UNRESOLVED              adjudication was attempted and reached no decision
#: NEEDS_DOMAIN_REVIEW     routed out of content QA entirely
ADJUDICATION_STATES = (
    "SINGLE",
    "AGREE",
    "DISAGREE_UNADJUDICATED",
    "ADJUDICATED",
    "UNRESOLVED",
    "NEEDS_DOMAIN_REVIEW",
)

#: Per-row outcomes the importer reports. ``NOT_RETURNED`` is never asserted by
#: a reviewer; it is what is left over after everything they did return.
ROW_OUTCOMES = ("COMPLETE", "SKIPPED", "STALE", "NOT_RETURNED")


class ReviewImportError(ValueError):
    """A submitted review that would put an unusable label in the corpus."""


def _timestamp(value: Any, where: str) -> dt.datetime:
    """An ISO-8601 instant WITH an offset, or a refusal.

    A naive timestamp is not a fact about when something happened; it is a fact
    about when it happened in a timezone the file does not record. Reviews are
    ordered against catalogue edits to decide staleness, so an ambiguous instant
    is an ambiguous staleness verdict.
    """
    if not isinstance(value, str) or not value:
        raise ReviewImportError(f"{where}: a timestamp is required")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ReviewImportError(
            f"{where}: {value!r} is not an ISO-8601 timestamp ({exc})"
        ) from exc
    if parsed.tzinfo is None:
        raise ReviewImportError(
            f"{where}: {value!r} has no UTC offset. A naive instant cannot be "
            "ordered against a catalogue edit, which is how staleness is judged"
        )
    return parsed


def _check_reviewer(submission: dict[str, Any]) -> str:
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
    return reviewer


def import_reviews(
    submission: dict[str, Any],
    batch: dict[str, Any],
    *,
    assignments: dict[str, Any],
) -> dict[str, Any]:
    """Validate one reviewer's returned file.

    Returns labels plus a coverage account, because the labels alone cannot
    distinguish "reviewed and clean" from "never looked at".

    ``assignments`` is REQUIRED. It was optional, defaulting to "every row in
    the batch is assigned to this reviewer", which silently defeated the
    unplanned-reviewer protection below for any caller that forgot it. A
    convenience default that disables a check is a check with an off switch.
    """
    manifest = batch["manifest"]
    # Before anything else: is this batch's recorded contract the one this code
    # implements? Every check below reads a code constant, so a batch built
    # under a different vocabulary would be validated against questions its
    # reviewers were never asked.
    check_contract(manifest)
    if submission.get("batch_id") != manifest["batch_id"]:
        raise ReviewImportError(
            f"submission is for batch {submission.get('batch_id')!r}, this is "
            f"{manifest['batch_id']!r}"
        )
    if submission.get("review_schema_version") != REVIEW_SCHEMA_VERSION:
        raise ReviewImportError(
            f"submission is review schema v"
            f"{submission.get('review_schema_version')!r}, this batch is v"
            f"{REVIEW_SCHEMA_VERSION}. An answer means what its schema says it "
            "means; reading it under a different one is a guess"
        )
    reviewer = _check_reviewer(submission)
    _timestamp(submission.get("submitted_at"), "submitted_at")

    items = {i["item_id"]: i for i in batch["items"]}

    # Which rows THIS reviewer was asked about.
    #
    # Not "which rows are in the batch". A review of a row somebody else was
    # dealt has no sampling provenance for this reviewer and, if the row is
    # doubled, silently turns a two-person agreement measurement into a
    # three-person one nobody planned.
    #
    # The submission names its SLOT, and the slot names the package. The slot
    # is not derived from the reviewer's name: a person's name is not a key,
    # two people can share one, and a slot whose owner changed mid-batch would
    # otherwise silently look like an unassigned reviewer.
    slot = submission.get("reviewer_slot")
    packages = (assignments or {}).get("packages") or {}
    if slot not in packages:
        raise ReviewImportError(
            f"reviewer_slot {slot!r} holds no package in this batch. Slots "
            f"are {sorted(packages)}"
        )
    assigned = set(packages[slot])

    labels: list[Label] = []
    outcomes: dict[str, str] = {}
    stale: list[dict[str, Any]] = []
    domain_review: list[str] = []
    notes: dict[str, str] = {}
    reasons: dict[str, list[str]] = {}
    seen: dict[str, dict[str, Any]] = {}

    for entry in submission.get("reviews") or []:
        if not isinstance(entry, dict):
            # Refused rather than allowed to become an AttributeError. This
            # module's whole stance is that a bad submission is REFUSED with a
            # sentence saying why; a stack trace out of the middle of the loop
            # is the same rejection delivered as a bug report.
            raise ReviewImportError(
                f"a review entry is {type(entry).__name__}, not an object"
            )
        item_id = entry.get("item_id")
        if item_id not in items:
            raise ReviewImportError(
                f"{item_id!r} is not in this batch. A review of a row nobody "
                "was asked about has no sampling provenance and cannot be "
                "used as evaluation"
            )
        if item_id not in assigned:
            raise ReviewImportError(
                f"{item_id!r} was not assigned to slot {slot!r}. Importing it "
                "would add an unplanned reviewer to a row and change what its "
                "agreement figure measures"
            )
        if item_id in seen:
            same = seen[item_id] == entry
            raise ReviewImportError(
                f"{item_id!r} appears twice in one submission "
                + ("with identical content. " if same else "with CONFLICTING "
                   "content. ")
                + "Which one is the review is a question the file cannot "
                "answer, and picking either is inventing an answer"
            )
        seen[item_id] = entry

        _timestamp(entry.get("review_timestamp"), f"{item_id}.review_timestamp")

        status = entry.get("review_status")
        if status not in REVIEW_STATUSES:
            raise ReviewImportError(
                f"{item_id}: review_status {status!r} is not one of "
                f"{REVIEW_STATUSES}"
            )

        # Staleness is checked BEFORE the answers, and before status.
        #
        # A review of content that has changed is not made usable by being
        # well formed, and a stale SKIP is still a skip of something else.
        got = entry.get("source_content_version")
        want = items[item_id]["source_content_version"]
        if got != want:
            outcomes[item_id] = "STALE"
            stale.append({
                "item_id": item_id,
                "reviewed_version": got,
                "current_version": want,
                "disposition": "RE_REVIEW_REQUIRED",
                "reason": (
                    "the row changed after the batch was built; this review "
                    "describes content that is no longer there"
                ),
            })
            continue

        note = entry.get("note") or ""
        if not isinstance(note, str):
            raise ReviewImportError(f"{item_id}: note must be text")
        codes = entry.get("reason_codes") or []
        if not isinstance(codes, list) or any(not isinstance(c, str) for c in codes):
            raise ReviewImportError(f"{item_id}: reason_codes must be a list")
        unknown_codes = sorted(set(codes) - set(REASON_CODES))
        if unknown_codes:
            raise ReviewImportError(
                f"{item_id}: reason codes outside the vocabulary: "
                f"{unknown_codes}. A code nobody can count is a note"
            )
        if "other" in codes and not note.strip():
            raise ReviewImportError(
                f"{item_id}: reason code 'other' requires a note. Otherwise "
                "the vocabulary being incomplete is unrecoverable from the file"
            )

        if entry.get("needs_domain_review"):
            # Routed OUT of content QA, not answered inside it. This is not a
            # clinical verdict and cannot become one: label_contract makes
            # CLINICALLY_VALIDATED_LABEL unconstructible from here.
            domain_review.append(item_id)

        answers = entry.get("answers") or {}
        if status == "SKIPPED":
            if answers:
                raise ReviewImportError(
                    f"{item_id}: a SKIPPED row carries no answers. A partial "
                    "answer set filed as a skip reads later as either, and the "
                    "reader will pick the convenient one"
                )
            outcomes[item_id] = "SKIPPED"
            if codes:
                reasons[item_id] = sorted(codes)
            if note.strip():
                notes[item_id] = note
            continue

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
        if "problem" in answers.values() and not codes:
            raise ReviewImportError(
                f"{item_id}: a 'problem' verdict requires at least one reason "
                "code. An uncoded problem cannot be counted, compared between "
                "reviewers, or acted on"
            )

        outcomes[item_id] = "COMPLETE"
        if codes:
            reasons[item_id] = sorted(codes)
        if note.strip():
            notes[item_id] = note
        for question, verdict in sorted(answers.items()):
            if verdict == "unsure":
                # An abstention, kept out of the label set entirely. Importing
                # it as a value would make "we do not know" a class.
                continue
            labels.append(
                Label(
                    item_id=item_id,
                    check=question,
                    source=LabelSource.HUMAN_REVIEWED_QA_LABEL,
                    value=(verdict == "ok"),
                    reviewer=reviewer,
                    evidence={
                        "batch_id": manifest["batch_id"],
                        # The split this label came from, carried on the label
                        # rather than looked up later. `leakage_guard` refuses
                        # to train on it, and a guard that has to consult a
                        # second file to know what it is looking at is a guard
                        # somebody will forget to give the second file.
                        "split": manifest["split"],
                        "review_schema_version": REVIEW_SCHEMA_VERSION,
                        "source_content_version": want,
                        "reason_codes": sorted(codes),
                    },
                )
            )

    not_returned = sorted(assigned - set(outcomes))
    for item_id in not_returned:
        outcomes[item_id] = "NOT_RETURNED"

    counts = collections.Counter(outcomes.values())
    return {
        "reviewer": reviewer,
        "reviewer_slot": slot,
        "labels": labels,
        "outcomes": outcomes,
        "stale": stale,
        "notes": notes,
        "reason_codes": reasons,
        "needs_domain_review": sorted(domain_review),
        "coverage": {
            "assigned": len(assigned),
            **{k: counts.get(k, 0) for k in ROW_OUTCOMES},
            "note": (
                "NOT_RETURNED is an UNKNOWN. It is not 'reviewed, nothing "
                "found' and must not be counted as a clean row."
            ),
        },
    }


def _kappa(pairs: list[tuple[bool, bool]]) -> float | None:
    """Cohen's kappa for two raters over a binary label.

    ``None`` where it is undefined rather than 0.0 or 1.0 — with no observations
    or with no expected disagreement, kappa has no value, and substituting one
    turns "not measurable" into a measurement.
    """
    n = len(pairs)
    if n == 0:
        return None
    po = sum(1 for a, b in pairs if a == b) / n
    pa = sum(1 for a, _ in pairs if a) / n
    pb = sum(1 for _, b in pairs if b) / n
    pe = pa * pb + (1 - pa) * (1 - pb)
    if pe >= 1.0:
        # Both raters used one category for everything. Chance agreement is
        # total, so kappa's denominator is zero: there is nothing to correct
        # for and nothing to report.
        return None
    return (po - pe) / (1 - pe)


def agreement(a: list[Label], b: list[Label]) -> dict[str, Any]:
    """Where two reviewers looked at the same item and question.

    Reports; does not resolve. Raw agreement AND kappa, because raw agreement on
    a corpus where almost everything is fine is high by construction — 95%
    agreement between two people who both answered "ok" to everything is not
    evidence that either was reading.
    """
    left = {(l.item_id, l.check): l.value for l in a}
    right = {(l.item_id, l.check): l.value for l in b}
    shared = sorted(set(left) & set(right))
    disagreements = [k for k in shared if left[k] != right[k]]

    per_question: dict[str, Any] = {}
    for question in REVIEW_QUESTIONS:
        pairs = [
            (left[k], right[k]) for k in shared if k[1] == question
        ]
        agreed = sum(1 for x, y in pairs if x == y)
        per_question[question] = {
            "compared": len(pairs),
            "agreed": agreed,
            "rate": agreed / len(pairs) if pairs else None,
            "kappa": _kappa(pairs),
        }

    return {
        "compared": len(shared),
        "agreed": len(shared) - len(disagreements),
        "disagreed": len(disagreements),
        "rate": (len(shared) - len(disagreements)) / len(shared) if shared else None,
        "kappa": _kappa([(left[k], right[k]) for k in shared]),
        "per_question": per_question,
        "items": [{"item_id": i, "check": c} for i, c in disagreements],
        "resolution": "THIRD_REVIEWER_REQUIRED",
        "kappa_note": (
            "null where undefined: no compared pairs, or no expected "
            "disagreement because both reviewers used a single category."
        ),
    }


def adjudicate(
    per_reviewer: dict[str, list[Label]],
    *,
    adjudications: list[dict[str, Any]] | None = None,
    domain_review: set[str] | None = None,
) -> dict[str, Any]:
    """Assign every reviewed (item, question) an explicit adjudication state.

    No state means "resolved by rule". A disagreement leaves this function in
    exactly the state it arrived in unless a person recorded a decision about
    it, and a recorded decision that reached no conclusion is ``UNRESOLVED``
    rather than being quietly folded back into one reviewer's answer.
    """
    domain_review = domain_review or set()
    by_key: dict[tuple[str, str], dict[str, bool]] = collections.defaultdict(dict)
    for reviewer, labels in sorted(per_reviewer.items()):
        for l in labels:
            by_key[(l.item_id, l.check)][reviewer] = l.value

    rulings: dict[tuple[str, str], dict[str, Any]] = {}
    for record in adjudications or []:
        key = (record.get("item_id"), record.get("check"))
        if key not in by_key:
            raise ReviewImportError(
                f"adjudication for {key} which no two reviewers answered"
            )
        # A ruling on something nobody disputed. Raised in gate review, and
        # worse than it sounds: the branch order below reaches SINGLE and AGREE
        # before it consults a ruling, so such a record was validated, stored,
        # never read -- and the output still attached the adjudicator's NAME to
        # the reviewers' value. An adjudicator recorded against a verdict they
        # contradicted, in a dataset that is immutable once written.
        #
        # Refused rather than applied. If the settled answer is wrong, that is a
        # correction to the review, not an adjudication of a dispute that did
        # not happen, and it should look different in the file.
        if len(by_key[key]) < 2 or len(set(by_key[key].values())) == 1:
            raise ReviewImportError(
                f"{key}: nothing to adjudicate -- "
                + ("only one reviewer answered it"
                   if len(by_key[key]) < 2 else "the reviewers agree")
                + ". An adjudication here would be recorded next to a value "
                "its adjudicator did not give"
            )
        adjudicator = record.get("adjudicator")
        if not isinstance(adjudicator, str) or not adjudicator:
            raise ReviewImportError(f"{key}: adjudication needs a named person")
        low = adjudicator.lower()
        for marker in MACHINE_REVIEWER_MARKERS:
            if marker in low:
                raise ReviewImportError(
                    f"{key}: adjudicator {adjudicator!r} contains {marker!r}. "
                    "A machine may not decide which human was right"
                )
        if adjudicator in by_key[key]:
            raise ReviewImportError(
                f"{key}: {adjudicator!r} already reviewed this row. An "
                "adjudicator who is one of the parties is not a third opinion"
            )
        if "value" in record and record["value"] is not None:
            if not isinstance(record["value"], bool):
                raise ReviewImportError(f"{key}: adjudicated value must be boolean")
        rulings[key] = record

    out: dict[str, Any] = {}
    counts: collections.Counter = collections.Counter()
    for key in sorted(by_key):
        answers = by_key[key]
        item_id = key[0]
        ruling = rulings.get(key)
        if item_id in domain_review:
            state, value = "NEEDS_DOMAIN_REVIEW", None
        elif len(answers) == 1:
            state, value = "SINGLE", next(iter(answers.values()))
        elif len(set(answers.values())) == 1:
            state, value = "AGREE", next(iter(answers.values()))
        elif ruling is None:
            state, value = "DISAGREE_UNADJUDICATED", None
        elif ruling.get("value") is None:
            state, value = "UNRESOLVED", None
        else:
            state, value = "ADJUDICATED", ruling["value"]
        counts[state] += 1
        out[f"{key[0]}|{key[1]}"] = {
            "item_id": key[0],
            "check": key[1],
            "state": state,
            "value": value,
            "reviewers": sorted(answers),
            "answers": {k: answers[k] for k in sorted(answers)},
            "adjudicator": (ruling or {}).get("adjudicator"),
        }

    return {
        "states": out,
        "counts": {s: counts.get(s, 0) for s in ADJUDICATION_STATES},
        "policy": (
            "No automatic tie-break. DISAGREE_UNADJUDICATED is a queue, not a "
            "result, and only AGREE / ADJUDICATED / SINGLE carry a value."
        ),
    }
