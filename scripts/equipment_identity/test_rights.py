# -*- coding: utf-8 -*-
"""P0.G3 tests for scripts/equipment_identity/rights.py.

    python -m pytest scripts/equipment_identity/test_rights.py -q
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rights  # noqa: E402


def _base_rights(**overrides) -> dict:
    base = {
        "legalReviewState": "UNREVIEWED",
        "commercialAllowed": False,
        "displayAllowed": False,
        "recognitionProcessingAllowed": False,
        "trainingAllowed": False,
        "derivativeAllowed": False,
        "redistributionAllowed": False,
        "attributionRequired": False,
        "shareAlike": False,
        "noAiRestriction": True,
        "termsCaptured": False,
    }
    base.update(overrides)
    return base


def _base_record(**overrides) -> dict:
    base = {
        "sourceId": "test_source",
        "providerName": "Test Provider",
        "sourceClass": "OFFICIAL_MANUFACTURER",
        "priority": "P0",
        "canonicalUrl": "https://example.com/",
        "retrievedAt": "2026-08-22T00:00:00Z",
        "termsUrl": None,
        "rights": _base_rights(),
    }
    base.update(overrides)
    return base


def _reviewed_permissive_record(**rights_overrides) -> dict:
    defaults = {
        "legalReviewState": "REVIEWED",
        "reviewedAt": "2026-08-22T00:00:00Z",
        "noAiRestriction": False,
        "termsCaptured": True,
        "commercialAllowed": True,
    }
    defaults.update(rights_overrides)
    return _base_record(rights=_base_rights(**defaults))


# --- registry-level -----------------------------------------------------

def test_every_registry_record_validates_schema():
    sources = rights.load_registry()
    assert len(sources) >= 1
    for record in sources:
        rights.validate_source_record(record)  # must not raise


def test_every_record_has_rights_state():
    sources = rights.load_registry()
    for record in sources:
        assert "rights" in record
        assert record["rights"]["legalReviewState"] in rights.LEGAL_REVIEW_STATES


def test_malformed_timestamp_fails_validation():
    record = _base_record(retrievedAt="not-a-date")
    with pytest.raises(rights.RightsValidationError, match="retrievedAt"):
        rights.validate_source_record(record)


def test_malformed_hash_fails_validation():
    r = _base_rights(termsCaptured=True, termsSnapshotSha256="not-a-hash")
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsSnapshotSha256"):
        rights.validate_source_record(record)


def test_missing_rights_object_fails_validation():
    record = _base_record()
    del record["rights"]
    with pytest.raises(rights.RightsValidationError, match="rights"):
        rights.validate_source_record(record)


def test_source_class_priority_is_deterministic():
    # A record may only declare a priority its sourceClass allows -- not any
    # of the six values freely.
    record = _base_record(sourceClass="WGER", priority="P0")
    with pytest.raises(rights.RightsValidationError, match="priority"):
        rights.validate_source_record(record)


def test_search_discovery_can_never_declare_a_non_discovery_priority():
    record = _base_record(sourceClass="SEARCH_DISCOVERY", priority="P0")
    with pytest.raises(rights.RightsValidationError, match="priority"):
        rights.validate_source_record(record)


# --- fail-closed eligibility ---------------------------------------------

def test_unreviewed_plus_any_requested_privileged_use_denies():
    record = _base_record(rights=_base_rights(
        legalReviewState="UNREVIEWED",
        # Even if every boolean were somehow true, UNREVIEWED must still deny.
    ))
    for use in rights.ELIGIBILITY_BY_USE:
        assert rights.eligible_for(record, use) is False


def test_unreviewed_record_cannot_carry_a_granted_permission():
    # Structural: validate_source_record refuses UNREVIEWED+True, so the
    # "even if every boolean were true" scenario above can't occur for a
    # record that passes validation in the first place.
    r = _base_rights(legalReviewState="UNREVIEWED", displayAllowed=True)
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="UNREVIEWED"):
        rights.validate_source_record(record)


def test_reviewed_and_allowed_grants_the_specific_use_only():
    record = _reviewed_permissive_record(displayAllowed=True)
    assert rights.eligible_for(record, "DISPLAY") is True
    assert rights.eligible_for(record, "TRAINING") is False
    assert rights.eligible_for(record, "RECOGNITION_PROCESSING") is False
    assert rights.eligible_for(record, "DERIVATIVE") is False
    assert rights.eligible_for(record, "REDISTRIBUTION") is False


def test_no_ai_restriction_blocks_recognition_training_derivative():
    record = _reviewed_permissive_record(
        recognitionProcessingAllowed=True, trainingAllowed=True,
        derivativeAllowed=True, redistributionAllowed=True, displayAllowed=True,
        noAiRestriction=True,
    )
    assert rights.eligible_for(record, "RECOGNITION_PROCESSING") is False
    assert rights.eligible_for(record, "TRAINING") is False
    assert rights.eligible_for(record, "DERIVATIVE") is False
    # noAiRestriction does not touch DISPLAY/REDISTRIBUTION -- those are not
    # AI processing uses.
    assert rights.eligible_for(record, "DISPLAY") is True
    assert rights.eligible_for(record, "REDISTRIBUTION") is True


def test_no_ai_restriction_false_on_unreviewed_source_is_not_permission():
    # noAiRestriction=false must never be read as permission on its own --
    # legalReviewState gates every decision before anything else is inspected.
    record = _base_record(rights=_base_rights(
        legalReviewState="UNREVIEWED", noAiRestriction=False,
    ))
    for use in rights.ELIGIBILITY_BY_USE:
        assert rights.eligible_for(record, use) is False


def test_royalty_free_string_alone_cannot_grant_training():
    # decisionBasis is free text and is never read by any eligibility
    # function -- only the boolean fields are. A record whose decisionBasis
    # says "royalty free" but whose trainingAllowed is false (the honest
    # state for an unreviewed/undetermined source) must still deny training.
    r = _base_rights(
        legalReviewState="UNREVIEWED",
        trainingAllowed=False,
        decisionBasis="royalty free per provider marketing page",
    )
    record = _base_record(rights=r)
    assert rights.eligible_for(record, "TRAINING") is False
    # Also true even if legalReviewState were REVIEWED but trainingAllowed
    # was never actually set true by that review.
    r2 = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        trainingAllowed=False, noAiRestriction=False,
        decisionBasis="royalty free per provider marketing page",
    )
    record2 = _base_record(rights=r2)
    assert rights.eligible_for(record2, "TRAINING") is False


def test_search_discovery_can_never_be_training_or_display_source():
    # Even a (hypothetically miswritten) REVIEWED+allowed SEARCH_DISCOVERY
    # record must still be refused -- the priority check is structural,
    # independent of the rights booleans. Every other gate (review state,
    # commercial clearance, terms captured, no-AI restriction) is
    # deliberately satisfied here so the only possible reason for denial is
    # the DISCOVERY_ONLY priority itself.
    record = _base_record(
        sourceClass="SEARCH_DISCOVERY", priority="DISCOVERY_ONLY",
        rights=_base_rights(
            legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
            displayAllowed=True, trainingAllowed=True, noAiRestriction=False,
            commercialAllowed=True, termsCaptured=True,
        ),
    )
    assert rights.eligible_for(record, "DISPLAY") is False
    assert rights.eligible_for(record, "TRAINING") is False


def test_no_adapter_can_auto_promote_a_source():
    # Structural: this module exposes no function that mutates a record's
    # legalReviewState or any permission boolean -- only load/validate/read
    # eligibility. Promotion is a human editing source_registry.json by hand.
    import inspect
    mutating_names = [
        name for name, obj in vars(rights).items()
        if inspect.isfunction(obj) and (
            "promote" in name.lower() or "approve" in name.lower() or "grant" in name.lower()
        )
    ]
    assert mutating_names == []


def test_validator_never_rewrites_the_registry_file():
    before = rights.SOURCE_REGISTRY.read_bytes()
    rights.load_registry()
    rights.main()
    after = rights.SOURCE_REGISTRY.read_bytes()
    assert before == after


def test_reviewed_state_requires_reviewed_at():
    r = _base_rights(legalReviewState="REVIEWED")
    r.pop("reviewedAt", None)
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="reviewedAt"):
        rights.validate_source_record(record)


def test_terms_snapshot_hash_requires_terms_captured_flag():
    r = _base_rights(termsCaptured=False)
    r["termsSnapshotSha256"] = "a" * 64
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsCaptured"):
        rights.validate_source_record(record)


def test_reviewed_without_terms_captured_fails_validation():
    # A REVIEWED record whose terms were never actually captured is exactly
    # the "review by rumor" gap this registry exists to close -- caught by
    # security-reviewer and silent-failure-hunter independently in the
    # P0.G3 review round.
    r = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        displayAllowed=True, termsCaptured=False,
    )
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsCaptured"):
        rights.validate_source_record(record)


def test_blocked_state_cannot_carry_a_granted_permission():
    # BLOCKED means "review happened and the answer was no" -- a BLOCKED
    # record with a true permission boolean is a self-contradictory record
    # and must be rejected at validation, not just silently non-eligible.
    r = _base_rights(
        legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
        displayAllowed=True,
    )
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="BLOCKED"):
        rights.validate_source_record(record)


def test_commercial_clearance_is_required_for_every_privileged_use():
    # commercialAllowed is a required rights field but was, before this
    # fix, never read by any eligibility function -- a REVIEWED, otherwise-
    # fully-allowed, non-commercially-cleared source must still be refused
    # for every use, since SPTR is itself a commercial product.
    record = _reviewed_permissive_record(
        commercialAllowed=False,
        displayAllowed=True, recognitionProcessingAllowed=True,
        trainingAllowed=True, derivativeAllowed=True, redistributionAllowed=True,
    )
    for use in rights.ELIGIBILITY_BY_USE:
        assert rights.eligible_for(record, use) is False


def test_load_registry_does_not_mutate_input_records():
    sources = rights.load_registry()
    snapshot = copy.deepcopy(sources)
    for record in sources:
        rights.validate_source_record(record)
        for use in rights.ELIGIBILITY_BY_USE:
            rights.eligible_for(record, use)
    assert sources == snapshot
