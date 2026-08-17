# -*- coding: utf-8 -*-
"""CT-1 train-split review: the one invariant, and the refusal to guess.

    python -m pytest scripts/ct1/test_train_review.py -q

``TRAIN REVIEW ROWS ∩ HOLDOUT ROWS = ∅`` is the whole point of this module.
Everything else here exists so that invariant cannot be satisfied vacuously —
by an empty batch, by an empty holdout, or by a test that never asked for a
corpus large enough to have both.
"""
from __future__ import annotations

import pytest

from build_dataset import split_for
from leakage_guard import LeakageError, assert_split_disjoint
from review_batch import BATCH_ID as HOLDOUT_BATCH_ID
from review_batch import REVIEW_QUESTIONS, select as holdout_select
from test_review_batch import _corpus
from train_review import (
    BATCH_ID,
    STRATEGIES,
    TrainReviewError,
    select,
    train_rows,
)


def _both(size: int = 60):
    """The train batch and the holdout batch, from one corpus."""
    en, ru, eq = _corpus()
    return en, ru, eq, select(en, ru, eq, size=size), holdout_select(en, ru, eq, size=size)


# --------------------------------------------------------------------------
# the invariant
# --------------------------------------------------------------------------


def test_the_train_batch_and_the_holdout_share_no_row():
    en, ru, eq, train, holdout = _both()
    train_ids = {i["item_id"] for i in train["items"]}
    holdout_ids = {i["item_id"] for i in holdout["items"]}
    # Non-vacuous: both are populated, so the disjointness below is a claim
    # about two real sets rather than about two empty ones.
    assert len(train_ids) == 60
    assert len(holdout_ids) == 60
    assert train_ids.isdisjoint(holdout_ids)
    assert_split_disjoint(train_ids, holdout_ids)


def test_every_row_it_draws_is_actually_in_the_train_split():
    """Disjointness from one particular holdout batch is weaker than this: a
    row could miss that batch and still be a holdout row."""
    en, ru, eq, train, _ = _both()
    for item in train["items"]:
        assert split_for(item["item_id"]) == "train"


def test_the_row_source_cannot_see_a_holdout_row():
    """`train_rows` is the only place this module decides what it may look at,
    so a later edit cannot let a holdout row in without changing it."""
    en, _, _ = _corpus()
    rows = train_rows(en)
    assert rows, "no train rows, so this proves nothing"
    assert all(split_for(r["id"]) == "train" for r in rows)
    assert len(rows) > len([r for r in en if split_for(r["id"]) == "holdout"]) / 4


def test_the_manifest_records_a_zero_intersection_it_actually_checked():
    en, ru, eq, train, _ = _both()
    assert train["manifest"]["holdout_intersection"] == 0
    assert train["manifest"]["split"] == "train"


def test_a_batch_containing_a_holdout_row_is_refused_at_draw_time():
    """The guard inside `select`, reached by widening what it is allowed to see.

    Not redundant with `leakage_guard`: that one runs at TRAINING time, which
    is after a reviewer has already spent a day on the wrong rows. This one
    runs while the mistake is still free to fix.

    The mutation is the realistic one -- `train_rows` stops filtering, which is
    exactly what a careless edit to it would do.
    """
    import train_review

    en, ru, eq = _corpus()
    real = train_review.train_rows
    train_review.train_rows = lambda rows: rows          # the mutation
    try:
        with pytest.raises(TrainReviewError, match="holdout"):
            select(en, ru, eq, size=60)
    finally:
        train_review.train_rows = real
    # And green again once restored, so the test proves the guard rather than
    # proving the monkeypatch.
    assert select(en, ru, eq, size=60)["manifest"]["holdout_intersection"] == 0


# --------------------------------------------------------------------------
# it will not guess where the challenger should learn
# --------------------------------------------------------------------------


def test_error_targeted_is_refused_while_the_holdout_review_is_open():
    """The strategy the design expects, and the one that cannot be honestly
    approximated: it needs to know where the baseline was measured WRONG."""
    en, ru, eq = _corpus()
    with pytest.raises(TrainReviewError, match="HUMAN_REVIEW_LABELS_REQUIRED"):
        select(en, ru, eq, size=20, strategy="error_targeted")


def test_an_unnamed_strategy_is_refused_rather_than_defaulted():
    en, ru, eq = _corpus()
    with pytest.raises(TrainReviewError, match="not a strategy"):
        select(en, ru, eq, size=20, strategy="whatever_looks_reasonable")


def test_every_strategy_states_what_it_assumes():
    for name, rationale in STRATEGIES.items():
        assert len(rationale) > 80, f"{name} has no stated rationale"
    # The one that encodes the rules' own opinion says so in its own words,
    # rather than leaving a reader to notice.
    assert "feedback loop" in STRATEGIES["mirror_baseline"]


def test_mirroring_the_baseline_is_available_but_labelled():
    """Available deliberately: it may be the right call once somebody argues
    for it. What must not happen is arriving at it by default."""
    en, ru, eq = _corpus()
    batch = select(en, ru, eq, size=20, strategy="mirror_baseline")
    assert batch["manifest"]["strategy"] == "mirror_baseline"
    assert "ENCODES THE RULES" in batch["manifest"]["strategy_rationale"]


# --------------------------------------------------------------------------
# it is a training batch and says so
# --------------------------------------------------------------------------


def test_the_batch_says_it_is_for_training_and_names_what_it_is_not():
    en, ru, eq, train, _ = _both()
    m = train["manifest"]
    assert m["purpose"] == "TRAINING_LABEL_ACQUISITION"
    assert "TRAINING ONLY" in m["use"]
    assert HOLDOUT_BATCH_ID in m["not_for"]
    assert "CT1_HUMAN_EVAL_V1" in m["not_for"]


def test_it_is_not_the_holdout_batch_under_another_name():
    assert BATCH_ID != HOLDOUT_BATCH_ID


def test_the_items_are_blind():
    """Same rule as the holdout batch. A reviewer who can see which rule fired
    produces an agreement rate, and a challenger trained on agreement rates is
    a copy of the rules with extra steps."""
    import json

    en, ru, eq, train, _ = _both()
    blob = json.dumps(train["items"], ensure_ascii=False).lower()
    for forbidden in ("duplicate_", "flag", "label", "check", "score",
                      "baseline", "predict", "suspect"):
        assert forbidden not in blob, f"{forbidden!r} reached the blind batch"


def test_the_questions_are_the_same_ones_the_holdout_batch_asks():
    """Two vocabularies would make the train and evaluation labels
    incomparable, which is how a challenger gets scored against a different
    question from the one it learned."""
    en, ru, eq, train, _ = _both()
    assert train["manifest"]["questions"] == list(REVIEW_QUESTIONS)


def test_selection_is_deterministic_and_order_independent():
    import random

    en, ru, eq = _corpus()
    first = {i["item_id"] for i in select(en, ru, eq, size=40)["items"]}
    again = {i["item_id"] for i in select(en, ru, eq, size=40)["items"]}
    assert first == again
    shuffled = list(en)
    random.Random(4).shuffle(shuffled)
    assert {i["item_id"] for i in select(shuffled, ru, eq, size=40)["items"]} == first
