# -*- coding: utf-8 -*-
"""CT-1 label ontology — what a content-QA label is allowed to claim.

    python -m pytest scripts/ct1/test_ct1.py -q

The whole point of writing this before any model exists is that the mistake it
prevents is not detectable afterwards. A pipeline that trains on its own
predictions still reports excellent metrics; it has simply learned to agree
with itself, and the only evidence of that is the provenance it did not keep.

So provenance is not metadata here. It is the primary key of a label, and the
rules below are enforced in code rather than described in a document.

## The six kinds

They are ordered by authority, and the order is deliberately not a scale of
confidence -- an OBSERVATION is the most certain thing in this file and the
least authoritative. What increases down the list is who is entitled to be
wrong.

``OBSERVATION``
    A measured property of the catalogue row. "This row has no
    ``contraindications`` key." Not a judgement, cannot be incorrect, and needs
    no reviewer. Recomputable from the source at any time.

``AUTO_HEURISTIC_FLAG``
    A deterministic rule fired. "Two rows share a title." The rule is exact
    about what it matched and says nothing about whether that matters --
    duplicate titles can be legitimate.

``MODEL_PREDICTION``
    A model's opinion. Never a target. Never evidence.

``HUMAN_REVIEWED_QA_LABEL``
    A person looked at the item and recorded a verdict about CONTENT quality:
    the steps contradict the title, the equipment is wrong, the translation is
    missing. The first kind that may be trained on.

``DOMAIN_REVIEWED_LABEL``
    A qualified strength/movement professional's verdict. Content authority,
    still not clinical authority.

``CLINICALLY_VALIDATED_LABEL``
    A named clinician's verdict, under the governance in
    ``GOVERNANCE_OWNERSHIP.md``. **Nothing in this repository can produce one.**
    It exists in the enum so that the absence is representable and so that no
    other label can be quietly promoted into meaning it. See D1, H3, and
    ``core/review/CLINICAL_VALIDATION_HANDOFF.md``.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping


class LabelSource(str, Enum):
    OBSERVATION = "OBSERVATION"
    AUTO_HEURISTIC_FLAG = "AUTO_HEURISTIC_FLAG"
    MODEL_PREDICTION = "MODEL_PREDICTION"
    HUMAN_REVIEWED_QA_LABEL = "HUMAN_REVIEWED_QA_LABEL"
    DOMAIN_REVIEWED_LABEL = "DOMAIN_REVIEWED_LABEL"
    CLINICALLY_VALIDATED_LABEL = "CLINICALLY_VALIDATED_LABEL"


#: Sources a supervised target may be drawn from.
#:
#: The exclusion of MODEL_PREDICTION is the anti-feedback-loop rule and is the
#: reason this module exists. AUTO_HEURISTIC_FLAG is excluded for a quieter but
#: equally real reason: training on the rules would produce a model that
#: reproduces the rules, at a cost, with less precision, and the deterministic
#: baseline already runs them exactly. A challenger has to beat the rules, and
#: it cannot do that by imitating them.
TRAINABLE_SOURCES = frozenset({
    LabelSource.HUMAN_REVIEWED_QA_LABEL,
    LabelSource.DOMAIN_REVIEWED_LABEL,
    LabelSource.CLINICALLY_VALIDATED_LABEL,
})

#: Sources this repository is capable of producing.
#:
#: Anything outside it must arrive from a named external reviewer with a
#: recorded identity, which is what makes the CLINICALLY_VALIDATED case
#: unreachable rather than merely discouraged.
PRODUCIBLE_HERE = frozenset({
    LabelSource.OBSERVATION,
    LabelSource.AUTO_HEURISTIC_FLAG,
    LabelSource.MODEL_PREDICTION,
})


class LabelContractError(ValueError):
    """A label that would break the ontology, refused at construction."""


_REVIEWER_RE = re.compile(r"^[a-z0-9](?:[a-z0-9_.-]{1,62})$")


@dataclass(frozen=True)
class Label:
    """One claim about one catalogue row.

    Frozen, because a label whose source can be reassigned after the fact is
    exactly the hole the ontology exists to close.
    """

    item_id: str
    check: str
    source: LabelSource
    value: Any = True
    #: Who produced it. Required for every reviewed source and forbidden for
    #: the machine ones -- an OBSERVATION with a human's name on it invites
    #: someone to read it as a review.
    reviewer: str | None = None
    evidence: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.item_id:
            raise LabelContractError("item_id is required")
        if not self.check:
            raise LabelContractError("check is required")
        reviewed = self.source in TRAINABLE_SOURCES
        if reviewed and not self.reviewer:
            raise LabelContractError(
                f"{self.source.value} requires a reviewer identity; a reviewed "
                "label with nobody attached is an unreviewed label wearing a "
                "better name"
            )
        if not reviewed and self.reviewer:
            raise LabelContractError(
                f"{self.source.value} must not carry a reviewer; naming a "
                "person beside a machine-produced label is how one gets read "
                "as the other"
            )
        if self.reviewer and not _REVIEWER_RE.match(self.reviewer):
            raise LabelContractError(f"unusable reviewer id: {self.reviewer!r}")
        if self.source is LabelSource.CLINICALLY_VALIDATED_LABEL:
            raise LabelContractError(
                "no process in this repository can produce a clinically "
                "validated label. D1 requires external validation and H3 is on "
                "hold; see core/review/CLINICAL_VALIDATION_HANDOFF.md"
            )

    def to_json(self) -> dict[str, Any]:
        out: dict[str, Any] = {
            "item_id": self.item_id,
            "check": self.check,
            "source": self.source.value,
            "value": self.value,
        }
        if self.reviewer:
            out["reviewer"] = self.reviewer
        if self.evidence:
            out["evidence"] = dict(self.evidence)
        return out


def may_train_on(source: LabelSource) -> bool:
    """Whether a supervised target may be drawn from `source`."""
    return source in TRAINABLE_SOURCES


def assert_no_self_training(labels: list[Label]) -> None:
    """Refuses a training set that contains any machine-produced label.

    The check a pipeline skips because it is obvious. It is called by the
    dataset builder on the training split, so skipping it requires deleting a
    line rather than forgetting one.
    """
    bad = sorted({l.source.value for l in labels if not may_train_on(l.source)})
    if bad:
        raise LabelContractError(
            "training targets may not come from " + ", ".join(bad) + ". A "
            "predicted class cannot become its own training label, and a "
            "heuristic's output teaches a model only to be a worse copy of the "
            "heuristic."
        )
