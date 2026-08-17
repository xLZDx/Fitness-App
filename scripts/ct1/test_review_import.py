# -*- coding: utf-8 -*-
"""CT-1 import and adjudication: what a returned review is not allowed to be.

    python -m pytest scripts/ct1/test_review_import.py -q

Almost every test here is a refusal, and every refusal is a case where the
alternative is a label that looks exactly like a good one. A malformed
submission gets noticed. A well-formed submission describing content that has
since changed, or answered by somebody who was not asked, does not.

One test is deliberately not a refusal: a well-formed submission imports. An
importer that refuses everything satisfies every other test in this file.
"""
from __future__ import annotations

import pytest

from label_contract import LabelSource
from review_batch import REVIEW_QUESTIONS, REVIEW_SCHEMA_VERSION, assign, select
from review_import import (
    ReviewImportError,
    adjudicate,
    agreement,
    import_reviews,
)
from test_review_batch import _corpus

NOW = "2026-08-17T09:00:00+00:00"


def _batch(size: int = 60):
    en, ru, eq = _corpus()
    batch = select(en, ru, eq, size=size)
    batch["assignments"] = assign(batch["items"])
    return batch


def _slot_of(batch, item_id):
    return batch["assignments"]["primary"][item_id]


def _submission(batch, *, reviewer=None, item=None, slot=None, **over):
    """A submission that imports, so a test can break exactly one thing."""
    item = item or batch["items"][0]
    slot = slot or _slot_of(batch, item["item_id"])
    reviewer = reviewer or f"qa.{slot.lower()}"
    sub = {
        "batch_id": batch["manifest"]["batch_id"],
        "review_schema_version": REVIEW_SCHEMA_VERSION,
        "reviewer": reviewer,
        "reviewer_slot": slot,
        "reviewer_kind": "HUMAN",
        "submitted_at": NOW,
        "reviews": [{
            "item_id": item["item_id"],
            "source_content_version": item["source_content_version"],
            "review_timestamp": NOW,
            "review_status": "COMPLETE",
            "answers": {q: "ok" for q in REVIEW_QUESTIONS},
            "reason_codes": [],
            "note": "",
            "needs_domain_review": False,
        }],
    }
    sub.update(over)
    return sub


def _import(batch, sub, *, reviewer_slot=None):
    """Import against a package sized for the reviewer under test.

    The real assignment map deals ~1/3 of the batch to each slot; a test
    submission answers one row. Coverage accounting therefore reports the rest
    as NOT_RETURNED, which is correct and not what most of these tests are
    about, so they pass the real map and read only the parts they assert on.
    """
    return import_reviews(sub, batch, assignments=batch["assignments"])


# --------------------------------------------------------------------------
# the control case
# --------------------------------------------------------------------------


def test_a_well_formed_submission_imports_as_reviewed_labels():
    batch = _batch()
    out = _import(batch, _submission(batch))
    assert len(out["labels"]) == len(REVIEW_QUESTIONS)
    assert {l.source for l in out["labels"]} == {
        LabelSource.HUMAN_REVIEWED_QA_LABEL
    }
    assert all(l.value is True for l in out["labels"])
    # The label carries its own split, so `leakage_guard` can refuse it without
    # being handed a second file.
    assert {l.evidence["split"] for l in out["labels"]} == {"holdout"}


# --------------------------------------------------------------------------
# who is allowed to have answered
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "reviewer",
    ["claude", "gpt-4o", "codex-cli", "content-bot", "auto-reviewer",
     "baseline heuristic", "review script v2"],
)
def test_a_machine_shaped_reviewer_identity_is_refused(reviewer):
    batch = _batch()
    with pytest.raises(ReviewImportError):
        _import(batch, _submission(batch, reviewer=reviewer))


def test_reviewer_kind_must_be_stated_rather_than_omitted():
    batch = _batch()
    sub = _submission(batch)
    sub.pop("reviewer_kind")
    with pytest.raises(ReviewImportError, match="reviewer_kind"):
        _import(batch, sub)


def test_a_review_of_a_row_assigned_to_somebody_else_is_refused():
    """Section 12. Importing it adds an unplanned reviewer to a row and
    changes what that row's agreement figure measures."""
    batch = _batch()
    item = batch["items"][0]
    mine = _slot_of(batch, item["item_id"])
    other = next(s for s in batch["assignments"]["slots"] if s != mine)
    sub = _submission(batch, item=item, slot=other)
    with pytest.raises(ReviewImportError, match="not assigned"):
        _import(batch, sub)


def test_an_unknown_reviewer_slot_is_refused():
    batch = _batch()
    with pytest.raises(ReviewImportError, match="no package"):
        _import(batch, _submission(batch, slot="R9"))


# --------------------------------------------------------------------------
# what the submission is about
# --------------------------------------------------------------------------


def test_a_submission_for_another_batch_is_refused():
    batch = _batch()
    with pytest.raises(ReviewImportError, match="batch"):
        _import(batch, _submission(batch, batch_id="CT1_REVIEW_BATCH_999"))


def test_a_submission_under_the_previous_review_schema_is_refused():
    """A v1 answer cannot carry a content digest, a reason code or a status.
    Reading it as v2 is guessing what the reviewer meant."""
    batch = _batch()
    with pytest.raises(ReviewImportError, match="review schema"):
        _import(batch, _submission(batch, review_schema_version=1))


def test_a_review_of_a_row_nobody_was_asked_about_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["item_id"] = "row-that-was-never-in-any-batch"
    with pytest.raises(ReviewImportError, match="not in this batch"):
        _import(batch, sub)


# --------------------------------------------------------------------------
# section 12 — content that moved under the reviewer
# --------------------------------------------------------------------------


def test_a_review_of_content_that_has_changed_is_marked_stale_not_imported():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["source_content_version"] = "0" * 32
    out = _import(batch, sub)
    assert out["labels"] == []
    assert len(out["stale"]) == 1
    assert out["stale"][0]["disposition"] == "RE_REVIEW_REQUIRED"
    assert out["outcomes"][sub["reviews"][0]["item_id"]] == "STALE"


def test_a_stale_row_is_not_silently_dropped():
    """It is reported, not absent. A dropped row is indistinguishable from one
    that was never assigned."""
    batch = _batch()
    sub = _submission(batch)
    item_id = sub["reviews"][0]["item_id"]
    sub["reviews"][0]["source_content_version"] = "0" * 32
    out = _import(batch, sub)
    assert item_id in {s["item_id"] for s in out["stale"]}
    assert out["coverage"]["STALE"] == 1


# --------------------------------------------------------------------------
# timestamps
# --------------------------------------------------------------------------


@pytest.mark.parametrize("bad", ["yesterday", "2026-13-45T00:00:00Z", "", None])
def test_a_malformed_review_timestamp_is_refused(bad):
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["review_timestamp"] = bad
    with pytest.raises(ReviewImportError):
        _import(batch, sub)


def test_a_timestamp_without_an_offset_is_refused():
    """A naive instant cannot be ordered against a catalogue edit, which is
    how staleness is judged."""
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["review_timestamp"] = "2026-08-17T09:00:00"
    with pytest.raises(ReviewImportError, match="offset"):
        _import(batch, sub)


def test_a_submission_with_no_submitted_at_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub.pop("submitted_at")
    with pytest.raises(ReviewImportError, match="submitted_at"):
        _import(batch, sub)


# --------------------------------------------------------------------------
# duplicates
# --------------------------------------------------------------------------


def test_a_row_reviewed_twice_in_one_submission_is_refused_when_conflicting():
    batch = _batch()
    sub = _submission(batch)
    second = dict(sub["reviews"][0])
    second["answers"] = {**second["answers"], REVIEW_QUESTIONS[0]: "problem"}
    second["reason_codes"] = ["steps_missing"]
    sub["reviews"].append(second)
    with pytest.raises(ReviewImportError, match="CONFLICTING"):
        _import(batch, sub)


def test_a_row_reviewed_twice_identically_is_still_refused():
    """Not harmless. Which entry is the review is a question the file cannot
    answer, and a de-duplicating importer teaches submitters that duplicates
    are fine right up until one of them differs."""
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"].append(dict(sub["reviews"][0]))
    with pytest.raises(ReviewImportError, match="twice"):
        _import(batch, sub)


# --------------------------------------------------------------------------
# the answers themselves
# --------------------------------------------------------------------------


def test_a_partially_answered_row_is_refused_rather_than_half_imported():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"].pop(REVIEW_QUESTIONS[0])
    with pytest.raises(ReviewImportError, match="no answer for"):
        _import(batch, sub)


def test_an_answer_to_a_question_nobody_asked_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"]["is_this_exercise_safe"] = "ok"
    with pytest.raises(ReviewImportError, match="not asked"):
        _import(batch, sub)


def test_an_unusable_verdict_word_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "probably fine"
    with pytest.raises(ReviewImportError, match="not one of"):
        _import(batch, sub)


def test_unsure_is_an_abstention_and_never_a_class():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "unsure"
    out = _import(batch, sub)
    assert len(out["labels"]) == len(REVIEW_QUESTIONS) - 1
    assert all(l.check != REVIEW_QUESTIONS[0] for l in out["labels"])


# --------------------------------------------------------------------------
# reason codes
# --------------------------------------------------------------------------


def test_a_problem_verdict_without_a_reason_code_is_refused():
    """An uncoded problem cannot be counted, compared, or acted on."""
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    with pytest.raises(ReviewImportError, match="reason code"):
        _import(batch, sub)


def test_a_reason_code_outside_the_vocabulary_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    sub["reviews"][0]["reason_codes"] = ["looks_a_bit_odd"]
    with pytest.raises(ReviewImportError, match="vocabulary"):
        _import(batch, sub)


def test_other_requires_a_note():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    sub["reviews"][0]["reason_codes"] = ["other"]
    with pytest.raises(ReviewImportError, match="requires a note"):
        _import(batch, sub)
    sub["reviews"][0]["note"] = "The title is in the wrong language."
    assert _import(batch, sub)["labels"]


def test_a_coded_problem_reaches_the_label_evidence():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    sub["reviews"][0]["reason_codes"] = ["steps_truncated"]
    out = _import(batch, sub)
    bad = [l for l in out["labels"] if l.check == REVIEW_QUESTIONS[0]]
    assert bad and bad[0].value is False
    assert bad[0].evidence["reason_codes"] == ["steps_truncated"]


# --------------------------------------------------------------------------
# section 48 — an unknown is not a clean row
# --------------------------------------------------------------------------


def test_a_row_nobody_returned_is_unknown_and_not_reviewed_none():
    batch = _batch()
    out = _import(batch, _submission(batch))
    assigned = out["coverage"]["assigned"]
    assert out["coverage"]["COMPLETE"] == 1
    assert out["coverage"]["NOT_RETURNED"] == assigned - 1
    assert "NOT_RETURNED" in out["coverage"]["note"]


def test_a_skipped_row_produces_no_labels_and_is_counted_separately():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["review_status"] = "SKIPPED"
    sub["reviews"][0]["answers"] = {}
    out = _import(batch, sub)
    assert out["labels"] == []
    assert out["coverage"]["SKIPPED"] == 1
    assert out["coverage"]["COMPLETE"] == 0


def test_a_skip_carrying_answers_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["review_status"] = "SKIPPED"
    with pytest.raises(ReviewImportError, match="SKIPPED"):
        _import(batch, sub)


def test_an_unknown_review_status_is_refused():
    batch = _batch()
    sub = _submission(batch)
    sub["reviews"][0]["review_status"] = "DONE"
    with pytest.raises(ReviewImportError, match="review_status"):
        _import(batch, sub)


# --------------------------------------------------------------------------
# agreement
# --------------------------------------------------------------------------


def _two_reviewers(batch):
    """One doubled row, answered by both of the reviewers it was dealt to."""
    doubled = next(
        i for i in batch["items"]
        if i["item_id"] in batch["assignments"]["secondary"]
    )
    rid = doubled["item_id"]
    first = batch["assignments"]["primary"][rid]
    second = batch["assignments"]["secondary"][rid]
    return doubled, first, second


def test_disagreement_is_reported_and_not_resolved():
    batch = _batch()
    item, one, two = _two_reviewers(batch)
    a = _import(batch, _submission(batch, item=item, slot=one))["labels"]
    sub_b = _submission(batch, item=item, slot=two)
    sub_b["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    sub_b["reviews"][0]["reason_codes"] = ["steps_missing"]
    b = _import(batch, sub_b)["labels"]

    out = agreement(a, b)
    assert out["compared"] == len(REVIEW_QUESTIONS)
    assert out["disagreed"] == 1
    assert out["items"] == [
        {"item_id": item["item_id"], "check": REVIEW_QUESTIONS[0]}
    ]
    assert out["resolution"] == "THIRD_REVIEWER_REQUIRED"
    assert "value" not in out and "winner" not in out


def test_agreement_on_nothing_reports_no_rate_rather_than_a_perfect_one():
    # `0/0 = 1.0` would report flawless agreement between two reviewers who
    # never looked at the same row.
    assert agreement([], [])["rate"] is None
    assert agreement([], [])["kappa"] is None


def test_kappa_is_null_when_both_reviewers_used_one_category():
    """Not 1.0. Two people who answered `ok` to everything agree completely and
    by chance; kappa's denominator is zero and there is nothing to report."""
    batch = _batch()
    item, one, two = _two_reviewers(batch)
    a = _import(batch, _submission(batch, item=item, slot=one))["labels"]
    b = _import(batch, _submission(batch, item=item, slot=two))["labels"]
    out = agreement(a, b)
    assert out["rate"] == 1.0
    assert out["kappa"] is None
    assert "null where undefined" in out["kappa_note"]


# --------------------------------------------------------------------------
# adjudication — section 14
# --------------------------------------------------------------------------


def _disagreeing(batch):
    item, one, two = _two_reviewers(batch)
    a = _import(batch, _submission(batch, item=item, slot=one))["labels"]
    sub_b = _submission(batch, item=item, slot=two)
    sub_b["reviews"][0]["answers"][REVIEW_QUESTIONS[0]] = "problem"
    sub_b["reviews"][0]["reason_codes"] = ["steps_missing"]
    b = _import(batch, sub_b)["labels"]
    return item, {f"qa.{one.lower()}": a, f"qa.{two.lower()}": b}


def test_a_disagreement_stays_unadjudicated_without_a_ruling():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer)
    key = f"{item['item_id']}|{REVIEW_QUESTIONS[0]}"
    assert out["states"][key]["state"] == "DISAGREE_UNADJUDICATED"
    assert out["states"][key]["value"] is None
    assert out["counts"]["DISAGREE_UNADJUDICATED"] == 1


def test_agreement_is_stated_as_agreement_not_as_a_single_answer():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer)
    agreed = f"{item['item_id']}|{REVIEW_QUESTIONS[1]}"
    assert out["states"][agreed]["state"] == "AGREE"
    assert out["states"][agreed]["value"] is True


def test_a_third_reviewer_can_settle_it():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer, adjudications=[{
        "item_id": item["item_id"], "check": REVIEW_QUESTIONS[0],
        "adjudicator": "qa.lead.morgan", "value": False,
        "rationale": "the title names a different movement",
    }])
    key = f"{item['item_id']}|{REVIEW_QUESTIONS[0]}"
    assert out["states"][key]["state"] == "ADJUDICATED"
    assert out["states"][key]["value"] is False
    assert out["states"][key]["adjudicator"] == "qa.lead.morgan"


def test_an_adjudication_that_reached_no_decision_is_unresolved():
    """Not folded back into whichever reviewer answered first."""
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer, adjudications=[{
        "item_id": item["item_id"], "check": REVIEW_QUESTIONS[0],
        "adjudicator": "qa.lead.morgan", "value": None,
        "rationale": "the source content is ambiguous",
    }])
    key = f"{item['item_id']}|{REVIEW_QUESTIONS[0]}"
    assert out["states"][key]["state"] == "UNRESOLVED"
    assert out["states"][key]["value"] is None


def test_an_adjudicator_may_not_be_one_of_the_two_reviewers():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    who = sorted(per_reviewer)[0]
    with pytest.raises(ReviewImportError, match="already reviewed"):
        adjudicate(per_reviewer, adjudications=[{
            "item_id": item["item_id"], "check": REVIEW_QUESTIONS[0],
            "adjudicator": who, "value": True,
        }])


@pytest.mark.parametrize("who", ["claude", "arbiter-bot", "tie-break script"])
def test_a_machine_may_not_decide_which_human_was_right(who):
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    with pytest.raises(ReviewImportError):
        adjudicate(per_reviewer, adjudications=[{
            "item_id": item["item_id"], "check": REVIEW_QUESTIONS[0],
            "adjudicator": who, "value": True,
        }])


def test_an_anonymous_adjudication_is_refused():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    with pytest.raises(ReviewImportError, match="named person"):
        adjudicate(per_reviewer, adjudications=[{
            "item_id": item["item_id"], "check": REVIEW_QUESTIONS[0],
            "value": True,
        }])


def test_a_row_routed_to_domain_review_is_not_given_a_content_verdict():
    batch = _batch()
    item, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer, domain_review={item["item_id"]})
    for record in out["states"].values():
        assert record["state"] == "NEEDS_DOMAIN_REVIEW"
        assert record["value"] is None


def test_adjudication_never_reports_a_majority_or_first_wins_policy():
    batch = _batch()
    _, per_reviewer = _disagreeing(batch)
    out = adjudicate(per_reviewer)
    assert "No automatic tie-break" in out["policy"]
