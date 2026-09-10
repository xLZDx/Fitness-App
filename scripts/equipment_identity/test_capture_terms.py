# -*- coding: utf-8 -*-
"""B1 steps 8, 9 and 10 tests for scripts/equipment_identity/capture_terms.py.

    python -m pytest scripts/equipment_identity/test_capture_terms.py -q
"""
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_terms as ct  # noqa: E402
import rights  # noqa: E402

MOMENT = dt.datetime(2026, 9, 10, 14, 22, 33, tzinfo=dt.timezone.utc)
CAPTURE_ID = "20260910T142233Z"
STAMP = "2026-09-10T14:22:33Z"
PAYLOAD = b"<html><body>PROHIBITED ACTIVITIES</body></html>"

SOURCE = "life_fitness_hammer_strength_product_catalog"
DOC = "terms_of_use"


@pytest.fixture
def namespace(tmp_path, monkeypatch):
    """Redirect the capture namespace into tmp_path.

    The production root is exercised separately by
    `test_the_production_namespace_sits_under_the_snapshot_root`, so redirecting
    here does not leave the real path a phantom nothing traverses.
    """
    root = tmp_path / "captures"
    root.mkdir()
    monkeypatch.setattr(ct, "CAPTURES_ROOT", root)
    return root


def staging_dir(tmp_path, *, document=True, sidecar=True, ext="html"):
    staging = tmp_path / "staging"
    staging.mkdir()
    if document:
        (staging / f"{ct.DOCUMENT_STEM}.{ext}").write_bytes(PAYLOAD)
    if sidecar:
        (staging / ct.SIDECAR_NAME).write_bytes(b"{}")
    return staging


def manual_fields() -> dict:
    return {
        "assertedDocumentUrl": "https://www.lifefitness.com/en-us/terms-of-use",
        "actor": "operator",
        "attestationRef": "attest-001",
    }


def observed_fields() -> dict:
    return {
        "requestedUrlObserved": "https://127.0.0.1:8443/terms",
        "redirectChainObserved": [],
        "finalUrlObserved": "https://127.0.0.1:8443/terms",
    }


def sidecar(method=ct.HUMAN_MANUAL_RETRIEVAL, **overrides) -> dict:
    built = ct.build_sidecar(
        source_id=SOURCE,
        candidate_doc_id=DOC,
        capture_id=CAPTURE_ID,
        acquisition_method=method,
        acquisition_basis_ref="basis-acq",
        retention_basis_ref="basis-ret",
        media_type="text/html",
        payload=PAYLOAD,
        timestamp=STAMP,
        asserted=manual_fields() if method == ct.HUMAN_MANUAL_RETRIEVAL else None,
        observed=observed_fields() if method == ct.AUTOMATED_FETCH else None,
    )
    built.update(overrides)
    return built


# ==========================================================================
# STEP 8 -- capture identity is a reading of a clock, not a shape.
# ==========================================================================

def test_a_capture_id_round_trips_to_the_instant_it_came_from():
    assert ct.format_capture_id(MOMENT) == CAPTURE_ID
    assert ct.parse_capture_id(CAPTURE_ID) == MOMENT


def test_an_impossible_date_dies_on_the_parse():
    """GPT-PM's own example. A grammar of ^[0-9]{8}T[0-9]{6}Z$ accepts it."""
    with pytest.raises(ct.CaptureError, match="not a real UTC instant"):
        ct.parse_capture_id("20261399T996099Z")


@pytest.mark.parametrize("value", [
    "20260230T120000Z",   # 30 February
    "20260910T250000Z",   # hour 25
    "20260910T146000Z",   # minute 60
    "20260000T120000Z",   # month 0
    "2026091T142233Z",    # too short
    "20260910T142233",    # no Z
    "20260910t142233z",   # lowercase
    "",
])
def test_these_are_not_instants(value):
    with pytest.raises(ct.CaptureError):
        ct.parse_capture_id(value)


def test_a_naive_datetime_is_refused():
    with pytest.raises(ct.CaptureError, match="timezone-aware"):
        ct.format_capture_id(dt.datetime(2026, 9, 10, 14, 22, 33))


def test_a_non_utc_instant_is_normalised_rather_than_relabelled():
    plus_two = dt.timezone(dt.timedelta(hours=2))
    same_instant = dt.datetime(2026, 9, 10, 16, 22, 33, tzinfo=plus_two)
    assert ct.format_capture_id(same_instant) == CAPTURE_ID


def test_microseconds_do_not_leak_into_the_identity():
    assert ct.format_capture_id(MOMENT.replace(microsecond=999999)) == CAPTURE_ID


def test_the_capture_id_and_the_sidecar_stamp_must_denote_one_instant():
    assert ct.capture_id_matches_timestamp(CAPTURE_ID, STAMP)
    assert ct.capture_id_matches_timestamp(CAPTURE_ID, "2026-09-10T14:22:33+00:00")
    assert not ct.capture_id_matches_timestamp(CAPTURE_ID, "2026-09-10T14:22:34Z")
    assert not ct.capture_id_matches_timestamp(CAPTURE_ID, "2026-09-11T14:22:33Z")


def test_a_stamp_with_no_zone_does_not_match_anything():
    assert not ct.capture_id_matches_timestamp(CAPTURE_ID, "2026-09-10T14:22:33")


def test_the_production_clock_returns_an_aware_utc_instant():
    now = ct.utc_now()
    assert now.tzinfo is not None
    assert ct.format_capture_id(now)


# ==========================================================================
# STEP 9 -- one rename, or nothing.
# ==========================================================================

def test_a_prepared_staging_directory_publishes_whole(namespace, tmp_path):
    staging = staging_dir(tmp_path)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    ct.publish_capture(staging, target)

    assert (target / "document.html").read_bytes() == PAYLOAD
    assert (target / ct.SIDECAR_NAME).is_file()
    assert not staging.exists(), "the staging directory moved, it was not copied"


def test_a_failure_immediately_before_the_rename_leaves_nothing(namespace, tmp_path):
    """The atomicity claim, asserted by LISTING the tree rather than by trusting the flow."""
    staging = staging_dir(tmp_path)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)

    def explode():
        raise RuntimeError("disk fell over")

    with pytest.raises(RuntimeError, match="disk fell over"):
        ct.publish_capture(staging, target, on_before_publish=explode)

    assert list(namespace.iterdir()) == [], "no half-published capture may remain"
    assert not target.exists()
    assert not staging.exists(), "no staging debris may remain either"


def test_the_bounded_retry_succeeds_after_transient_failures(namespace, tmp_path, monkeypatch):
    """A transient winerror 5/32 from an indexer/AV handle is retried, not
    fatal on the first hit -- see `_replace_with_bounded_retry`'s own docstring
    for why this is retried rather than treated as a real failure."""
    staging = staging_dir(tmp_path)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    real_replace = ct.os.replace
    calls = {"n": 0}

    def flaky_replace(src, dst):
        calls["n"] += 1
        if calls["n"] < 3:
            raise OSError("transient handle")
        return real_replace(src, dst)

    monkeypatch.setattr(ct.os, "replace", flaky_replace)
    monkeypatch.setattr(ct.time, "sleep", lambda seconds: None)
    ct.publish_capture(staging, target)
    assert calls["n"] == 3
    assert (target / "document.html").read_bytes() == PAYLOAD


def test_the_bounded_retry_gives_up_after_persistent_failure(namespace, tmp_path, monkeypatch):
    """Retrying is honest; catching the error and reporting success would not
    be -- a persistent failure must still surface as CaptureError, with the
    capture NOT published and staging cleaned up."""
    staging = staging_dir(tmp_path)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)

    def always_fails(src, dst):
        raise OSError("handle never releases")

    monkeypatch.setattr(ct.os, "replace", always_fails)
    monkeypatch.setattr(ct.time, "sleep", lambda seconds: None)
    with pytest.raises(ct.CaptureError, match="could not publish"):
        ct.publish_capture(staging, target)
    assert not target.exists()
    assert not staging.exists(), "staging is removed even when publication never succeeds"


def test_an_existing_capture_is_refused_never_overwritten(namespace, tmp_path):
    first = staging_dir(tmp_path)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    ct.publish_capture(first, target)
    original = (target / "document.html").read_bytes()

    second = tmp_path / "staging2"
    second.mkdir()
    (second / "document.html").write_bytes(b"different bytes")
    (second / ct.SIDECAR_NAME).write_bytes(b"{}")

    with pytest.raises(ct.CaptureError, match="already exists"):
        ct.publish_capture(second, target)

    assert (target / "document.html").read_bytes() == original
    assert not second.exists(), "the refused staging directory is cleaned up"


def test_a_staging_directory_missing_its_sidecar_is_refused(namespace, tmp_path):
    staging = staging_dir(tmp_path, sidecar=False)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    with pytest.raises(ct.CaptureError, match="half an evidence pair"):
        ct.publish_capture(staging, target)
    assert list(namespace.iterdir()) == []
    assert not staging.exists()


def test_a_staging_directory_missing_its_document_is_refused(namespace, tmp_path):
    staging = staging_dir(tmp_path, document=False)
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    with pytest.raises(ct.CaptureError, match="half an evidence pair"):
        ct.publish_capture(staging, target)
    assert list(namespace.iterdir()) == []


def test_a_staging_directory_with_two_documents_is_refused(namespace, tmp_path):
    staging = staging_dir(tmp_path)
    (staging / "document.pdf").write_bytes(b"%PDF-")
    target = ct.capture_directory(SOURCE, DOC, CAPTURE_ID)
    with pytest.raises(ct.CaptureError, match="exactly one"):
        ct.publish_capture(staging, target)
    assert list(namespace.iterdir()) == []


def test_the_directory_name_is_the_identity_triple():
    assert ct.capture_directory_name(SOURCE, DOC, CAPTURE_ID) == f"{SOURCE}__{DOC}__{CAPTURE_ID}"


def test_no_component_alphabet_can_produce_a_traversal_name():
    """Structural: none of the three alphabets admits '.', so the join cannot be '.' or '..'."""
    name = ct.capture_directory_name(SOURCE, DOC, CAPTURE_ID)
    assert "." not in name
    assert name not in (".", "..")


def test_the_production_namespace_sits_under_the_snapshot_root():
    assert ct.CAPTURES_ROOT.parent == rights.TERMS_SNAPSHOT_ROOT
    assert ct.CAPTURES_ROOT.name == "captures"


def test_b1_does_not_own_the_pre_existing_g3_fixture():
    """The reason B1 has a namespace at all.

    `synthetic_test_terms.txt` is a tracked G3 fixture living directly in the
    snapshot ROOT. A verifier sweeping the root would call it an orphan and fail
    before B1 had created anything.
    """
    fixture = rights.TERMS_SNAPSHOT_ROOT / "synthetic_test_terms.txt"
    assert fixture.is_file(), "the G3 fixture this namespace exists to avoid is gone"
    assert not fixture.is_relative_to(ct.CAPTURES_ROOT)


# ==========================================================================
# STEP 10 -- asserted and observed are different fields.
# ==========================================================================

def test_a_manual_sidecar_carries_assertions_and_no_observations():
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL)
    assert ct.ASSERTED_ONLY_FIELDS <= set(built)
    assert not (ct.OBSERVED_ONLY_FIELDS & set(built)), "absent, not null-filled"
    ct.validate_sidecar(built)


def test_an_automated_sidecar_carries_observations_and_no_assertions():
    built = sidecar(ct.AUTOMATED_FETCH)
    assert ct.OBSERVED_ONLY_FIELDS <= set(built)
    assert not (ct.ASSERTED_ONLY_FIELDS & set(built))
    ct.validate_sidecar(built)


def test_a_manual_capture_may_not_be_built_with_observed_fields():
    with pytest.raises(ct.CaptureError, match="nothing was observed"):
        ct.build_sidecar(
            source_id=SOURCE, candidate_doc_id=DOC, capture_id=CAPTURE_ID,
            acquisition_method=ct.HUMAN_MANUAL_RETRIEVAL,
            acquisition_basis_ref="a", retention_basis_ref="r",
            media_type="text/html", payload=PAYLOAD, timestamp=STAMP,
            asserted=manual_fields(), observed=observed_fields(),
        )


def test_an_automated_capture_may_not_be_built_with_asserted_fields():
    with pytest.raises(ct.CaptureError, match="beside a claim"):
        ct.build_sidecar(
            source_id=SOURCE, candidate_doc_id=DOC, capture_id=CAPTURE_ID,
            acquisition_method=ct.AUTOMATED_FETCH,
            acquisition_basis_ref="a", retention_basis_ref="r",
            media_type="text/html", payload=PAYLOAD, timestamp=STAMP,
            asserted=manual_fields(), observed=observed_fields(),
        )


def test_validate_refuses_a_manual_sidecar_carrying_an_observed_chain():
    """Direction one of the impossible-combination rule."""
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL)
    built["redirectChainObserved"] = ["https://a.test", "https://b.test"]
    with pytest.raises(ct.CaptureError, match="opens no connection"):
        ct.validate_sidecar(built)


def test_validate_refuses_an_automated_sidecar_with_no_observed_final_url():
    """Direction two. Both named, because one alone is half a rule."""
    built = sidecar(ct.AUTOMATED_FETCH)
    del built["finalUrlObserved"]
    with pytest.raises(ct.CaptureError, match="did not observe the transaction"):
        ct.validate_sidecar(built)


def test_validate_refuses_an_automated_sidecar_carrying_an_actor_assertion():
    built = sidecar(ct.AUTOMATED_FETCH)
    built["actor"] = "operator"
    with pytest.raises(ct.CaptureError, match="same record shape as a measurement"):
        ct.validate_sidecar(built)


def test_validate_refuses_a_manual_sidecar_missing_its_attestation():
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL)
    del built["attestationRef"]
    with pytest.raises(ct.CaptureError, match="missing"):
        ct.validate_sidecar(built)


def test_a_sidecar_whose_id_and_stamp_disagree_is_refused_at_build_time():
    with pytest.raises(ct.CaptureError, match="same instant"):
        ct.build_sidecar(
            source_id=SOURCE, candidate_doc_id=DOC, capture_id=CAPTURE_ID,
            acquisition_method=ct.HUMAN_MANUAL_RETRIEVAL,
            acquisition_basis_ref="a", retention_basis_ref="r",
            media_type="text/html", payload=PAYLOAD,
            timestamp="2026-09-11T09:00:00Z",
            asserted=manual_fields(),
        )


def test_a_sidecar_whose_id_and_stamp_disagree_is_refused_at_validate_time():
    """Separately provable: build-time and read-back are different moments.

    A record can be edited on disk after it was built, and `--verify` reads what
    is there rather than what was once assembled.
    """
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL)
    built["capturedAtUtc"] = "2026-09-11T09:00:00Z"
    with pytest.raises(ct.CaptureError, match="same instant"):
        ct.validate_sidecar(built)


def test_a_zero_byte_document_is_not_a_captured_document():
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL, byteLength=0)
    with pytest.raises(ct.CaptureError, match="zero-byte"):
        ct.validate_sidecar(built)


def test_the_sidecar_records_the_digest_of_the_bytes_it_was_given():
    import hashlib
    built = sidecar(ct.HUMAN_MANUAL_RETRIEVAL)
    assert built["sha256"] == hashlib.sha256(PAYLOAD).hexdigest()
    assert built["byteLength"] == len(PAYLOAD)


def test_an_unknown_acquisition_method_is_refused_both_ways():
    with pytest.raises(ct.CaptureError, match="unknown acquisitionMethod"):
        ct.build_sidecar(
            source_id=SOURCE, candidate_doc_id=DOC, capture_id=CAPTURE_ID,
            acquisition_method="TELEPATHY",
            acquisition_basis_ref="a", retention_basis_ref="r",
            media_type="text/html", payload=PAYLOAD, timestamp=STAMP,
        )
    with pytest.raises(ct.CaptureError, match="unknown acquisitionMethod"):
        ct.validate_sidecar({"acquisitionMethod": "TELEPATHY"})


def test_the_sidecar_names_the_registrar_that_wrote_it():
    assert sidecar()["registrarVersion"] == ct.REGISTRAR_VERSION


def test_a_known_media_type_has_a_declared_extension():
    assert ct.media_type_extension("text/html") == "html"
    assert ct.media_type_extension("application/pdf") == "pdf"


def test_an_undeclared_media_type_has_no_extension_to_guess():
    with pytest.raises(ct.CaptureError, match="no declared extension"):
        ct.media_type_extension("application/x-whatever")


def test_a_sidecar_serialises_to_json():
    json.dumps(sidecar(ct.AUTOMATED_FETCH))
