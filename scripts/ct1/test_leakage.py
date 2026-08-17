# -*- coding: utf-8 -*-
"""CT-1 leakage guards, proved by breaking what they guard.

    python -m pytest scripts/ct1/test_leakage.py -q

Sections 43 and 44. Both guards are trivially satisfied today, which is exactly
the problem with them: a guard nobody has ever seen fail is a guard nobody knows
is connected. So each is mutation-tested — the subject is broken in the specific
way the guard exists to catch, and the guard must fail.

A test that only asserts the green case would pass against `def guard(*a): pass`.
"""
from __future__ import annotations

import dataclasses

import pytest

from build_dataset import split_for
from label_contract import (
    Label,
    LabelContractError,
    LabelSource,
    TRAINABLE_SOURCES,
)
from leakage_guard import (
    UNTRAINABLE_SOURCES,
    LeakageError,
    assert_split_disjoint,
    assert_trainable,
    report,
)
from test_review_batch import _corpus


def _splits():
    en, _, _ = _corpus(400)
    train = [r["id"] for r in en if split_for(r["id"]) == "train"]
    holdout = [r["id"] for r in en if split_for(r["id"]) == "holdout"]
    return train, holdout


def _label(item_id, *, source=LabelSource.HUMAN_REVIEWED_QA_LABEL,
           reviewer="qa.sam", split="train", check="content_is_complete"):
    return Label(
        item_id=item_id, check=check, source=source, value=True,
        reviewer=reviewer, evidence={"split": split},
    )


# --------------------------------------------------------------------------
# section 43 — the splits are disjoint
# --------------------------------------------------------------------------


def test_the_real_splits_are_disjoint_and_both_populated():
    train, holdout = _splits()
    assert train and holdout
    assert_split_disjoint(train, holdout)


def test_moving_one_holdout_row_into_training_is_caught():
    """The mutation. One row, out of nearly four hundred, in both places."""
    train, holdout = _splits()
    assert_split_disjoint(train, holdout)          # green before
    with pytest.raises(LeakageError, match="BOTH splits"):
        assert_split_disjoint(train + [holdout[0]], holdout)


def test_an_empty_training_split_is_not_treated_as_disjoint():
    """Two empty sets are disjoint, so a guard that checks only the
    intersection passes loudest exactly when the split has stopped working."""
    _, holdout = _splits()
    with pytest.raises(LeakageError, match="training split is empty"):
        assert_split_disjoint([], holdout)


def test_an_empty_holdout_split_is_refused():
    train, _ = _splits()
    with pytest.raises(LeakageError, match="holdout split is empty"):
        assert_split_disjoint(train, [])


def test_the_guard_names_the_rows_it_found():
    """A guard that says only "leakage detected" sends somebody to read the
    whole corpus."""
    train, holdout = _splits()
    with pytest.raises(LeakageError) as exc:
        assert_split_disjoint(train + holdout[:3], holdout)
    assert holdout[0] in str(exc.value) or holdout[1] in str(exc.value)


# --------------------------------------------------------------------------
# section 44 — where a training label came from
# --------------------------------------------------------------------------


def test_a_human_label_on_a_training_row_is_trainable():
    train, holdout = _splits()
    assert_trainable([_label(train[0])], holdout_ids=holdout)


@pytest.mark.parametrize("source", sorted(UNTRAINABLE_SOURCES, key=lambda s: s.name))
def test_every_untrainable_source_is_refused(source):
    """Parametrised over the enum rather than over a hand-written list, so a
    source added later is covered without anybody remembering to add it."""
    train, holdout = _splits()
    label = dataclasses.replace(
        _label(train[0]), source=source,
        reviewer=None if source not in TRAINABLE_SOURCES else "qa.sam",
    )
    with pytest.raises(LeakageError, match="may not be a training target"):
        assert_trainable([label], holdout_ids=holdout)


def test_the_untrainable_set_is_exactly_the_complement_of_the_trainable_one():
    """If the two files ever disagree, one of them is wrong and this says so
    rather than letting the guard quietly enforce a stale list."""
    assert UNTRAINABLE_SOURCES == frozenset(set(LabelSource) - set(TRAINABLE_SOURCES))
    assert UNTRAINABLE_SOURCES & frozenset(TRAINABLE_SOURCES) == frozenset()


def test_a_human_label_on_a_holdout_row_is_refused_by_its_row():
    """The dangerous one. It is a perfectly valid human label, it passes every
    check in `label_contract`, and training on it destroys the only evaluation
    this project has."""
    train, holdout = _splits()
    label = _label(holdout[0], split="train")   # evidence lies; the id does not
    with pytest.raises(LeakageError, match="HOLDOUT row"):
        assert_trainable([label], holdout_ids=holdout)


def test_a_human_label_carrying_split_holdout_is_refused_by_its_evidence():
    """The same refusal without being handed the holdout list -- which is the
    case that matters, because a guard needing a second file is a guard
    somebody will call without it."""
    train, _ = _splits()
    label = _label(train[0], split="holdout")
    with pytest.raises(LeakageError, match="HOLDOUT row"):
        assert_trainable([label])


def test_the_review_batch_labels_are_exactly_what_this_refuses():
    """Section 5, end to end: a label as `review_import` actually produces it.

    Not a hand-built stand-in -- the guard has to refuse the object the
    importer emits, including its evidence dict, or it refuses a shape nothing
    creates.
    """
    label = Label(
        item_id="row0007", check="content_is_complete",
        source=LabelSource.HUMAN_REVIEWED_QA_LABEL, value=False,
        reviewer="qa.jordan",
        evidence={
            "batch_id": "CT1_REVIEW_BATCH_002",
            "split": "holdout",
            "review_schema_version": 2,
            "source_content_version": "0" * 32,
            "reason_codes": ["steps_truncated"],
        },
    )
    with pytest.raises(LeakageError, match="section 5|Section 5"):
        assert_trainable([label])


def test_a_reviewed_label_with_no_reviewer_cannot_be_built_at_all():
    """So `assert_trainable` deliberately does not check for it.

    A guard branch that cannot fire is a guard nobody knows is disconnected —
    section 42. The enforcement is in `Label.__post_init__`, which is where
    this asserts it, and the guard's docstring says why it is absent there.
    """
    train, _ = _splits()
    with pytest.raises(LabelContractError, match="requires a reviewer"):
        dataclasses.replace(_label(train[0]), reviewer="")


def test_training_on_nothing_is_refused():
    """Otherwise "the leakage guard passed" is a claim about an empty set."""
    _, holdout = _splits()
    with pytest.raises(LeakageError, match="no training labels"):
        assert_trainable([], holdout_ids=holdout)


# --------------------------------------------------------------------------
# the report a model card would carry
# --------------------------------------------------------------------------


def test_the_report_records_counts_and_not_only_a_verdict():
    train, holdout = _splits()
    out = report(train, holdout, [_label(train[0]), _label(train[1])])
    assert out["verdict"] == "NO_LEAKAGE_DETECTED"
    assert out["train_rows"] == len(set(train))
    assert out["holdout_rows"] == len(set(holdout))
    assert out["training_labels"] == 2
    assert out["label_sources"] == ["HUMAN_REVIEWED_QA_LABEL"]


def test_the_report_states_what_it_does_not_prove():
    """A structural guard that reads as a clean bill of health for leakage in
    general is worse than none: it is the sentence somebody quotes."""
    train, holdout = _splits()
    out = report(train, holdout, [_label(train[0])])
    for phrase in ("Structural only", "threshold tuned", "derived from the whole"):
        assert phrase in out["scope"]


def test_the_report_refuses_rather_than_reporting_a_failed_check():
    train, holdout = _splits()
    with pytest.raises(LeakageError):
        report(train + [holdout[0]], holdout, [_label(train[0])])
