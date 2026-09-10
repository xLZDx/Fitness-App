# -*- coding: utf-8 -*-
"""B1 steps 2 and 7 tests for scripts/equipment_identity/terms_candidates.py.

    python -m pytest scripts/equipment_identity/test_terms_candidates.py -q

On the grammar tests below: the string set is a **boundary corpus**, and it is
called that here, in the module under test, in the decision log and in the
report. It backs the structural argument; it does not constitute it. The
language is unbounded, so no finite set could -- and calling one "exhaustive"
would be a claim wider than its evidence in the very place built to stop that.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import terms_candidates as tc  # noqa: E402


# --------------------------------------------------------------------------
# Fixture builders.
# --------------------------------------------------------------------------

def observed_candidate(**overrides) -> dict:
    base = {
        "candidateDocId": "terms_of_use",
        "documentUrls": ["https://example.test/terms"],
        "allowedFinalUrls": ["https://example.test/terms"],
        "declaredMediaTypes": ["text/html"],
        "observationState": "OBSERVED",
        "observedAtUtc": "2026-09-10T00:00:00Z",
        "observationMethod": "WEB_FETCH_MARKDOWN_EXTRACTION",
        "identityExpectations": {"requiredMarkers": ["PROHIBITED ACTIVITIES"]},
    }
    base.update(overrides)
    return base


def unobserved_candidate(**overrides) -> dict:
    base = {
        "candidateDocId": "other_terms",
        "documentUrls": ["https://example.test/other"],
        "allowedFinalUrls": ["https://example.test/other"],
        "declaredMediaTypes": ["text/html"],
        "observationState": "NOT_OBSERVED",
        "observedAtUtc": None,
        "observationMethod": None,
    }
    base.update(overrides)
    return base


def manifest(*candidates, reason=None, source_id="example_source") -> dict:
    return {
        "manifestKind": "TERMS_CANDIDATE_DOCUMENTS",
        "sources": [{
            "sourceId": source_id,
            "candidates": list(candidates),
            "noCandidatesReason": reason,
        }],
    }


def check(doc: dict) -> None:
    tc.validate_candidates(doc, expect_targets=False)


# --------------------------------------------------------------------------
# Controls.
# --------------------------------------------------------------------------

def test_an_observed_candidate_is_accepted():
    check(manifest(observed_candidate()))


def test_an_unobserved_candidate_is_accepted():
    check(manifest(unobserved_candidate()))


def test_a_source_with_no_candidates_and_a_reason_is_accepted():
    check(manifest(reason="the host refuses programmatic requests"))


# --------------------------------------------------------------------------
# STEP 7 -- the candidateDocId grammar.
# --------------------------------------------------------------------------

ACCEPTED_BOUNDARY_CORPUS = [
    "a", "z", "0", "9",
    "terms_of_use", "legal_terms_conditions", "pages_terms_and_conditions",
    "a-b", "a_b", "a-b_c-d", "x9-y_z0",
    "terms" + "0123456789" * 12,
]

REJECTED_BOUNDARY_CORPUS = [
    "", ".", "..", "./x", "../x", "x/..",
    "a/b", "a\\b", "a:b", "C:", "C:\\x", "//host/share",
    "a b", "a\tb", "a\nb", "\n", " a",
    "_leading", "-leading",
    "A", "aB", "Terms", "ünicode", "a.b",
    "terms_of_use\n",  # the trailing-newline trap: Python's `$` would accept it
]


@pytest.mark.parametrize("value", ACCEPTED_BOUNDARY_CORPUS)
def test_the_grammar_accepts_these_boundary_strings(value):
    assert tc.is_valid_candidate_doc_id(value)


@pytest.mark.parametrize("value", REJECTED_BOUNDARY_CORPUS)
def test_the_grammar_rejects_these_boundary_strings(value):
    assert not tc.is_valid_candidate_doc_id(value)


def test_the_terminator_refuses_a_trailing_newline():
    """`$` would accept this. `(?![\\s\\S])` does not.

    Called out on its own rather than left inside the corpus because it is the
    specific defect `rights.py::_SOURCE_ID_RE` still carries, and a reader of
    this file should be able to find it by name.
    """
    assert tc.is_valid_candidate_doc_id("terms_of_use")
    assert not tc.is_valid_candidate_doc_id("terms_of_use\n")


def test_the_structural_claim_holds_over_the_boundary_corpus():
    """The alphabet excludes the dangerous characters, so no accepted string has one.

    This CHECKS the structural argument on a sample. It does not PROVE it -- the
    proof is that the character classes cannot emit these characters at any
    length, and it is written beside the pattern in the module under test.
    """
    dangerous = set(". / \\ : \t \n \r".split()) | {" "}
    for value in ACCEPTED_BOUNDARY_CORPUS:
        assert tc.is_valid_candidate_doc_id(value)
        assert not (set(value) & dangerous), f"{value!r} slipped a dangerous character"


def test_a_non_string_candidate_doc_id_does_not_crash_the_check():
    for value in (None, 3, [], {}, b"terms"):
        assert not tc.is_valid_candidate_doc_id(value)


def test_an_invalid_candidate_doc_id_is_rejected_by_the_manifest():
    with pytest.raises(tc.CandidateManifestError, match="does not match"):
        check(manifest(observed_candidate(candidateDocId="../escape")))


# --------------------------------------------------------------------------
# STEP 2 -- what the manifest may not be able to say.
# --------------------------------------------------------------------------

@pytest.mark.parametrize("field", sorted(tc.FORBIDDEN_CANDIDATE_FIELDS))
def test_a_candidate_may_not_declare_a_legal_conclusion(field):
    with pytest.raises(tc.CandidateManifestError, match="legal conclusion"):
        check(manifest(observed_candidate(**{field: True})))


def test_the_committed_manifest_declares_no_legal_conclusion():
    for source in tc.load_candidates()["sources"]:
        for candidate in source["candidates"]:
            assert not (tc.FORBIDDEN_CANDIDATE_FIELDS & set(candidate))


# --------------------------------------------------------------------------
# STEP 2 -- an unopened document may not be described.
# --------------------------------------------------------------------------

def test_an_unobserved_candidate_may_not_carry_identity_expectations():
    doc = manifest(unobserved_candidate(
        identityExpectations={"requiredMarkers": ["PROHIBITED ACTIVITIES"]}
    ))
    with pytest.raises(tc.CandidateManifestError, match="invented rather than seen"):
        check(doc)


def test_an_unobserved_candidate_may_not_claim_an_observation_time():
    doc = manifest(unobserved_candidate(observedAtUtc="2026-09-10T00:00:00Z"))
    with pytest.raises(tc.CandidateManifestError, match="claims an observation happened"):
        check(doc)


def test_an_unobserved_candidate_may_not_claim_an_observation_method():
    doc = manifest(unobserved_candidate(observationMethod="WEB_FETCH_MARKDOWN_EXTRACTION"))
    with pytest.raises(tc.CandidateManifestError, match="claims an observation happened"):
        check(doc)


def test_an_observed_candidate_without_expectations_is_rejected():
    doc = manifest(observed_candidate(identityExpectations=None))
    with pytest.raises(tc.CandidateManifestError, match="requires identityExpectations"):
        check(doc)


def test_an_observed_candidate_with_no_markers_is_rejected():
    doc = manifest(observed_candidate(identityExpectations={"requiredMarkers": []}))
    with pytest.raises(tc.CandidateManifestError, match="vacuously true"):
        check(doc)


def test_the_committed_manifest_describes_only_what_was_opened():
    for source in tc.load_candidates()["sources"]:
        for candidate in source["candidates"]:
            if candidate["observationState"] == "NOT_OBSERVED":
                assert candidate.get("identityExpectations") is None
                assert candidate.get("observedAtUtc") is None
            else:
                assert candidate["identityExpectations"]["requiredMarkers"]


# --------------------------------------------------------------------------
# STEP 2 -- structure.
# --------------------------------------------------------------------------

def test_a_plaintext_document_url_is_rejected():
    doc = manifest(observed_candidate(documentUrls=["http://example.test/terms"]))
    with pytest.raises(tc.CandidateManifestError, match="not https"):
        check(doc)


def test_a_plaintext_allowed_final_url_is_rejected():
    """Separate from the rule above, and separately provable: different field.

    A downgrade smuggled into the ALLOWED set would authorise the redirect guard
    to accept plaintext later, which is not the same hole as a plaintext start.
    """
    doc = manifest(observed_candidate(allowedFinalUrls=["http://example.test/terms"]))
    with pytest.raises(tc.CandidateManifestError, match="not https"):
        check(doc)


def test_an_empty_media_type_list_is_rejected():
    doc = manifest(observed_candidate(declaredMediaTypes=[]))
    with pytest.raises(tc.CandidateManifestError, match="declaredMediaTypes"):
        check(doc)


def test_a_duplicate_candidate_doc_id_is_rejected():
    doc = manifest(observed_candidate(), observed_candidate())
    with pytest.raises(tc.CandidateManifestError, match="duplicate candidateDocId"):
        check(doc)


def test_a_duplicate_source_id_across_two_entries_is_rejected():
    """`manifest()` above only ever builds ONE source; this is the sibling
    check one level up -- two DIFFERENT source entries sharing one sourceId."""
    doc = {
        "manifestKind": "TERMS_CANDIDATE_DOCUMENTS",
        "sources": [
            {"sourceId": "dup_source", "candidates": [], "noCandidatesReason": "none found"},
            {"sourceId": "dup_source", "candidates": [], "noCandidatesReason": "still none"},
        ],
    }
    with pytest.raises(tc.CandidateManifestError, match="duplicate sourceId"):
        check(doc)


def test_expect_targets_true_rejects_a_manifest_missing_a_b1_target():
    doc = manifest(observed_candidate(), source_id=tc.B1_TARGET_SOURCE_IDS[0])
    with pytest.raises(tc.CandidateManifestError, match="missing="):
        tc.validate_candidates(doc, expect_targets=True)


def test_expect_targets_true_rejects_a_manifest_with_an_extra_non_target_source():
    doc = {
        "manifestKind": "TERMS_CANDIDATE_DOCUMENTS",
        "sources": [
            {"sourceId": sid, "candidates": [], "noCandidatesReason": "none found"}
            for sid in tc.B1_TARGET_SOURCE_IDS
        ] + [{"sourceId": "not_a_b1_target", "candidates": [], "noCandidatesReason": "none found"}],
    }
    with pytest.raises(tc.CandidateManifestError, match="extra="):
        tc.validate_candidates(doc, expect_targets=True)


def test_an_empty_candidate_list_without_a_reason_is_rejected():
    with pytest.raises(tc.CandidateManifestError, match="nobody looked"):
        check(manifest())


def test_a_reason_recorded_beside_real_candidates_is_rejected():
    doc = manifest(observed_candidate(), reason="none found")
    with pytest.raises(tc.CandidateManifestError, match="both cannot be true"):
        check(doc)


def test_an_unknown_observation_state_is_rejected():
    doc = manifest(observed_candidate(observationState="PROBABLY_SEEN"))
    with pytest.raises(tc.CandidateManifestError, match="observationState must be one of"):
        check(doc)


def test_a_wrong_manifest_kind_is_rejected():
    doc = manifest(observed_candidate())
    doc["manifestKind"] = "SOMETHING_ELSE"
    with pytest.raises(tc.CandidateManifestError, match="manifestKind"):
        check(doc)


# --------------------------------------------------------------------------
# STEP 2 -- resolve_candidate is the only door.
# --------------------------------------------------------------------------

def test_resolve_returns_the_trusted_record():
    doc = tc.load_candidates()
    record = tc.resolve_candidate(
        "life_fitness_hammer_strength_product_catalog", "terms_of_use", doc
    )
    assert record["documentUrls"] == ["https://www.lifefitness.com/en-us/terms-of-use"]
    assert record["observationState"] == "OBSERVED"


def test_resolve_refuses_a_candidate_the_manifest_never_registered():
    """The E2 headline: a caller cannot invent a document.

    Otherwise a well-formed request with correct source, correct bases and real
    bytes publishes a perfectly consistent capture of a document B1 never knew
    about.
    """
    with pytest.raises(tc.CandidateManifestError, match="never registered"):
        tc.resolve_candidate(
            "life_fitness_hammer_strength_product_catalog",
            "legal_page",
            tc.load_candidates(),
        )


def test_resolve_refuses_an_unknown_source():
    with pytest.raises(tc.CandidateManifestError, match="no source"):
        tc.resolve_candidate("wger_project", "terms_of_use", tc.load_candidates())


def test_resolve_refuses_an_ill_formed_candidate_doc_id():
    with pytest.raises(tc.CandidateManifestError, match="does not match"):
        tc.resolve_candidate(
            "life_fitness_hammer_strength_product_catalog", "../etc", tc.load_candidates()
        )


def test_resolve_finds_nothing_for_a_source_with_no_candidates():
    with pytest.raises(tc.CandidateManifestError, match="never registered"):
        tc.resolve_candidate("technogym_product_catalog", "terms_of_use", tc.load_candidates())


def test_resolve_hands_back_a_copy_the_caller_cannot_use_to_edit_the_record():
    """A resolver that returns a live reference is a writer wearing a reader's name."""
    doc = tc.load_candidates()
    record = tc.resolve_candidate(
        "core_health_fitness_nautilus_product_catalog", "terms_and_conditions", doc
    )
    record["allowedFinalUrls"].append("https://attacker.test/")
    record["identityExpectations"]["requiredMarkers"].clear()

    again = tc.resolve_candidate(
        "core_health_fitness_nautilus_product_catalog", "terms_and_conditions", doc
    )
    assert "https://attacker.test/" not in again["allowedFinalUrls"]
    assert again["identityExpectations"]["requiredMarkers"]


# --------------------------------------------------------------------------
# The committed manifest and the file on disk.
# --------------------------------------------------------------------------

def test_the_committed_manifest_validates():
    tc.validate_candidates(tc.load_candidates())


def test_the_committed_manifest_covers_exactly_the_three_b1_targets():
    doc = tc.load_candidates()
    assert {s["sourceId"] for s in doc["sources"]} == set(tc.B1_TARGET_SOURCE_IDS)


def test_life_fitness_keeps_two_candidates_and_neither_is_preferred():
    doc = {s["sourceId"]: s for s in tc.load_candidates()["sources"]}
    candidates = doc["life_fitness_hammer_strength_product_catalog"]["candidates"]
    assert len(candidates) == 2, "both Life Fitness documents stay registered"
    for candidate in candidates:
        assert not (tc.FORBIDDEN_CANDIDATE_FIELDS & set(candidate))


def test_technogym_records_no_candidates_and_says_why():
    doc = {s["sourceId"]: s for s in tc.load_candidates()["sources"]}
    entry = doc["technogym_product_catalog"]
    assert entry["candidates"] == []
    assert "403" in entry["noCandidatesReason"]


def test_the_manifest_file_is_pure_lf():
    assert tc.CANDIDATES_PATH.read_bytes().count(b"\r\n") == 0


def test_the_manifest_file_is_valid_utf8_json():
    json.loads(tc.CANDIDATES_PATH.read_bytes().decode("utf-8"))


def test_load_candidates_reports_a_missing_file_rather_than_crashing(tmp_path):
    with pytest.raises(tc.CandidateManifestError, match="not found"):
        tc.load_candidates(tmp_path / "absent.json")


def test_load_candidates_reports_malformed_json_rather_than_crashing(tmp_path):
    broken = tmp_path / "broken.json"
    broken.write_bytes(b"{nope")
    with pytest.raises(tc.CandidateManifestError, match="not valid UTF-8 JSON"):
        tc.load_candidates(broken)
