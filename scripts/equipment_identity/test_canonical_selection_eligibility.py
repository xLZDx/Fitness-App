# -*- coding: utf-8 -*-
"""Tests for scripts/equipment_identity/canonical_selection_eligibility.py
(pre-P1.G5 direct-corroboration pass, GPT-PM spec 2026-08-22).

    python -m pytest scripts/equipment_identity/test_canonical_selection_eligibility.py -q
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import canonical_selection_eligibility as cse  # noqa: E402
import rights  # noqa: E402


def _candidate(brandId="matrix", modelCode="X1", candidateId="cid1", provenance=None):
    return {
        "candidateId": candidateId,
        "brandId": brandId,
        "modelCode": modelCode,
        "provenance": provenance if provenance is not None else [],
    }


# --- GPT-PM's own explicit test scenarios ----------------------------------


def test_snippet_only_candidate_is_not_eligible():
    candidate = _candidate(
        brandId="technogym", modelCode="NOT_A_REAL_CODE",
        provenance=[{"sourceId": "s", "sourceUrl": "u", "retrievalMethod": "SEARCH_INDEX_SNIPPET"}],
    )
    corroboration = cse.direct_corroboration_for(candidate, {})
    assert corroboration is None


def test_candidate_with_direct_official_corroboration_may_become_eligible_when_preconditions_pass():
    candidate = _candidate(
        brandId="precor", modelCode="RSL0602",
        provenance=[{"sourceId": "s", "sourceUrl": "u", "retrievalMethod": "DIRECT_FETCH", "fixtureSha256": "a" * 64}],
    )
    corroboration = cse.direct_corroboration_for(candidate, {})
    assert corroboration is not None
    assert corroboration["retrievalMethod"] == "DIRECT_FETCH"
    # Eligibility itself is a separate, two-factor decision -- having direct
    # evidence is necessary but not sufficient; see the fail-closed tests below.


def test_brand_direct_counts_computed_from_real_data():
    counts = cse.direct_corroboration_counts_by_brand(
        cse.load_combined_pool(), cse.load_matrix_pdf_corroboration()
    )
    assert counts.get("technogym", 0) == 0
    assert counts.get("matrix", 0) >= cse.BRAND_FLOOR_MINIMUM
    assert counts.get("panatta", 0) == 0
    assert counts.get("precor", 0) >= cse.BRAND_FLOOR_MINIMUM
    assert counts.get("nautilus", 0) >= cse.BRAND_FLOOR_MINIMUM
    assert counts.get("life-fitness", 0) >= cse.BRAND_FLOOR_MINIMUM
    assert counts.get("hammer-strength", 0) >= cse.BRAND_FLOOR_MINIMUM


def test_eligible_total_reflects_real_pool_state():
    counts = cse.direct_corroboration_counts_by_brand(
        cse.load_combined_pool(), cse.load_matrix_pdf_corroboration()
    )
    total = sum(counts.values())
    assert total == 40  # today's real, honest number -- not >=50 yet


# --- fail-closed two-factor eligibility -------------------------------------


def test_overall_preconditions_not_met_today_technogym_and_panatta_zero():
    counts = cse.direct_corroboration_counts_by_brand(
        cse.load_combined_pool(), cse.load_matrix_pdf_corroboration()
    )
    met, reasons = cse.overall_preconditions_met(counts)
    assert met is False
    assert any("technogym" in r for r in reasons)
    assert any("panatta" in r for r in reasons)
    assert any("total direct pool" in r for r in reasons)


def test_all_selected_50_scenario_is_eligible():
    # GPT-PM's third scenario: "all selected 50 -> canonicalSelectionEligible=true".
    # Construct a synthetic counts dict clearing every floor and confirm the
    # gate function itself (not the real, still-short-of-50 data) resolves true.
    counts = {"technogym": 4, "matrix": 4, "panatta": 4, "precor": 14, "nautilus": 13, "life-fitness": 5, "hammer-strength": 6}
    met, reasons = cse.overall_preconditions_met(counts)
    assert met is True
    assert reasons == []


def test_candidate_with_direct_corroboration_is_ineligible_while_pool_preconditions_unmet():
    # The fail-closed core of this module: real, independently-verified
    # direct corroboration for ONE candidate must not unlock eligibility on
    # its own while Technogym/Panatta are still at 0.
    artifact = cse.build_eligibility_artifact()
    assert artifact["overallPreconditionsMet"] is False
    matrix_entries_with_evidence = [
        e for e in artifact["entries"]
        if e["brandId"] == "matrix" and e["directCorroboration"] is not None
    ]
    assert len(matrix_entries_with_evidence) == 4
    for e in matrix_entries_with_evidence:
        assert e["canonicalSelectionEligible"] is False
        assert any("POOL_PRECONDITION_NOT_MET" in r for r in e["rejectionReasons"])


def test_no_candidate_is_eligible_today_given_real_unmet_preconditions():
    artifact = cse.build_eligibility_artifact()
    assert all(e["canonicalSelectionEligible"] is False for e in artifact["entries"])
    assert artifact["p1G5Status"] == "BLOCKED_ON_SOURCE_EVIDENCE"


def test_both_factors_are_actually_load_bearing_when_the_pool_gate_is_open(monkeypatch):
    # Reviewer-found gap (silent-failure-hunter, P1.G4-corroboration-pass
    # review, 2026-08-22): every other real-data test runs against today's
    # state where overall_preconditions_met() is always False, so a future
    # regression collapsing `eligible = has_direct and preconditions_met`
    # down to just `eligible = preconditions_met` would pass the entire
    # suite silently -- undetectable until the day the pool genuinely
    # clears 50, at which point every candidate (including ones with zero
    # real evidence) would incorrectly flip eligible in one commit. This
    # forces preconditions_met=True through the real build_eligibility_
    # artifact() pipeline and proves has_direct still gates the result.
    monkeypatch.setattr(cse, "overall_preconditions_met", lambda counts_by_brand: (True, []))
    artifact = cse.build_eligibility_artifact()
    assert artifact["overallPreconditionsMet"] is True

    with_evidence = [e for e in artifact["entries"] if e["directCorroboration"] is not None]
    without_evidence = [e for e in artifact["entries"] if e["directCorroboration"] is None]
    assert with_evidence, "fixture must contain at least one directly-corroborated candidate"
    assert without_evidence, "fixture must contain at least one candidate with no direct evidence"

    for e in with_evidence:
        assert e["canonicalSelectionEligible"] is True
        assert e["rejectionReasons"] == []
    for e in without_evidence:
        assert e["canonicalSelectionEligible"] is False
        assert "NO_DIRECT_FETCH_CORROBORATION" in e["rejectionReasons"]


def test_unmatched_fixture_entry_is_rejected_loudly_not_silently_dropped(monkeypatch, tmp_path):
    # Reviewer-found gap (silent-failure-hunter): a typo'd modelCode in the
    # hand-captured fixture previously just failed to match anything, with
    # no error and no visible trace -- only a quietly lower brand count.
    bad_fixture = tmp_path / "bad.json"
    bad_fixture.write_text(
        json.dumps({
            "sourceId": "matrix_johnsonfit_pdf_corroboration",  # real, registered -- isolates this test to the unmatched-key path
            "corroborations": [
                {"brandId": "matrix", "modelCode": "G7-S7O", "sourceUrl": "u",  # letter O, not zero -- real typo shape
                 "documentSha256": "a" * 64, "locator": "l"},
            ]
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(cse, "MATRIX_PDF_CORROBORATION_PATH", bad_fixture)
    with pytest.raises(cse.EligibilityError, match="match no real candidate"):
        cse.build_eligibility_artifact()


def test_fixture_entry_with_null_modelcode_is_rejected(monkeypatch, tmp_path):
    # Reviewer-found gap (silent-failure-hunter + python-reviewer,
    # combined): a None-keyed fixture entry would collide with any real
    # candidate that itself has no modelCode, silently misattributing
    # corroboration. Rejected outright rather than accepted as a wildcard.
    path = tmp_path / "null_model_code.json"
    path.write_text(
        json.dumps({
            "sourceId": "matrix_johnsonfit_pdf_corroboration",
            "corroborations": [{"brandId": "matrix", "modelCode": None, "sourceUrl": "u"}],
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(cse, "MATRIX_PDF_CORROBORATION_PATH", path)
    with pytest.raises(cse.EligibilityError, match="no modelCode"):
        cse.load_matrix_pdf_corroboration()


def test_original_direct_fetch_provenance_rejects_more_than_one_direct_fetch_record():
    # Reviewer-found gap (python-reviewer): asymmetric with the fixture
    # loader's own duplicate guard -- a candidate with two DIRECT_FETCH
    # provenance records must not be silently resolved by picking the first.
    candidate = _candidate(
        provenance=[
            {"sourceId": "a", "sourceUrl": "u1", "retrievalMethod": "DIRECT_FETCH"},
            {"sourceId": "b", "sourceUrl": "u2", "retrievalMethod": "DIRECT_FETCH"},
        ]
    )
    with pytest.raises(cse.EligibilityError, match="carries 2 DIRECT_FETCH"):
        cse._original_direct_fetch_provenance(candidate)


# --- scope boundary: never assigns primaryTypeId/modelId, never resolves conflicts ---


def test_artifact_never_claims_to_assign_identity_or_resolve_conflicts():
    artifact = cse.build_eligibility_artifact()
    assert artifact["assignsPrimaryTypeIdOrModelId"] is False
    assert artifact["resolvesConflicts"] is False


def test_no_entry_carries_a_primaryTypeId_or_modelId_field():
    artifact = cse.build_eligibility_artifact()
    for e in artifact["entries"]:
        assert "primaryTypeId" not in e
        assert "modelId" not in e


# --- structural / coverage correctness --------------------------------------


def test_every_real_candidate_appears_exactly_once():
    artifact = cse.build_eligibility_artifact()
    pool = cse.load_combined_pool()
    ids = [e["candidateId"] for e in artifact["entries"]]
    assert sorted(ids) == sorted(c["candidateId"] for c in pool)
    assert len(ids) == len(set(ids))


def test_direct_corroboration_for_prefers_original_provenance_over_pdf_pass():
    candidate = _candidate(
        brandId="matrix", modelCode="G7-S70",
        provenance=[{"sourceId": "s", "sourceUrl": "u", "retrievalMethod": "DIRECT_FETCH", "fixtureSha256": "b" * 64}],
    )
    matrix_pdf_corroboration = cse.load_matrix_pdf_corroboration()
    result = cse.direct_corroboration_for(candidate, matrix_pdf_corroboration)
    assert result["evidenceType"] == "ORIGINAL_ADAPTER_PROVENANCE"


def test_matrix_pdf_corroboration_fixture_has_no_duplicate_brand_model_pairs():
    # load_matrix_pdf_corroboration() itself raises on a real duplicate --
    # this just asserts it doesn't raise against the real committed fixture.
    result = cse.load_matrix_pdf_corroboration()
    assert len(result) == 4


def test_direct_corroboration_uses_the_fixtures_stable_source_id_not_the_url():
    # Reviewer-found bug (GPT-PM devil's-advocate review, 2026-08-22):
    # sourceId was previously set equal to sourceUrl, so it was never
    # actually a stable identifier and could not be told apart from the URL.
    candidate = _candidate(brandId="matrix", modelCode="G7-S70")
    result = cse.direct_corroboration_for(candidate, cse.load_matrix_pdf_corroboration())
    assert result["sourceId"] == "matrix_johnsonfit_pdf_corroboration"
    assert result["sourceId"] != result["sourceUrl"]


def test_unregistered_source_id_cannot_back_any_corroboration(monkeypatch, tmp_path):
    # Reviewer-found gap (GPT-PM devil's-advocate review, 2026-08-22):
    # nothing previously mechanically enforced that a corroboration
    # fixture's source was actually a registered, first-party manufacturer
    # source -- an arbitrary sourceId (a reseller, a scrape, anything) could
    # silently count toward a brand's floor. Now checked against the real
    # source_registry.json via rights.load_registry().
    path = tmp_path / "unregistered.json"
    path.write_text(
        json.dumps({
            "sourceId": "definitely_not_a_registered_source_id",
            "corroborations": [
                {"brandId": "matrix", "modelCode": "X", "sourceUrl": "u", "documentSha256": "a" * 64, "locator": "l"},
            ],
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(cse, "MATRIX_PDF_CORROBORATION_PATH", path)
    with pytest.raises(cse.EligibilityError, match="not a registered source"):
        cse.load_matrix_pdf_corroboration()


def test_non_official_manufacturer_source_cannot_back_corroboration(monkeypatch, tmp_path):
    # Same enforcement, the other failure mode: a real, registered source
    # that is NOT sourceClass=OFFICIAL_MANUFACTURER (e.g. a SEARCH_DISCOVERY
    # or REFURBISHED_USED entry) must not be able to back direct
    # corroboration either.
    registry = rights.load_registry()
    non_official = next((r for r in registry if r["sourceClass"] != "OFFICIAL_MANUFACTURER"), None)
    if non_official is None:
        pytest.skip("no non-OFFICIAL_MANUFACTURER source exists in the real registry to test against")
    path = tmp_path / "wrong_class.json"
    path.write_text(
        json.dumps({
            "sourceId": non_official["sourceId"],
            "corroborations": [
                {"brandId": "matrix", "modelCode": "X", "sourceUrl": "u", "documentSha256": "a" * 64, "locator": "l"},
            ],
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(cse, "MATRIX_PDF_CORROBORATION_PATH", path)
    with pytest.raises(cse.EligibilityError, match="not OFFICIAL_MANUFACTURER"):
        cse.load_matrix_pdf_corroboration()


def test_real_matrix_johnsonfit_source_is_registered_as_official_manufacturer():
    # The real, committed fixture's own source must pass the same check --
    # proves the registry entry this pass added is actually wired up.
    registry = rights.load_registry()
    entry = next(r for r in registry if r["sourceId"] == "matrix_johnsonfit_pdf_corroboration")
    assert entry["sourceClass"] == "OFFICIAL_MANUFACTURER"
    # And building the real artifact must not raise.
    cse.build_eligibility_artifact()


def test_duplicate_model_key_across_two_candidates_is_rejected_not_double_counted():
    # Reviewer-found gap (GPT-PM devil's-advocate review, 2026-08-22): the
    # precondition counts distinct corroborated MODELS, not candidate rows
    # -- two rows for the same (brandId, modelCode) must not silently
    # inflate a brand's floor or the total.
    a = _candidate(
        brandId="precor", modelCode="RSL0602", candidateId="dup-a",
        provenance=[{"sourceId": "s", "sourceUrl": "u", "retrievalMethod": "DIRECT_FETCH"}],
    )
    b = _candidate(
        brandId="precor", modelCode="RSL0602", candidateId="dup-b",
        provenance=[{"sourceId": "s", "sourceUrl": "u", "retrievalMethod": "DIRECT_FETCH"}],
    )
    with pytest.raises(cse.EligibilityError, match="duplicate \\(brandId, modelCode\\)"):
        cse.direct_corroboration_counts_by_brand([a, b], {})


def test_matrix_pdf_corroboration_sha256_values_are_well_formed():
    result = cse.load_matrix_pdf_corroboration()
    for entry in result.values():
        assert len(entry["documentSha256"]) == 64
        assert all(c in "0123456789abcdef" for c in entry["documentSha256"])


def test_load_matrix_pdf_corroboration_rejects_a_duplicate_entry(tmp_path, monkeypatch):
    dup_path = tmp_path / "dup.json"
    dup_path.write_text(
        json.dumps({
            "sourceId": "matrix_johnsonfit_pdf_corroboration",
            "corroborations": [
                {"brandId": "matrix", "modelCode": "X", "sourceUrl": "u1", "documentSha256": "a" * 64, "locator": "l1"},
                {"brandId": "matrix", "modelCode": "X", "sourceUrl": "u2", "documentSha256": "b" * 64, "locator": "l2"},
            ]
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(cse, "MATRIX_PDF_CORROBORATION_PATH", dup_path)
    with pytest.raises(cse.EligibilityError, match="duplicate corroboration"):
        cse.load_matrix_pdf_corroboration()


# --- determinism + generated-file integrity ---------------------------------


def test_build_eligibility_artifact_is_deterministic():
    a = cse.build_eligibility_artifact()
    b = cse.build_eligibility_artifact()
    assert a == b


def test_generated_artifact_file_matches_a_fresh_build():
    on_disk = json.loads(cse.ELIGIBILITY_ARTIFACT_PATH.read_text(encoding="utf-8"))
    fresh = cse.build_eligibility_artifact()
    assert on_disk == fresh


def test_generated_artifact_written_through_canonical_json():
    on_disk_text = cse.ELIGIBILITY_ARTIFACT_PATH.read_text(encoding="utf-8")
    assert on_disk_text == cse.canonical_json.dump_pretty(cse.build_eligibility_artifact())
