# -*- coding: utf-8 -*-
"""P0.G3 — fail-closed source & rights registry.

    python scripts/equipment_identity/rights.py
    python -m pytest scripts/equipment_identity/test_rights.py -q

This module builds RIGHTS GOVERNANCE, not legal approvals. Nothing here
declares a real license legally sufficient — it only enforces the mechanics
that make "unknown/unreviewed" fail closed instead of quietly defaulting to
allowed. Every eligibility question below reduces to the same shape: was
this source actually reviewed, and does its recorded rights object say yes
to the SPECIFIC use being asked about. `UNREVIEWED` always fails every
privileged use, with no exception route.

## Fail-closed policy (per the gate contract, restated as code)

    DISPLAY                 legalReviewState==REVIEWED AND displayAllowed
    RECOGNITION_PROCESSING  legalReviewState==REVIEWED AND recognitionProcessingAllowed
                             AND NOT noAiRestriction
    TRAINING                legalReviewState==REVIEWED AND trainingAllowed
                             AND NOT noAiRestriction
    DERIVATIVE               legalReviewState==REVIEWED AND derivativeAllowed
                             AND NOT noAiRestriction
    REDISTRIBUTION           legalReviewState==REVIEWED AND redistributionAllowed

`noAiRestriction=false` on an UNREVIEWED source is never read as permission
— `legalReviewState` gates every decision below before any other field is
even inspected. A SEARCH_DISCOVERY-priority source is refused for every
privileged use regardless of its rights booleans, structurally, not just by
convention — that class exists to find candidate sources, never to BE one.

## Reused, not duplicated

`REQUIRED_RIGHTS_FIELDS`/`SOURCE_CLASSES`/`PRIORITIES` mirror
`core/equipment_identity/p0/source_registry.schema.json` and
`rights_decision.schema.json` field-for-field — this module is the
executable enforcement those schemas can only describe (a static schema
cannot express "trainingCodeCommit must resolve in this repo"-style cross
checks; here, "an UNREVIEWED source is never eligible" is exactly that kind
of check).
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
P0_DIR = REPO / "core" / "equipment_identity" / "p0"
SOURCE_REGISTRY = P0_DIR / "source_registry.json"

SOURCE_CLASSES = frozenset({
    "OFFICIAL_MANUFACTURER", "OFFICIAL_BIM", "WGER", "EXERCISEDB",
    "API_NINJAS", "DISTRIBUTOR", "REFURBISHED_USED", "MARKETPLACE_3D",
    "SEARCH_DISCOVERY", "OTHER",
})

PRIORITIES = frozenset({"P0", "P1", "P2", "ENRICHMENT", "STAGING", "DISCOVERY_ONLY"})

LEGAL_REVIEW_STATES = frozenset({"UNREVIEWED", "REVIEWED", "BLOCKED"})

#: Which priorities a given sourceClass may declare — priority is not a free
#: per-record choice; it is determined by what kind of source this is.
#: SEARCH_DISCOVERY's single legal priority is the structural half of "search
#: discovery can never be a training/display source": it is impossible for a
#: SEARCH_DISCOVERY record to even pass registry validation with any other
#: priority, let alone reach an eligibility check.
CANONICAL_PRIORITIES_BY_SOURCE_CLASS: dict[str, frozenset[str]] = {
    "OFFICIAL_MANUFACTURER": frozenset({"P0", "P1"}),
    "OFFICIAL_BIM": frozenset({"P0", "P1"}),
    "WGER": frozenset({"ENRICHMENT"}),
    "EXERCISEDB": frozenset({"STAGING"}),
    "API_NINJAS": frozenset({"STAGING"}),
    "DISTRIBUTOR": frozenset({"P1", "P2"}),
    "REFURBISHED_USED": frozenset({"P2"}),
    "MARKETPLACE_3D": frozenset({"STAGING"}),
    "SEARCH_DISCOVERY": frozenset({"DISCOVERY_ONLY"}),
    "OTHER": frozenset({"STAGING", "ENRICHMENT", "P2"}),
}

REQUIRED_RIGHTS_FIELDS: tuple[str, ...] = (
    "legalReviewState", "commercialAllowed", "displayAllowed",
    "recognitionProcessingAllowed", "trainingAllowed", "derivativeAllowed",
    "redistributionAllowed", "attributionRequired", "shareAlike",
    "noAiRestriction", "termsCaptured",
)

REQUIRED_RIGHTS_BOOLEAN_FIELDS: tuple[str, ...] = tuple(
    f for f in REQUIRED_RIGHTS_FIELDS if f != "legalReviewState"
)

#: The subset of REQUIRED_RIGHTS_BOOLEAN_FIELDS that actually GRANT a use —
#: what "zero fake permissions on an UNREVIEWED source" means. Deliberately
#: excludes `attributionRequired`/`shareAlike` (obligations, not grants — true
#: only makes a use MORE restrictive) and `termsCaptured`/`noAiRestriction`
#: (factual/restriction metadata, not permissions): terms text can honestly be
#: captured before anyone reviews it, and a No-AI restriction is the opposite
#: of a grant.
PERMISSION_FIELDS: tuple[str, ...] = (
    "commercialAllowed", "displayAllowed", "recognitionProcessingAllowed",
    "trainingAllowed", "derivativeAllowed", "redistributionAllowed",
)

REQUIRED_SOURCE_FIELDS: tuple[str, ...] = (
    "sourceId", "providerName", "sourceClass", "priority",
    "canonicalUrl", "retrievedAt", "termsUrl", "rights",
)

_SOURCE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class RightsValidationError(RuntimeError):
    """A registry record that cannot honestly support the rights claim it
    makes — either malformed, or missing the evidence a REVIEWED state
    requires."""


def _looks_like_iso_datetime(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def validate_rights(rights: dict[str, Any], *, context: str) -> None:
    missing = [f for f in REQUIRED_RIGHTS_FIELDS if f not in rights]
    if missing:
        raise RightsValidationError(f"{context}: rights object missing {missing}")

    state = rights["legalReviewState"]
    if state not in LEGAL_REVIEW_STATES:
        raise RightsValidationError(
            f"{context}: legalReviewState {state!r} is not one of {sorted(LEGAL_REVIEW_STATES)}"
        )

    for field in REQUIRED_RIGHTS_BOOLEAN_FIELDS:
        if not isinstance(rights[field], bool):
            raise RightsValidationError(
                f"{context}: rights.{field} must be a boolean, got {rights[field]!r}"
            )

    if state in ("UNREVIEWED", "BLOCKED"):
        granted = [f for f in PERMISSION_FIELDS if rights[f] is True]
        if granted:
            raise RightsValidationError(
                f"{context}: legalReviewState={state} but {granted} is/are "
                f"already true — only a REVIEWED source may carry a granted "
                "permission; zero fake permissions is a P0.G3 close condition"
            )

    if state in ("REVIEWED", "BLOCKED") and not rights.get("reviewedAt"):
        raise RightsValidationError(
            f"{context}: legalReviewState={state} requires reviewedAt to be set"
        )
    if state == "REVIEWED" and rights["termsCaptured"] is not True:
        raise RightsValidationError(
            f"{context}: legalReviewState=REVIEWED requires termsCaptured=true — "
            "REVIEWED means a human reviewed actual captured terms, not a "
            "reputation- or category-based guess"
        )
    if rights.get("reviewedAt") is not None and not _looks_like_iso_datetime(rights["reviewedAt"]):
        raise RightsValidationError(f"{context}: reviewedAt is not a valid ISO-8601 timestamp")
    if rights.get("recheckAt") is not None and not _looks_like_iso_datetime(rights["recheckAt"]):
        raise RightsValidationError(f"{context}: recheckAt is not a valid ISO-8601 timestamp")

    if rights["termsCaptured"] and "termsSnapshotSha256" in rights:
        snapshot = rights["termsSnapshotSha256"]
        if not (isinstance(snapshot, str) and _SHA256_RE.match(snapshot)):
            raise RightsValidationError(
                f"{context}: termsSnapshotSha256 {snapshot!r} is not a 64-hex-character sha256"
            )
    if "termsSnapshotSha256" in rights and not rights["termsCaptured"]:
        raise RightsValidationError(
            f"{context}: termsSnapshotSha256 is set but termsCaptured=false — a "
            "captured snapshot without the flag admitting it is captured is "
            "exactly the kind of drift this registry exists to prevent"
        )


def validate_source_record(record: dict[str, Any]) -> None:
    missing = [f for f in REQUIRED_SOURCE_FIELDS if f not in record]
    if missing:
        raise RightsValidationError(f"source record missing {missing}")

    source_id = record["sourceId"]
    if not (isinstance(source_id, str) and _SOURCE_ID_RE.match(source_id)):
        raise RightsValidationError(f"sourceId {source_id!r} does not match {_SOURCE_ID_RE.pattern}")

    context = f"source {source_id!r}"

    if not isinstance(record["providerName"], str) or not record["providerName"].strip():
        raise RightsValidationError(f"{context}: providerName must be a non-empty string")

    source_class = record["sourceClass"]
    if source_class not in SOURCE_CLASSES:
        raise RightsValidationError(f"{context}: sourceClass {source_class!r} not in {sorted(SOURCE_CLASSES)}")

    priority = record["priority"]
    if priority not in PRIORITIES:
        raise RightsValidationError(f"{context}: priority {priority!r} not in {sorted(PRIORITIES)}")
    allowed_priorities = CANONICAL_PRIORITIES_BY_SOURCE_CLASS[source_class]
    if priority not in allowed_priorities:
        raise RightsValidationError(
            f"{context}: sourceClass={source_class} may only declare priority "
            f"in {sorted(allowed_priorities)}, got {priority!r} — priority is "
            "determined by source class, not freely chosen per record"
        )

    if not isinstance(record["canonicalUrl"], str) or not record["canonicalUrl"].strip():
        raise RightsValidationError(f"{context}: canonicalUrl must be a non-empty string")
    if not _looks_like_iso_datetime(record["retrievedAt"]):
        raise RightsValidationError(f"{context}: retrievedAt is not a valid ISO-8601 timestamp")
    if record["termsUrl"] is not None and not isinstance(record["termsUrl"], str):
        raise RightsValidationError(f"{context}: termsUrl must be a string or null")

    rights = record["rights"]
    if not isinstance(rights, dict):
        raise RightsValidationError(f"{context}: rights must be an object, got {rights!r}")
    validate_rights(rights, context=context)


def load_registry(path: Path = SOURCE_REGISTRY) -> list[dict[str, Any]]:
    """Load and fully validate every entry. Raises on the first invalid
    record rather than returning a partially-trustworthy list.

    Also enforces sourceId uniqueness across the whole registry (reviewer-
    found gap, P1.G2 review, 2026-08-22): neither this function nor the
    JSON Schema previously checked for a duplicate sourceId, so a future
    copy-paste record (e.g. cloning an existing entry and only editing
    canonicalUrl/decisionBasis, leaving sourceId stale) would pass every
    per-record check and then silently shadow the original in any consumer
    that builds a {sourceId: record} map -- exactly the kind of silent
    provenance loss this registry exists to prevent."""
    data = json.loads(path.read_text(encoding="utf-8"))
    sources = data.get("sources", [])
    if not sources:
        raise RightsValidationError(f"{path}: registry has no sources")
    seen_ids: set[str] = set()
    for record in sources:
        validate_source_record(record)
        source_id = record["sourceId"]
        if source_id in seen_ids:
            raise RightsValidationError(f"{path}: duplicate sourceId {source_id!r}")
        seen_ids.add(source_id)
    return sources


# ---------------------------------------------------------------------------
# Fail-closed eligibility. Every function takes the WHOLE source record (not
# just `rights`) so a SEARCH_DISCOVERY-priority record can be refused
# structurally, in addition to whatever its rights booleans happen to say —
# defence in depth against a future bug that sets a permission boolean true
# on a class that must never carry one.
# ---------------------------------------------------------------------------

def _reviewed(record: dict[str, Any]) -> bool:
    return record["rights"]["legalReviewState"] == "REVIEWED"


def _not_discovery_only(record: dict[str, Any]) -> bool:
    return record["priority"] != "DISCOVERY_ONLY"


def _commercially_allowed(record: dict[str, Any]) -> bool:
    # SPTR is a commercial product -- every privileged use happens in that
    # context, so a source that is REVIEWED+*Allowed but explicitly not
    # cleared for commercial use must still be refused for every use, not
    # just silently accepted because no single use-specific flag mentions
    # "commercial." See P0_G3_RIGHTS_GOVERNANCE.md's review record.
    return record["rights"]["commercialAllowed"]


def eligible_for_display(record: dict[str, Any]) -> bool:
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _commercially_allowed(record)
        and record["rights"]["displayAllowed"]
    )


def eligible_for_recognition_processing(record: dict[str, Any]) -> bool:
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _commercially_allowed(record)
        and rights["recognitionProcessingAllowed"]
        and not rights["noAiRestriction"]
    )


def eligible_for_training(record: dict[str, Any]) -> bool:
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _commercially_allowed(record)
        and rights["trainingAllowed"]
        and not rights["noAiRestriction"]
    )


def eligible_for_derivative(record: dict[str, Any]) -> bool:
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _commercially_allowed(record)
        and rights["derivativeAllowed"]
        and not rights["noAiRestriction"]
    )


def eligible_for_redistribution(record: dict[str, Any]) -> bool:
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _commercially_allowed(record)
        and record["rights"]["redistributionAllowed"]
    )


ELIGIBILITY_BY_USE: dict[str, Any] = {
    "DISPLAY": eligible_for_display,
    "RECOGNITION_PROCESSING": eligible_for_recognition_processing,
    "TRAINING": eligible_for_training,
    "DERIVATIVE": eligible_for_derivative,
    "REDISTRIBUTION": eligible_for_redistribution,
}


def eligible_for(record: dict[str, Any], use: str) -> bool:
    """P1.G1 §6.8 hardening (forward note accepted at P0.G3 close): every
    caller reaches the individual `eligible_for_*` functions through this
    one chokepoint, so validating the record here — before any eligibility
    field is even read — means a malformed/inconsistent record can never
    silently produce a `True` (or a wrong `False`) by having its fields
    misread. Previously each `eligible_for_*` trusted its `record` argument
    structurally; a record that skipped `validate_source_record` (e.g. a
    hand-built dict in a future caller, not one of P0's registry-loaded
    records) could raise a bare `KeyError`/`TypeError` instead of the
    typed `RightsValidationError` every other rights failure raises, or —
    worse — could have a booleanish-but-wrong value read as truthy."""
    validate_source_record(record)
    if use not in ELIGIBILITY_BY_USE:
        raise RightsValidationError(f"unknown use {use!r}, expected one of {sorted(ELIGIBILITY_BY_USE)}")
    return ELIGIBILITY_BY_USE[use](record)


def main() -> int:
    sources = load_registry()
    print(f"{len(sources)} source(s) validated")
    for record in sources:
        uses = [u for u in ELIGIBILITY_BY_USE if eligible_for(record, u)]
        print(f"  {record['sourceId']:40} {record['rights']['legalReviewState']:10} eligible_for={uses or 'NONE'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
