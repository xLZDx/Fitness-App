# -*- coding: utf-8 -*-
"""B1 step 11 tests for `capture_terms.register_from_file`.

    python -m pytest scripts/equipment_identity/test_from_file.py -q

Ten named refusals from the plan, plus F3's own fixture (correct everything,
wrong bytes) and one control that actually publishes -- because a function that
refuses everything proves nothing about what it is supposed to accept.
"""
from __future__ import annotations

import datetime as dt
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_terms as ct  # noqa: E402

SOURCE = "life_fitness_hammer_strength_product_catalog"
DOC = "terms_of_use"
URL = "https://www.lifefitness.com/en-us/terms-of-use"
CLOCK = lambda: dt.datetime(2026, 9, 10, 14, 22, 33, tzinfo=dt.timezone.utc)  # noqa: E731

HTML = (
    b"<!doctype html><html><body>"
    b"<h2>Use of the Site and Standards of Conduct</h2>"
    b"<h2>Intellectual Property</h2>"
    b"<p>unauthorised robot spider scraper</p>"
    b"</body></html>"
)
WRONG_HTML = b"<!doctype html><html><body>Completely unrelated page.</body></html>"


def source_registry() -> dict:
    return {"sources": [
        {"sourceId": SOURCE},
        {"sourceId": "wger_project"},
    ]}


def manifest() -> dict:
    return {
        "manifestKind": "TERMS_CANDIDATE_DOCUMENTS",
        "sources": [{
            "sourceId": SOURCE,
            "candidates": [{
                "candidateDocId": DOC,
                "documentUrls": [URL],
                "allowedFinalUrls": [URL],
                "declaredMediaTypes": ["text/html"],
                "observationState": "OBSERVED",
                "observedAtUtc": "2026-09-10T00:00:00Z",
                "observationMethod": "WEB_FETCH_MARKDOWN_EXTRACTION",
                "identityExpectations": {
                    "requiredMarkers": [
                        "Use of the Site and Standards of Conduct",
                        "Intellectual Property",
                        "unauthorised",
                    ],
                },
            }],
            "noCandidatesReason": None,
        }],
    }


def unobserved_manifest() -> dict:
    doc = manifest()
    doc["sources"][0]["candidates"][0]["observationState"] = "NOT_OBSERVED"
    del doc["sources"][0]["candidates"][0]["identityExpectations"]
    del doc["sources"][0]["candidates"][0]["observedAtUtc"]
    del doc["sources"][0]["candidates"][0]["observationMethod"]
    return doc


def acq_basis(**overrides) -> dict:
    base = {
        "basisRef": "acq-basis",
        "capabilities": ["ACQUISITION"],
        "scope": {
            "sourceIds": [SOURCE], "candidateDocIds": [DOC],
            "acquisitionMethods": [ct.HUMAN_MANUAL_RETRIEVAL],
        },
    }
    base.update(overrides)
    return base


def ret_basis(**overrides) -> dict:
    base = {
        "basisRef": "ret-basis",
        "capabilities": ["RETENTION"],
        "scope": {
            "sourceIds": [SOURCE], "candidateDocIds": [DOC],
            "acquisitionMethods": [ct.HUMAN_MANUAL_RETRIEVAL],
        },
    }
    base.update(overrides)
    return base


def bases(*records) -> dict:
    return {"bases": list(records) if records else [acq_basis(), ret_basis()]}


def call(tmp_path, *, document=HTML, namespace_root=None, **overrides):
    doc_path = tmp_path / "input.html"
    doc_path.write_bytes(document)
    args = dict(
        source_id=SOURCE,
        candidate_doc_id=DOC,
        document_path=doc_path,
        acquisition_basis_ref="acq-basis",
        retention_basis_ref="ret-basis",
        actor="operator",
        attestation_ref="attest-001",
        asserted_document_url=URL,
        clock=CLOCK,
        manifest=manifest(),
        basis_registry=bases(),
        source_registry=source_registry(),
    )
    args.update(overrides)
    return ct.register_from_file(**args)


@pytest.fixture
def namespace(tmp_path, monkeypatch):
    root = tmp_path / "captures"
    root.mkdir()
    monkeypatch.setattr(ct, "CAPTURES_ROOT", root)
    return root


# --------------------------------------------------------------------------
# The control.
# --------------------------------------------------------------------------

def test_a_fully_correct_registration_publishes(namespace, tmp_path):
    target = call(tmp_path)
    assert target.parent == namespace
    assert (target / "document.html").read_bytes() == HTML
    sidecar = (target / ct.SIDECAR_NAME).read_bytes()
    assert b"assertedDocumentUrl" in sidecar
    assert b"requestedUrlObserved" not in sidecar
    assert list(namespace.iterdir()) == [target]


# --------------------------------------------------------------------------
# Ten named refusals. Each must publish NOTHING.
# --------------------------------------------------------------------------

@pytest.mark.parametrize("field", [
    "source_id", "candidate_doc_id", "acquisition_basis_ref",
    "retention_basis_ref", "actor", "attestation_ref", "asserted_document_url",
])
def test_1_missing_required_field_publishes_nothing(namespace, tmp_path, field):
    with pytest.raises(ct.CaptureError, match="requires"):
        call(tmp_path, **{field: ""})
    assert list(namespace.iterdir()) == []


def test_2_unresolvable_acquisition_basis_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.AuthorityError, match="resolves to nothing"):
        call(tmp_path, basis_registry=bases(ret_basis()))
    assert list(namespace.iterdir()) == []


def test_3_unresolvable_retention_basis_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.AuthorityError, match="resolves to nothing"):
        call(tmp_path, basis_registry=bases(acq_basis()))
    assert list(namespace.iterdir()) == []


def test_4_acquisition_only_basis_used_as_retention_publishes_nothing(namespace, tmp_path):
    """The E1 headline for the manual path."""
    same_ref = acq_basis(basisRef="shared")
    with pytest.raises(ct.AuthorityError, match="neither implies the other"):
        call(
            tmp_path,
            acquisition_basis_ref="shared", retention_basis_ref="shared",
            basis_registry=bases(same_ref),
        )
    assert list(namespace.iterdir()) == []


def test_5_basis_scoped_to_another_candidate_publishes_nothing(namespace, tmp_path):
    wrong_scope = acq_basis(scope={
        "sourceIds": [SOURCE], "candidateDocIds": ["legal_terms_conditions"],
        "acquisitionMethods": [ct.HUMAN_MANUAL_RETRIEVAL],
    })
    with pytest.raises(ct.AuthorityError, match="does not cover"):
        call(tmp_path, basis_registry=bases(wrong_scope, ret_basis()))
    assert list(namespace.iterdir()) == []


def test_6_basis_scoped_to_another_source_publishes_nothing(namespace, tmp_path):
    wrong_scope = acq_basis(scope={
        "sourceIds": ["core_health_fitness_nautilus_product_catalog"],
        "candidateDocIds": [DOC], "acquisitionMethods": [ct.HUMAN_MANUAL_RETRIEVAL],
    })
    with pytest.raises(ct.AuthorityError, match="does not cover"):
        call(tmp_path, basis_registry=bases(wrong_scope, ret_basis()))
    assert list(namespace.iterdir()) == []


def test_7_missing_retention_basis_ref_with_valid_acquisition_publishes_nothing(
    namespace, tmp_path
):
    with pytest.raises(ct.CaptureError, match="requires retentionBasisRef"):
        call(tmp_path, retention_basis_ref="")
    assert list(namespace.iterdir()) == []


def test_8_missing_attestation_ref_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.CaptureError, match="requires attestationRef"):
        call(tmp_path, attestation_ref="")
    assert list(namespace.iterdir()) == []


def test_9_url_the_manifest_does_not_own_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.CaptureError, match="not a URL this manifest owns"):
        call(tmp_path, asserted_document_url="https://www.lifefitness.com/en-us/legal/terms-conditions")
    assert list(namespace.iterdir()) == []


def test_10_media_type_the_candidate_does_not_declare_publishes_nothing(namespace, tmp_path):
    pdf_manifest = manifest()
    pdf_manifest["sources"][0]["candidates"][0]["declaredMediaTypes"] = ["application/pdf"]
    with pytest.raises(ct.CaptureError, match="does not declare"):
        call(tmp_path, manifest=pdf_manifest)
    assert list(namespace.iterdir()) == []


def test_11_correct_everything_wrong_bytes_publishes_nothing(namespace, tmp_path):
    """F3's own fixture: the finding this step exists to close.

    Correct source, correct candidate, correct bases, correct asserted URL --
    and the wrong document. Provenance would be internally consistent while
    being bound to the wrong thing, which a redirect would expose online and
    nothing exposes offline except this check.
    """
    with pytest.raises(ct.CaptureError, match="not the document the manifest registered"):
        call(tmp_path, document=WRONG_HTML)
    assert list(namespace.iterdir()) == []


# --------------------------------------------------------------------------
# Supporting refusals: identity resolution and the NOT_OBSERVED guard.
# --------------------------------------------------------------------------

def test_a_nonexistent_source_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.AuthorityError, match="matches no record"):
        call(tmp_path, source_id="acme_fitness_catalog")
    assert list(namespace.iterdir()) == []


def test_a_real_but_non_target_source_publishes_nothing(namespace, tmp_path):
    with pytest.raises(ct.AuthorityError, match="not a B1 target"):
        call(tmp_path, source_id="wger_project")
    assert list(namespace.iterdir()) == []


def test_a_candidate_the_manifest_never_registered_publishes_nothing(namespace, tmp_path):
    """E2's headline, on the file path specifically."""
    with pytest.raises(ct.CandidateManifestError, match="never registered"):
        call(tmp_path, candidate_doc_id="invented_page")
    assert list(namespace.iterdir()) == []


def test_a_not_observed_candidate_publishes_nothing(namespace, tmp_path):
    """The manifest owns no expectations for it, so checking would be vacuous."""
    with pytest.raises(ct.CaptureError, match="NOT_OBSERVED"):
        call(tmp_path, manifest=unobserved_manifest())
    assert list(namespace.iterdir()) == []


def test_an_unreadable_file_is_reported_rather_than_crashing(namespace, tmp_path):
    with pytest.raises(ct.CaptureError, match="could not read"):
        call(tmp_path, document_path=tmp_path / "does_not_exist.html")
    assert list(namespace.iterdir()) == []


def test_an_existing_capture_is_refused_never_overwritten(namespace, tmp_path):
    first = call(tmp_path)
    original = (first / "document.html").read_bytes()
    with pytest.raises(ct.CaptureError, match="already exists"):
        call(tmp_path)
    assert (first / "document.html").read_bytes() == original
    assert list(namespace.iterdir()) == [first]


def test_a_failure_before_publish_leaves_no_staging_debris(namespace, tmp_path):
    def explode():
        raise RuntimeError("disk fell over")

    with pytest.raises(RuntimeError, match="disk fell over"):
        call(tmp_path, on_before_publish=explode)
    assert list(namespace.iterdir()) == []


# --------------------------------------------------------------------------
# `derive_media_type` in isolation, since it is load-bearing on its own.
# --------------------------------------------------------------------------

def test_media_type_is_derived_from_bytes_not_the_extension():
    assert ct.derive_media_type(HTML) == "text/html"
    assert ct.derive_media_type(b"%PDF-1.4\n...") == "application/pdf"


def test_unrecognisable_bytes_refuse_rather_than_guess():
    with pytest.raises(ct.CaptureError, match="could not determine"):
        ct.derive_media_type(b"\x00\x01\x02not a document")


def test_empty_bytes_refuse():
    with pytest.raises(ct.CaptureError, match="empty"):
        ct.derive_media_type(b"")


def test_html_wrapped_in_leading_comment_and_prolog_is_still_recognised():
    wrapped = b"<!-- generated -->\n<!doctype html><html></html>"
    assert ct.derive_media_type(wrapped) == "text/html"


def test_the_word_html_appearing_in_prose_is_not_mistaken_for_a_tag():
    plain_text = b"This document discusses html and other formats at length."
    with pytest.raises(ct.CaptureError, match="could not determine"):
        ct.derive_media_type(plain_text)


# --------------------------------------------------------------------------
# `check_identity_expectations` in isolation.
# --------------------------------------------------------------------------

def test_identity_check_passes_when_every_marker_is_present():
    ct.check_identity_expectations(HTML, {"requiredMarkers": ["Intellectual Property"]})


def test_identity_check_reports_which_markers_are_missing():
    with pytest.raises(ct.CaptureError, match="Nonexistent Marker"):
        ct.check_identity_expectations(HTML, {"requiredMarkers": ["Nonexistent Marker"]})


def test_identity_check_refuses_an_empty_marker_set():
    with pytest.raises(ct.CaptureError, match="vacuously true"):
        ct.check_identity_expectations(HTML, {"requiredMarkers": []})
