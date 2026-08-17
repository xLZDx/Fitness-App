# -*- coding: utf-8 -*-
"""CT-1 evaluation dataset and the estimator that turns a batch into a rate.

    python -m pytest scripts/ct1/test_human_eval.py -q

Two failure modes are worth more than everything else here.

The first is an evaluation set that can be edited after somebody quoted a number
from it. Section 15.

The second is ``bad / 180`` printed under a heading that says "defect rate". The
batch over-samples flagged rows roughly sevenfold on purpose, so its raw
percentages are true about the batch and wrong about anything else. Section 17
and 18. The tests below are mostly about keeping those two numbers far enough
apart that nobody can quote one for the other by accident.

The reviews here are SYNTHETIC and exist to exercise the pipeline. They are not
human labels, they never touch ``core/ml``, and no metric computed from them is
a fact about the catalogue.
"""
from __future__ import annotations

import json

import pytest

from human_eval import (
    CHECK_TO_QUESTION,
    EvaluationError,
    build_eval,
    evaluate,
    write_eval,
)
from review_batch import REVIEW_QUESTIONS, REVIEW_SCHEMA_VERSION, assign, select
from test_review_batch import _corpus

NOW = "2026-08-17T09:00:00+00:00"


def _batch(size: int = 60, dup_every: int = 5):
    # `dup_every=5` gives roughly one flagged row to four unflagged, so the two
    # strata have different populations. At the shared fixture's default of 2
    # they come out equal, and a population-weighted estimate is then
    # numerically identical to an unweighted mean -- which makes the test below
    # unable to fail. Established by mutating the estimator, not by reading it.
    en, ru, eq = _corpus(dup_every=dup_every)
    batch = select(en, ru, eq, size=size)
    batch["assignments"] = assign(batch["items"])
    batch["sealed"] = batch["sealed"]
    return batch


def _review(item, *, bad_questions=()):
    answers = {q: "ok" for q in REVIEW_QUESTIONS}
    for q in bad_questions:
        answers[q] = "problem"
    return {
        "item_id": item["item_id"],
        "source_content_version": item["source_content_version"],
        "review_timestamp": NOW,
        "review_status": "COMPLETE",
        "answers": answers,
        "reason_codes": ["duplicate_of_another_row"] if bad_questions else [],
        "note": "",
        "needs_domain_review": False,
    }


def _submissions(batch, *, bad_for=lambda item_id: ()):
    """One submission per slot, covering every row that slot was dealt."""
    by_id = {i["item_id"]: i for i in batch["items"]}
    out = []
    for slot, ids in sorted(batch["assignments"]["packages"].items()):
        out.append({
            "batch_id": batch["manifest"]["batch_id"],
            "review_schema_version": REVIEW_SCHEMA_VERSION,
            "reviewer": f"qa.{slot.lower()}",
            "reviewer_slot": slot,
            "reviewer_kind": "HUMAN",
            "submitted_at": NOW,
            "reviews": [
                _review(by_id[i], bad_questions=bad_for(i)) for i in ids
            ],
        })
    return out


def _built(batch, **kw):
    return build_eval(
        batch, _submissions(batch, **kw),
        assignments=batch["assignments"],
    )


# --------------------------------------------------------------------------
# the gate itself
# --------------------------------------------------------------------------


def test_with_no_human_labels_there_is_no_metric_to_report():
    """EVALUATION_LABEL_GAP. Every number derivable from this state would be
    the baseline measuring its agreement with itself."""
    batch = _batch()
    empty = _submissions(batch)
    for sub in empty:
        sub["reviews"] = []
    with pytest.raises(EvaluationError, match="EVALUATION_LABEL_GAP"):
        build_eval(batch, empty, assignments=batch["assignments"])


def test_two_submissions_from_one_reviewer_are_refused():
    batch = _batch()
    subs = _submissions(batch)
    dup = dict(subs[0])
    dup["reviews"] = []
    with pytest.raises(EvaluationError, match="two submissions"):
        build_eval(batch, subs + [dup], assignments=batch["assignments"])


# --------------------------------------------------------------------------
# section 15 — immutability and provenance
# --------------------------------------------------------------------------


def test_the_dataset_records_where_every_part_of_it_came_from(tmp_path):
    dataset = _built(_batch())
    for field in ("dataset_id", "version", "batch_id", "review_schema_version",
                  "split", "source_commit", "batch_source_commit", "source",
                  "reviewers", "reviewer_count", "adjudication_counts",
                  "coverage", "excluded", "stratification", "strata",
                  "holdout_population"):
        assert field in dataset, f"no provenance for {field}"
    assert dataset["immutable"] is True
    assert dataset["source"]["sha256"]["catalogue_en"]


def test_a_published_version_is_never_overwritten(tmp_path):
    """A correction is v2 with a stated diff. An evaluation set that can be
    edited in place means a number quoted last month refers to something that
    no longer exists, and nobody can tell."""
    dataset = _built(_batch())
    first = write_eval(dataset, tmp_path)
    assert (first / "dataset.json").exists()
    with pytest.raises(EvaluationError, match="immutable"):
        write_eval(dataset, tmp_path)
    # The way forward is a new version, not a flag on the old call.
    write_eval({**dataset, "version": 2}, tmp_path)


def test_the_dataset_says_it_is_evaluation_only():
    dataset = _built(_batch())
    assert "EVALUATION ONLY" in dataset["use"]
    assert dataset["split"] == "holdout"


# --------------------------------------------------------------------------
# what does NOT get into the evaluation set, and whether you can tell
# --------------------------------------------------------------------------


def test_an_unadjudicated_disagreement_is_excluded_and_listed():
    """Not a label with a caveat. Not a label."""
    batch = _batch()
    doubled = sorted(batch["assignments"]["secondary"])[0]
    subs = _submissions(batch)
    # The second reviewer of one doubled row disagrees on one question.
    second = batch["assignments"]["secondary"][doubled]
    for sub in subs:
        if sub["reviewer_slot"] != second:
            continue
        for review in sub["reviews"]:
            if review["item_id"] == doubled:
                review["answers"][REVIEW_QUESTIONS[0]] = "problem"
                review["reason_codes"] = ["steps_missing"]

    dataset = build_eval(batch, subs, assignments=batch["assignments"])
    assert doubled not in dataset["rows"]
    excluded = [e for e in dataset["excluded"]
                if e["item_id"] == doubled and e["check"] == REVIEW_QUESTIONS[0]]
    assert excluded and excluded[0]["state"] == "DISAGREE_UNADJUDICATED"
    # And the row is listed as partly settled rather than silently absent.
    assert doubled in {p["item_id"] for p in dataset["excluded_partial_rows"]}


def test_a_dataset_that_lists_only_what_it_contains_cannot_be_audited():
    """So the builder carries `excluded`, `excluded_partial_rows`, `stale` and
    `coverage` alongside `rows`. The rows somebody dropped are exactly the ones
    worth knowing about."""
    dataset = _built(_batch())
    for field in ("excluded", "excluded_partial_rows", "stale", "coverage",
                  "needs_domain_review"):
        assert field in dataset


def test_a_row_where_nothing_settled_leaves_nothing_to_evaluate():
    batch = _batch()
    subs = _submissions(batch)
    for sub in subs:
        for review in sub["reviews"]:
            review["review_status"] = "SKIPPED"
            review["answers"] = {}
            review["reason_codes"] = []
    with pytest.raises(EvaluationError, match="EVALUATION_LABEL_GAP"):
        build_eval(batch, subs, assignments=batch["assignments"])


# --------------------------------------------------------------------------
# sections 17 and 18 — the three numbers, and why they are three
# --------------------------------------------------------------------------


def _bad_if_flagged(batch):
    """A reviewer who confirms every flagged row and clears every other one.

    Gives the baseline perfect precision and perfect recall, which is not
    realistic and is exactly what makes the arithmetic checkable by hand.
    """
    sealed = batch["sealed"]
    return lambda item_id: (REVIEW_QUESTIONS[4],) if sealed.get(item_id) else ()


def test_the_batch_metric_and_the_holdout_estimate_are_different_numbers():
    """If they were equal the batch would be representative, and it is not by
    design. This is the test that catches somebody 'simplifying' the estimator
    away."""
    batch = _batch()
    dataset = _built(batch, bad_for=_bad_if_flagged(batch))
    metrics = evaluate(dataset, batch["sealed"])
    raw = metrics["BATCH_METRIC"]["defect_rate"]
    weighted = metrics["HOLDOUT_ESTIMATE"]["estimate"]
    assert raw is not None and weighted is not None
    assert raw != weighted
    # The batch over-samples the flagged stratum, so the raw figure overstates.
    assert raw > weighted


def test_the_estimator_weights_by_the_holdout_population():
    """Checked against the arithmetic, not against itself."""
    batch = _batch()
    dataset = _built(batch, bad_for=_bad_if_flagged(batch))
    metrics = evaluate(dataset, batch["sealed"])
    strata = dataset["strata"]
    n_flagged = strata["flagged"]["population"]
    n_unflagged = strata["unflagged"]["population"]
    total = n_flagged + n_unflagged
    c = metrics["confusion"]
    expected = (
        (n_flagged / total) * (c["tp"] / (c["tp"] + c["fp"]))
        + (n_unflagged / total) * (c["fn"] / (c["fn"] + c["tn"]))
    )
    assert metrics["HOLDOUT_ESTIMATE"]["estimate"] == pytest.approx(expected)


def test_each_number_says_what_it_is_about():
    batch = _batch()
    metrics = evaluate(_built(batch), batch["sealed"])
    assert "must never be quoted" in metrics["BATCH_METRIC"]["meaning"]
    assert "holdout split" in metrics["HOLDOUT_ESTIMATE"]["meaning"]


def test_the_catalogue_rate_is_absent_on_purpose_and_says_so():
    """Present and null with the assumption written out, so its absence is a
    statement rather than an omission somebody fills in."""
    batch = _batch()
    metrics = evaluate(_built(batch), batch["sealed"])
    assert metrics["CATALOGUE_RATE"]["estimate"] is None
    assert "ASSUMPTION" in metrics["CATALOGUE_RATE"]["reason"]


def test_an_unsampled_stratum_makes_the_estimate_unknown_rather_than_zero():
    """Averaging over the strata that happen to have data silently assumes the
    missing one looks like them."""
    batch = _batch()
    dataset = _built(batch)
    # Pretend the holdout has a large stratum nobody reviewed.
    dataset = {**dataset, "strata": {
        "flagged": dataset["strata"]["flagged"],
        "unflagged": {"population": 10_000, "sampled": 0},
    }}
    dataset["rows"] = {
        k: v for k, v in dataset["rows"].items() if batch["sealed"].get(k)
    }
    metrics = evaluate(dataset, batch["sealed"])
    assert metrics["HOLDOUT_ESTIMATE"]["estimate"] is None
    assert "unknown, not zero" in metrics["HOLDOUT_ESTIMATE"]["reason"]


def test_an_exhaustively_sampled_stratum_contributes_no_sampling_variance():
    """The point of taking every flagged holdout row: there is nothing left
    unobserved in that stratum, so the finite population correction is zero and
    the uncertainty that remains is honestly attributed to the other one."""
    # Sized so the flagged stratum is exhausted, as it is in the real batch
    # (56 of 56). At the default 60 the ratio stops short of the whole
    # stratum, and this property is only claimable when it does not.
    batch = _batch(size=70)
    assert batch["manifest"]["flagged_exhausted"], "the premise does not hold"
    dataset = _built(batch, bad_for=_bad_if_flagged(batch))
    metrics = evaluate(dataset, batch["sealed"])
    strata = {s["name"]: s for s in metrics["HOLDOUT_ESTIMATE"]["strata"]}
    assert strata["flagged"]["sampled"] == strata["flagged"]["population"]
    assert metrics["HOLDOUT_ESTIMATE"]["standard_error"] >= 0
    lo, hi = metrics["HOLDOUT_ESTIMATE"]["ci95"]
    assert 0.0 <= lo <= metrics["HOLDOUT_ESTIMATE"]["estimate"] <= hi <= 1.0


# --------------------------------------------------------------------------
# joining two vocabularies that were designed apart
# --------------------------------------------------------------------------


def test_precision_is_stated_as_exhaustive_and_recall_as_estimated():
    batch = _batch()
    metrics = evaluate(_built(batch, bad_for=_bad_if_flagged(batch)),
                       batch["sealed"])
    assert "EXHAUSTIVE" in metrics["precision_note"]
    assert "estimated" in metrics["recall_note"]


def test_a_rule_family_with_no_matching_question_is_counted_not_dropped():
    """A silent join between two vocabularies is how a precision figure ends up
    comparing a rule to a question it never addressed."""
    batch = _batch()
    metrics = evaluate(_built(batch), batch["sealed"])
    assert "unknown_contraindication_tag" in metrics["unmapped_check_families"]
    assert CHECK_TO_QUESTION["unknown_contraindication_tag"] is None


def test_every_mapped_family_points_at_a_real_question():
    for family, question in CHECK_TO_QUESTION.items():
        assert question is None or question in REVIEW_QUESTIONS, family


def test_per_question_metrics_name_the_rules_they_compared_against():
    batch = _batch()
    metrics = evaluate(_built(batch), batch["sealed"])
    per_q = metrics["per_question"]["content_is_not_duplicated"]
    assert "duplicate_summary" in per_q["rules_mapped"]
    assert set(per_q) >= {"tp", "fp", "fn", "tn", "precision", "recall"}


def test_the_written_metrics_round_trip_as_json(tmp_path):
    batch = _batch()
    metrics = evaluate(_built(batch, bad_for=_bad_if_flagged(batch)),
                       batch["sealed"])
    path = tmp_path / "m.json"
    path.write_text(json.dumps(metrics, ensure_ascii=False), encoding="utf-8")
    assert json.loads(path.read_text(encoding="utf-8")) == metrics
