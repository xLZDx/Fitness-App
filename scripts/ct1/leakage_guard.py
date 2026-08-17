# -*- coding: utf-8 -*-
"""CT-1 — the two refusals that stand between a real metric and a fake one.

    python -m pytest scripts/ct1/test_leakage.py -q

Section 43 and 44 of the brief. Both are structural: they are checks a training
run must pass before it starts, not properties somebody asserts in a document
and nobody re-checks after the fourth refactor.

## 1. The holdout is disjoint from the training set

Trivially true the day the splitter is written, and the way it stops being true
is never a deliberate change. It is a new corpus, a merged file, a
deduplication pass keyed on something else, a helper that "fixes" an id. The
symptom is a challenger that beats the champion and cannot be reproduced.

## 2. A training label came from a person

``label_contract`` already refuses to train on ``MODEL_PREDICTION``,
``AUTO_HEURISTIC_FLAG`` and ``OBSERVATION``. This adds the case that contract
cannot see: a label whose SOURCE is a human review but whose ROW is in the
holdout. It is a perfectly valid human label and training on it destroys the
only evaluation this project has, which makes it the most dangerous label in
the corpus — it passes every check that exists to catch a bad one.

Section 5 of the brief, on the 180 reviewed rows: THEIR LABELS MUST NEVER BE
USED TO TRAIN THE CHALLENGER. That is what this file is.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from label_contract import Label, LabelSource, TRAINABLE_SOURCES  # noqa: E402


class LeakageError(AssertionError):
    """A training input that would make the evaluation meaningless."""


def assert_split_disjoint(
    train_ids: Iterable[str], holdout_ids: Iterable[str]
) -> None:
    """Both non-empty, and sharing nothing.

    Emptiness is checked because it is the failure mode a disjointness test
    invites: two empty sets are disjoint, so a guard that only checks the
    intersection passes loudest exactly when the split has stopped working at
    all.
    """
    train, holdout = set(train_ids), set(holdout_ids)
    if not train:
        raise LeakageError(
            "the training split is empty. An empty set is disjoint from "
            "everything, so this guard would pass while the split is broken"
        )
    if not holdout:
        raise LeakageError(
            "the holdout split is empty. There is nothing left to evaluate on, "
            "and any metric reported would be measuring the training set"
        )
    overlap = sorted(train & holdout)
    if overlap:
        raise LeakageError(
            f"{len(overlap)} row(s) are in BOTH splits, e.g. {overlap[:5]}. "
            "A model evaluated on rows it trained on reports its memory, not "
            "its generalisation"
        )


#: Sources that may never be a training target, named here as well as in
#: ``label_contract`` so that this guard states its own contract. If the two
#: ever disagree, ``test_leakage`` fails: the set below is asserted to be
#: exactly the complement of ``TRAINABLE_SOURCES``.
UNTRAINABLE_SOURCES = frozenset(set(LabelSource) - set(TRAINABLE_SOURCES))


def assert_trainable(labels: Iterable[Label], *, holdout_ids: Iterable[str] = ()) -> None:
    """Refuse a training set containing anything that must not be trained on.

    Two refusals, deliberately not merged:

    * a machine-produced source — the self-training loop;
    * a human label on a holdout row — the evaluation-destroying one.

    There is deliberately no third check for "a reviewed label with no named
    reviewer". ``Label.__post_init__`` already makes that object impossible to
    construct, so a check here could never fire, and a guard that cannot fail
    is a guard nobody knows is disconnected. ``test_leakage`` asserts the
    contract holds instead, which is where the enforcement actually is.
    """
    holdout = set(holdout_ids)
    labels = list(labels)
    if not labels:
        raise LeakageError(
            "no training labels. Reporting a model trained on nothing as "
            "trained is the failure this guard exists for"
        )
    for l in labels:
        if l.source in UNTRAINABLE_SOURCES:
            raise LeakageError(
                f"{l.item_id}.{l.check}: source {l.source.name} may not be a "
                "training target. Training on machine output makes the next "
                "model a copy of the last one's mistakes"
            )
        split = (l.evidence or {}).get("split")
        if l.item_id in holdout or split == "holdout":
            raise LeakageError(
                f"{l.item_id}.{l.check}: a {l.source.name} on a HOLDOUT row. "
                "It is a valid label and training on it destroys the only "
                "evaluation this project has. Section 5: the reviewed holdout "
                "labels must never be used to train the challenger"
            )


def report(
    train_ids: Iterable[str], holdout_ids: Iterable[str], labels: Iterable[Label]
) -> dict:
    """Run both guards and return what was checked, for the model card.

    Returns rather than prints, and records the COUNTS as well as the verdict:
    "leakage guard passed" over an empty corpus is the claim this module is
    least willing to let anybody make.
    """
    train, holdout, labels = set(train_ids), set(holdout_ids), list(labels)
    assert_split_disjoint(train, holdout)
    assert_trainable(labels, holdout_ids=holdout)
    return {
        "train_rows": len(train),
        "holdout_rows": len(holdout),
        "intersection": 0,
        "training_labels": len(labels),
        "label_sources": sorted({l.source.name for l in labels}),
        "verdict": "NO_LEAKAGE_DETECTED",
        "scope": (
            "Structural only. This proves the splits are disjoint and that no "
            "label offered for training is machine-produced or holdout-origin. "
            "It does NOT prove the absence of subtler leakage: a feature "
            "derived from the whole corpus, a threshold tuned against holdout "
            "results, or a rule written after looking at holdout rows."
        ),
    }
