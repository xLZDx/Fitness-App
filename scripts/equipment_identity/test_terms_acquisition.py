# -*- coding: utf-8 -*-
"""B1 step 1 tests for scripts/equipment_identity/terms_acquisition.py.

    python -m pytest scripts/equipment_identity/test_terms_acquisition.py -q

Every rejection test below is paired with a control that stays green, because a
guard that rejects everything proves nothing about what it is supposed to catch.
And each rejection is aimed at a fixture that ONLY that guard refuses -- if two
of these ever start catching each other's cases, one of them is redundant and
belongs deleted, per the precedent in `rights.py::_resolve_terms_snapshot`.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import terms_acquisition as ta  # noqa: E402


# --------------------------------------------------------------------------
# Fixture builders. Deliberately minimal: a fixture carrying more than the rule
# under test needs makes it ambiguous which field caused the refusal.
# --------------------------------------------------------------------------

def robots_allow_evidence() -> dict:
    return {
        "method": "ROBOTS_PARSER_PROBE",
        "target": "https://example.test/robots.txt",
        "observedAtUtc": "2026-09-09T00:00:00Z",
        "result": "HTTP 200, 1045 bytes, can_fetch('agent')=True, can_fetch('*')=True",
    }


def robots_disallow_evidence() -> dict:
    return {
        "method": "ROBOTS_PARSER_PROBE",
        "target": "https://example.test/robots.txt",
        "observedAtUtc": "2026-09-09T00:00:00Z",
        "result": "HTTP 200, 900 bytes, can_fetch('agent')=False",
    }


def robots_403_evidence() -> dict:
    return {
        "method": "ROBOTS_PARSER_PROBE",
        "target": "https://example.test/robots.txt",
        "observedAtUtc": "2026-09-09T00:00:00Z",
        "result": "HTTPError: HTTP Error 403: Forbidden",
    }


def document_evidence() -> dict:
    return {
        "method": "WEB_FETCH_MARKDOWN_EXTRACTION",
        "target": "https://example.test/terms",
        "observedAtUtc": "2026-09-10T00:00:00Z",
        "result": "Clauses quoted verbatim.",
    }


def prohibition_clause() -> dict:
    return {
        "topic": "AUTOMATED_ACCESS",
        "section": "Section 4: PROHIBITED ACTIVITIES",
        "verbatim": "you will not access the Site through automated or non-human means",
    }


def copying_clause() -> dict:
    return {
        "topic": "COPYING_AND_RETENTION",
        "section": "Section 2: INTELLECTUAL PROPERTY RIGHTS",
        "verbatim": "solely for your personal, non-commercial use",
    }


def observation(**overrides) -> dict:
    base = {
        "sourceId": "example_source",
        "outcome": "AUTO_FETCH_REFUSED",
        "reason": "The published terms prohibit automated access.",
        "documentBytesHeld": False,
        "documentSha256": None,
        "evidence": [robots_allow_evidence(), document_evidence()],
        "quotedClauses": [prohibition_clause()],
    }
    base.update(overrides)
    return base


def ledger(*observations, pending=None) -> dict:
    out = {
        "ledgerKind": "TERMS_ACQUISITION_PREFLIGHT",
        "observations": list(observations) or [observation()],
    }
    if pending is not None:
        out["pendingAuthorizations"] = pending
    return out


def check(doc: dict) -> None:
    """Validate a fixture without demanding the full B1 target set."""
    ta.validate_preflight(doc, expect_targets=False)


# --------------------------------------------------------------------------
# The control. If this ever goes red, every rejection below is meaningless.
# --------------------------------------------------------------------------

def test_a_well_supported_refusal_is_accepted():
    check(ledger())


# --------------------------------------------------------------------------
# The committed ledger itself.
# --------------------------------------------------------------------------

def test_the_committed_preflight_ledger_validates():
    ta.validate_preflight(ta.load_preflight())


def test_the_committed_ledger_covers_exactly_the_three_b1_targets():
    doc = ta.load_preflight()
    assert [o["sourceId"] for o in doc["observations"]] == list(ta.B1_TARGET_SOURCE_IDS)


def test_the_committed_ledger_records_the_measured_outcomes():
    doc = {o["sourceId"]: o for o in ta.load_preflight()["observations"]}
    assert doc["technogym_product_catalog"]["outcome"] == "AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE"
    assert doc["life_fitness_hammer_strength_product_catalog"]["outcome"] == "AUTO_FETCH_REFUSED"
    assert doc["core_health_fitness_nautilus_product_catalog"]["outcome"] == "AUTO_FETCH_REFUSED"


def test_no_committed_observation_claims_permission():
    for entry in ta.load_preflight()["observations"]:
        assert entry["outcome"] != "AUTO_FETCH_PERMITTED_BY_BASIS"
        assert entry.get("acquisitionBasisRef") is None


def test_no_committed_observation_claims_bytes_it_does_not_hold():
    for entry in ta.load_preflight()["observations"]:
        assert entry["documentBytesHeld"] is False
        assert entry["documentSha256"] is None


# --------------------------------------------------------------------------
# THE ASYMMETRY. This is the pair the whole ledger turns on, and it is asserted
# against the REAL committed rows rather than a fixture, because the point is
# that reality actually looks like this: both refused hosts allow in robots.txt.
# A check that read robots.txt and stopped would have concluded the opposite of
# the truth on two of three targets.
# --------------------------------------------------------------------------

def test_a_robots_allow_did_not_become_permission_on_the_real_ledger():
    doc = {o["sourceId"]: o for o in ta.load_preflight()["observations"]}
    for source_id in (
        "life_fitness_hammer_strength_product_catalog",
        "core_health_fitness_nautilus_product_catalog",
    ):
        entry = doc[source_id]
        probes = [e for e in entry["evidence"] if e["method"] == "ROBOTS_PARSER_PROBE"]
        assert probes, f"{source_id}: expected a robots probe on the record"
        assert any("=True" in p["result"] for p in probes), (
            f"{source_id}: this test is only meaningful while robots.txt actually allows"
        )
        assert entry["outcome"] == "AUTO_FETCH_REFUSED"


def test_a_robots_403_did_not_become_a_prohibition_on_the_real_ledger():
    entry = {o["sourceId"]: o for o in ta.load_preflight()["observations"]}[
        "technogym_product_catalog"
    ]
    assert any("403" in e["result"] for e in entry["evidence"])
    assert entry["outcome"] == "AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE"
    assert entry["quotedClauses"] == []


# --------------------------------------------------------------------------
# Guard: a refusal must carry the words that refuse.
# --------------------------------------------------------------------------

def test_a_refusal_with_no_quoted_clause_is_rejected():
    doc = ledger(observation(quotedClauses=[]))
    with pytest.raises(ta.PreflightValidationError, match="requires either a verbatim clause"):
        check(doc)


def test_a_refusal_quoting_only_a_copying_clause_is_rejected():
    """A copying restriction is real, and it is not a statement about ACCESS.

    This is the narrowest margin in the module: the fixture carries a genuine,
    verbatim, correctly-sectioned clause from the actual document -- it is simply
    about the wrong thing. Accepting it would be a claim wider than its evidence.
    """
    doc = ledger(observation(quotedClauses=[copying_clause()]))
    with pytest.raises(ta.PreflightValidationError, match="requires either a verbatim clause"):
        check(doc)


def test_a_refusal_whose_only_evidence_is_a_403_is_rejected():
    """A host that will not show its policy has not stated one."""
    doc = ledger(observation(evidence=[robots_403_evidence()], quotedClauses=[]))
    with pytest.raises(ta.PreflightValidationError, match="requires either a verbatim clause"):
        check(doc)


def test_a_refusal_quoting_a_clause_no_document_read_produced_is_rejected():
    """A robots probe cannot supply a quotation from the terms.

    robots.txt is a different artifact from the terms document. A record whose
    only evidence is a probe, yet which quotes prose, is citing something it
    never opened -- which is exactly the failure this whole module was built
    after.
    """
    doc = ledger(observation(evidence=[robots_allow_evidence()]))
    with pytest.raises(ta.PreflightValidationError, match="requires either a verbatim clause"):
        check(doc)


def test_a_robots_disallow_alone_supports_a_refusal():
    """The other branch, so the rule is not silently quote-only."""
    check(ledger(observation(evidence=[robots_disallow_evidence()], quotedClauses=[])))


# --------------------------------------------------------------------------
# Guard: an unreadable policy cannot be quoted.
# --------------------------------------------------------------------------

def test_policy_unavailable_that_quotes_a_prohibition_is_rejected():
    doc = ledger(observation(
        outcome="AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE",
        evidence=[robots_403_evidence()],
        quotedClauses=[prohibition_clause()],
    ))
    with pytest.raises(ta.PreflightValidationError, match="policy was unavailable"):
        check(doc)


def test_policy_unavailable_with_no_quotes_is_accepted():
    check(ledger(observation(
        outcome="AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE",
        evidence=[robots_403_evidence()],
        quotedClauses=[],
    )))


def test_policy_unavailable_may_still_carry_a_copying_clause():
    """Only PROHIBITION topics contradict 'unreadable'; the guard is not a blanket ban."""
    check(ledger(observation(
        outcome="AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE",
        evidence=[robots_403_evidence(), document_evidence()],
        quotedClauses=[copying_clause()],
    )))


# --------------------------------------------------------------------------
# Guard: the outcome that authorizes is unreachable until a basis registry exists.
# --------------------------------------------------------------------------

def test_permitted_by_basis_is_refused_while_no_basis_registry_exists():
    doc = ledger(observation(outcome="AUTO_FETCH_PERMITTED_BY_BASIS"))
    with pytest.raises(ta.PreflightValidationError, match="ACQUISITION capability"):
        check(doc)


def test_permitted_by_basis_is_refused_even_with_a_robots_allow():
    """The asymmetry, stated as a rejection rather than only as a comment."""
    doc = ledger(observation(
        outcome="AUTO_FETCH_PERMITTED_BY_BASIS",
        evidence=[robots_allow_evidence()],
        quotedClauses=[],
    ))
    with pytest.raises(ta.PreflightValidationError, match="never permission"):
        check(doc)


# --------------------------------------------------------------------------
# Guard: bytes claimed versus bytes held. Two separate rules, two fields.
# --------------------------------------------------------------------------

def test_a_digest_without_held_bytes_is_rejected():
    doc = ledger(observation(documentBytesHeld=False, documentSha256="a" * 64))
    with pytest.raises(ta.PreflightValidationError, match="cannot be re-verified"):
        check(doc)


def test_held_bytes_without_a_digest_is_rejected():
    doc = ledger(observation(documentBytesHeld=True, documentSha256=None))
    with pytest.raises(ta.PreflightValidationError, match="requires documentSha256"):
        check(doc)


def test_held_bytes_with_a_digest_is_accepted():
    check(ledger(observation(documentBytesHeld=True, documentSha256="b" * 64)))


def test_a_byteless_evidence_method_may_not_carry_a_digest():
    """Distinct from the two rules above: this one is on the EVIDENCE item.

    A markdown conversion read by a model is text about the bytes, not the bytes.
    A digest attached to it would describe the conversion while reading as if it
    described the document.
    """
    evidence = document_evidence()
    evidence["sha256"] = "c" * 64
    doc = ledger(observation(evidence=[evidence]))
    with pytest.raises(ta.PreflightValidationError, match="never holds raw bytes"):
        check(doc)


def test_a_document_reading_method_that_did_hold_bytes_may_carry_a_digest():
    evidence = {
        "method": "COMMITTED_REPOSITORY_DOCUMENT",
        "target": "core/equipment_identity/p1/P1_G2_OFFICIAL_P0_ADAPTERS.md",
        "observedAtUtc": "2026-08-22T00:00:00Z",
        "result": "recorded in the repository",
        "sha256": "d" * 64,
    }
    check(ledger(observation(evidence=[evidence])))


# --------------------------------------------------------------------------
# Guard: structure.
# --------------------------------------------------------------------------

def test_an_unknown_outcome_is_rejected():
    with pytest.raises(ta.PreflightValidationError, match="unknown outcome"):
        check(ledger(observation(outcome="PROBABLY_FINE")))


def test_an_unknown_evidence_method_is_rejected():
    evidence = document_evidence()
    evidence["method"] = "I_ASKED_SOMEONE"
    with pytest.raises(ta.PreflightValidationError, match="unknown evidence method"):
        check(ledger(observation(evidence=[evidence])))


def test_an_observation_with_no_evidence_is_rejected():
    with pytest.raises(ta.PreflightValidationError, match="non-empty list"):
        check(ledger(observation(evidence=[])))


def test_a_clause_missing_its_section_is_rejected():
    clause = prohibition_clause()
    clause["section"] = ""
    with pytest.raises(ta.PreflightValidationError, match="section must be a non-empty string"):
        check(ledger(observation(quotedClauses=[clause])))


def test_a_duplicate_source_id_is_rejected():
    doc = ledger(observation(), observation())
    with pytest.raises(ta.PreflightValidationError, match="duplicate sourceId"):
        check(doc)


def test_the_wrong_target_set_is_rejected_when_targets_are_expected():
    with pytest.raises(ta.PreflightValidationError, match="exactly the B1 targets"):
        ta.validate_preflight(ledger(), expect_targets=True)


def test_a_wrong_ledger_kind_is_rejected():
    doc = ledger()
    doc["ledgerKind"] = "SOMETHING_ELSE"
    with pytest.raises(ta.PreflightValidationError, match="ledgerKind"):
        check(doc)


# --------------------------------------------------------------------------
# Guard: a request is not a grant.
# --------------------------------------------------------------------------

def test_a_pending_authorization_may_not_be_marked_granted():
    doc = ledger(pending=[{
        "sourceId": "example_source",
        "state": "GRANTED",
        "target": "https://portal.test",
        "observation": "access approved",
    }])
    with pytest.raises(ta.PreflightValidationError, match="REQUESTED_NOT_GRANTED"):
        check(doc)


def test_a_pending_authorization_may_not_carry_a_basis_ref():
    doc = ledger(pending=[{
        "sourceId": "example_source",
        "state": "REQUESTED_NOT_GRANTED",
        "target": "https://portal.test",
        "observation": "requested",
        "acquisitionBasisRef": "basis-001",
    }])
    with pytest.raises(ta.PreflightValidationError, match="not granted"):
        check(doc)


def test_the_committed_portal_request_is_recorded_as_a_request_only():
    pending = ta.load_preflight().get("pendingAuthorizations", [])
    assert pending, "the Core H&F portal request should be on the record"
    for entry in pending:
        assert entry["state"] == "REQUESTED_NOT_GRANTED"
        assert entry.get("acquisitionBasisRef") is None


# --------------------------------------------------------------------------
# The file on disk.
# --------------------------------------------------------------------------

def test_the_ledger_file_is_pure_lf():
    raw = ta.PREFLIGHT_PATH.read_bytes()
    assert raw.count(b"\r\n") == 0, "the repository's equipment_identity files are LF"


def test_the_ledger_file_is_valid_utf8_json():
    json.loads(ta.PREFLIGHT_PATH.read_bytes().decode("utf-8"))


def test_load_preflight_reports_a_missing_file_rather_than_crashing(tmp_path):
    with pytest.raises(ta.PreflightValidationError, match="not found"):
        ta.load_preflight(tmp_path / "absent.json")


def test_load_preflight_reports_malformed_json_rather_than_crashing(tmp_path):
    broken = tmp_path / "broken.json"
    broken.write_bytes(b"{not json")
    with pytest.raises(ta.PreflightValidationError, match="not valid UTF-8 JSON"):
        ta.load_preflight(broken)


def test_the_committed_ledger_is_not_mutated_by_validation():
    """Validation must be a read. A validator that edits its input is a writer."""
    before = copy.deepcopy(ta.load_preflight())
    doc = ta.load_preflight()
    ta.validate_preflight(doc)
    assert doc == before
