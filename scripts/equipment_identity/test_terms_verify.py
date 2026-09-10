# -*- coding: utf-8 -*-
"""B1 step 14 tests for scripts/equipment_identity/terms_verify.py.

    python -m pytest scripts/equipment_identity/test_terms_verify.py -q
"""
from __future__ import annotations

import datetime as dt
import json
import socket
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_terms as ct  # noqa: E402
import rights  # noqa: E402
import terms_verify as tv  # noqa: E402
from test_from_file import (  # noqa: E402
    SOURCE, DOC, URL, CLOCK, HTML,
    acq_basis, ret_basis, bases, manifest, source_registry,
)


def call_from_file(tmp_path, **overrides):
    from test_from_file import call
    return call(tmp_path, **overrides)


@pytest.fixture
def namespace(tmp_path, monkeypatch):
    root = tmp_path / "captures"
    root.mkdir()
    monkeypatch.setattr(ct, "CAPTURES_ROOT", root)
    monkeypatch.setattr(tv, "CAPTURES_ROOT", root)
    return root


# ==========================================================================
# The real, committed namespace.
# ==========================================================================

def test_verify_all_passes_on_the_real_committed_namespace():
    report = tv.verify_all()
    assert report.count == 0


def test_verify_all_never_touches_the_pre_existing_g3_fixture():
    """The reason this module has a namespace at all."""
    fixture = rights.TERMS_SNAPSHOT_ROOT / "synthetic_test_terms.txt"
    assert fixture.is_file()
    before = fixture.read_bytes()
    tv.verify_all()
    assert fixture.read_bytes() == before


def test_verify_all_opens_no_socket(monkeypatch, namespace, tmp_path):
    """OFFLINE, proven rather than claimed.

    A real published capture is on disk first, so this actually exercises the
    resolve_basis lookup path, not just an empty-directory no-op.
    """
    call_from_file(tmp_path)

    def refuse_socket(*args, **kwargs):
        raise AssertionError("verify_all must not open a socket")

    monkeypatch.setattr(socket, "socket", refuse_socket)
    report = tv.verify_all(basis_registry=bases())
    assert report.count == 1


# ==========================================================================
# A real published capture, verified end to end.
# ==========================================================================

def test_a_freshly_published_manual_capture_verifies(namespace, tmp_path):
    call_from_file(tmp_path)
    report = tv.verify_all(basis_registry=bases())
    assert report.count == 1
    assert report.captures[0].source_id == SOURCE
    assert report.captures[0].candidate_doc_id == DOC


def test_two_captures_of_one_candidate_at_different_instants_both_verify(namespace, tmp_path):
    """The D2 cardinality: many captures per candidate."""
    call_from_file(tmp_path, clock=lambda: dt.datetime(2026, 9, 10, 14, 22, 33, tzinfo=dt.timezone.utc))
    call_from_file(tmp_path, clock=lambda: dt.datetime(2026, 9, 11, 9, 0, 0, tzinfo=dt.timezone.utc))
    report = tv.verify_all(basis_registry=bases())
    assert report.count == 2
    assert {c.capture_id for c in report.captures} == {"20260910T142233Z", "20260911T090000Z"}


def test_two_candidates_under_one_source_both_verify(namespace, tmp_path):
    """The D2 cardinality: many candidates per source."""
    second_manifest = manifest()
    second_manifest["sources"][0]["candidates"].append({
        "candidateDocId": "legal_terms_conditions",
        "documentUrls": ["https://www.lifefitness.com/en-us/legal/terms-conditions"],
        "allowedFinalUrls": ["https://www.lifefitness.com/en-us/legal/terms-conditions"],
        "declaredMediaTypes": ["text/html"],
        "observationState": "OBSERVED",
        "observedAtUtc": "2026-09-10T00:00:00Z",
        "observationMethod": "WEB_FETCH_MARKDOWN_EXTRACTION",
        "identityExpectations": {"requiredMarkers": ["Intellectual Property"]},
    })
    wide_scope = {
        "sourceIds": [SOURCE],
        "candidateDocIds": [DOC, "legal_terms_conditions"],
        "acquisitionMethods": [ct.HUMAN_MANUAL_RETRIEVAL],
    }
    wide_bases = bases(acq_basis(scope=wide_scope), ret_basis(scope=wide_scope))
    call_from_file(tmp_path, basis_registry=wide_bases)
    call_from_file(
        tmp_path,
        candidate_doc_id="legal_terms_conditions",
        asserted_document_url="https://www.lifefitness.com/en-us/legal/terms-conditions",
        manifest=second_manifest,
        document=b"<!doctype html><html>Intellectual Property notice here.</html>",
        basis_registry=wide_bases,
    )
    report = tv.verify_all(basis_registry=wide_bases)
    assert {c.candidate_doc_id for c in report.captures} == {DOC, "legal_terms_conditions"}


# ==========================================================================
# Refusals.
# ==========================================================================

def test_a_sha_mismatch_is_detected(namespace, tmp_path):
    target = call_from_file(tmp_path)
    (target / "document.html").write_bytes(b"tampered bytes")
    with pytest.raises(tv.VerificationError, match="no longer match"):
        tv.verify_all(basis_registry=bases())


def test_a_byte_length_mismatch_with_a_correct_hash_is_detected(namespace, tmp_path):
    """The sha256 check alone cannot prove this: only a wrong DECLARED length,
    with the document bytes and their real hash both left untouched, isolates
    the byteLength check from the sha256 check above it."""
    target = call_from_file(tmp_path)
    sidecar_path = target / "provenance.json"
    sidecar = json.loads(sidecar_path.read_bytes())
    sidecar["byteLength"] = sidecar["byteLength"] + 1
    sidecar_path.write_bytes(json.dumps(sidecar).encode("utf-8"))
    with pytest.raises(tv.VerificationError, match="sidecar records"):
        tv.verify_all(basis_registry=bases())


def test_a_malformed_json_sidecar_is_detected(namespace, tmp_path):
    target = call_from_file(tmp_path)
    (target / "provenance.json").write_bytes(b"{not valid json")
    with pytest.raises(tv.VerificationError, match="not valid UTF-8 JSON"):
        tv.verify_all(basis_registry=bases())


def test_a_revoked_retention_basis_specifically_is_detected(namespace, tmp_path):
    """The acquisition-only revocation test (below) can only ever exercise the
    FIRST of the two resolve_basis calls -- an empty registry raises on
    acquisitionBasisRef before retentionBasisRef is ever reached. This fixture
    keeps acquisition resolvable and removes only the retention basis, so the
    second check is proven on its own."""
    call_from_file(tmp_path)
    with pytest.raises(tv.VerificationError, match="no longer resolves"):
        tv.verify_all(basis_registry=bases(acq_basis()))


def test_an_orphan_file_directly_in_the_namespace_is_detected(namespace, tmp_path):
    call_from_file(tmp_path)
    (namespace / "stray.txt").write_bytes(b"not a capture")
    with pytest.raises(tv.VerificationError, match="orphan"):
        tv.verify_all(basis_registry=bases())


def test_a_file_masquerading_as_a_well_formed_capture_directory_is_detected(namespace, tmp_path):
    """`stray.txt` above never isolates the is_dir() check: its name ALSO fails
    `_parse_capture_directory_name`, so either guard catches it and both report
    "orphan". This fixture's name parses as a genuinely valid capture identity,
    so only the is_dir() check -- not the name parse -- can reject it."""
    call_from_file(tmp_path)
    well_formed_name = f"{SOURCE}__{DOC}__20270101T000000Z"
    (namespace / well_formed_name).write_bytes(b"not a directory")
    with pytest.raises(tv.VerificationError, match="is a file directly"):
        tv.verify_all(basis_registry=bases())


def test_an_orphan_directory_with_an_unparseable_name_is_detected(namespace, tmp_path):
    call_from_file(tmp_path)
    bogus = namespace / "not_a_valid_capture_name"
    bogus.mkdir()
    (bogus / "document.html").write_bytes(b"x")
    (bogus / "provenance.json").write_bytes(b"{}")
    with pytest.raises(tv.VerificationError, match="not a valid capture directory name"):
        tv.verify_all(basis_registry=bases())


def test_an_incomplete_capture_directory_is_detected(namespace, tmp_path):
    target = call_from_file(tmp_path)
    (target / "provenance.json").unlink()
    with pytest.raises(tv.VerificationError, match="expected exactly one"):
        tv.verify_all(basis_registry=bases())


def test_staging_debris_left_in_the_namespace_is_detected(namespace, tmp_path):
    call_from_file(tmp_path)
    (namespace / ".staging__leftover").mkdir()
    with pytest.raises(tv.VerificationError, match="staging debris"):
        tv.verify_all(basis_registry=bases())


def test_a_directory_renamed_after_publication_is_detected(namespace, tmp_path):
    """Cross-bound: the directory name and the sidecar must agree."""
    target = call_from_file(tmp_path)
    renamed = target.parent / (
        SOURCE + "__" + DOC + "__20261231T235959Z"
    )
    target.rename(renamed)
    with pytest.raises(tv.VerificationError, match="disagree"):
        tv.verify_all(basis_registry=bases())


def test_a_sidecar_edited_to_claim_another_source_is_detected(namespace, tmp_path):
    target = call_from_file(tmp_path)
    sidecar_path = target / "provenance.json"
    sidecar = json.loads(sidecar_path.read_bytes())
    sidecar["sourceId"] = "core_health_fitness_nautilus_product_catalog"
    sidecar_path.write_bytes(json.dumps(sidecar).encode("utf-8"))
    with pytest.raises(tv.VerificationError, match="disagree"):
        tv.verify_all(basis_registry=bases())


def test_a_sidecar_edited_to_claim_another_candidate_is_detected(namespace, tmp_path):
    """The sourceId fixture above and the captureId fixture (renamed directory)
    each isolate one cross-bound field; this isolates candidateDocId the same
    way, so a mutant narrowing the loop to only those two fields still dies."""
    target = call_from_file(tmp_path)
    sidecar_path = target / "provenance.json"
    sidecar = json.loads(sidecar_path.read_bytes())
    sidecar["candidateDocId"] = "legal_terms_conditions"
    sidecar_path.write_bytes(json.dumps(sidecar).encode("utf-8"))
    with pytest.raises(tv.VerificationError, match="disagree"):
        tv.verify_all(basis_registry=bases())


def test_an_impossible_method_field_combination_is_detected_in_both_directions(
    namespace, tmp_path
):
    """`validate_sidecar` is reused here, not reimplemented -- one rule, one place."""
    target = call_from_file(tmp_path)
    sidecar_path = target / "provenance.json"
    sidecar = json.loads(sidecar_path.read_bytes())
    sidecar["redirectChainObserved"] = []
    sidecar_path.write_bytes(json.dumps(sidecar).encode("utf-8"))
    with pytest.raises(tv.VerificationError, match="opens no connection"):
        tv.verify_all(basis_registry=bases())


def test_a_reference_that_no_longer_resolves_is_detected(namespace, tmp_path):
    """A basis can be revoked after a capture was published -- verify catches it live."""
    call_from_file(tmp_path)
    with pytest.raises(tv.VerificationError, match="no longer resolves"):
        tv.verify_all(basis_registry={"bases": []})


def test_a_duplicate_capture_identity_across_two_directories_is_detected(namespace, tmp_path):
    """Directory names cannot literally collide -- so this simulates the sidecar disagreeing."""
    first = call_from_file(tmp_path)
    second_dir = first.parent / (SOURCE + "__" + DOC + "__20270101T000000Z")
    second_dir.mkdir()
    sidecar = json.loads((first / "provenance.json").read_bytes())
    sidecar["captureId"] = first.name[-16:]  # claim the FIRST capture's identity
    sidecar["capturedAtUtc"] = json.loads((first / "provenance.json").read_bytes())["capturedAtUtc"]
    (second_dir / "document.html").write_bytes((first / "document.html").read_bytes())
    (second_dir / "provenance.json").write_bytes(json.dumps(sidecar).encode("utf-8"))
    with pytest.raises(tv.VerificationError, match="disagree"):
        # The directory name (ending in ...20270101T000000Z) disagrees with the
        # sidecar's captureId (the first capture's) BEFORE the duplicate check
        # is even reached -- cross-bound catches it first, which is the
        # correct order: a sidecar cannot claim an identity its own directory
        # does not name.
        tv.verify_all(basis_registry=bases())


# ==========================================================================
# Directory-name parsing in isolation.
# ==========================================================================

def test_parses_a_well_formed_name():
    assert tv._parse_capture_directory_name(
        f"{SOURCE}__{DOC}__20260910T142233Z"
    ) == (SOURCE, DOC)


def test_refuses_an_unknown_source_prefix():
    assert tv._parse_capture_directory_name(
        "acme_fitness_catalog__terms_of_use__20260910T142233Z"
    ) is None


def test_refuses_a_malformed_capture_id_suffix():
    assert tv._parse_capture_directory_name(f"{SOURCE}__{DOC}__not-a-timestamp") is None


def test_refuses_a_name_with_no_double_underscore_before_the_capture_id():
    assert tv._parse_capture_directory_name(f"{SOURCE}_{DOC}_20260910T142233Z") is None


def test_a_candidate_doc_id_containing_a_double_underscore_still_parses():
    """The reason this isn't a naive split(\"__\").

    The grammar permits consecutive underscores inside candidateDocId; the
    parser must still find the right boundary.
    """
    name = f"{SOURCE}__terms__and__conditions__20260910T142233Z"
    assert tv._parse_capture_directory_name(name) == (SOURCE, "terms__and__conditions")
