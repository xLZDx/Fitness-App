# -*- coding: utf-8 -*-
"""P0.G1 tests — the 9 minimum cases from
`SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md` §6.4,
plus the module's own helper coverage.

    python -m pytest scripts/equipment_identity/test_baseline.py -q
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import baseline  # noqa: E402
from canonical_json import file_sha256, payload_sha256  # noqa: E402


def _without_source_commit(payload: dict) -> dict:
    # `sourceCommit` is `git rev-parse HEAD` at build time (baseline.py's own
    # `--check` already excludes it for the same reason, baseline.py:~600):
    # a concurrent commit landing between the two `build()` calls below would
    # change it and fail this test even though the generator's actual
    # determinism w.r.t. real source content is intact — a false regression,
    # not a real one. This repo routinely runs concurrent sessions.
    return {k: v for k, v in payload.items() if k != "sourceCommit"}


def test_1_baseline_generator_deterministic():
    a = baseline.build()
    b = baseline.build()
    assert payload_sha256(_without_source_commit(a)) == payload_sha256(_without_source_commit(b))


def test_1b_legacy_inventory_generator_deterministic():
    a = baseline.build_legacy_inventory()
    b = baseline.build_legacy_inventory()
    assert payload_sha256(_without_source_commit(a)) == payload_sha256(_without_source_commit(b))


def test_2_all_scanner_contract_paths_exist():
    payload = baseline.build()
    for entry in payload["scannerContracts"]:
        assert (baseline.REPO / entry["path"]).exists(), entry["path"]


def test_3_recorded_sha_values_match_source():
    payload = baseline.build()
    for entry in payload["scannerContracts"]:
        actual = file_sha256(baseline.REPO / entry["path"])
        assert actual == entry["sha256"], entry["path"]
    assert payload["functionalCatalog"]["sha256"] == file_sha256(baseline.FUNCTIONAL_CATALOG)
    assert payload["modelRegistry"]["sha256"] == file_sha256(baseline.MODEL_REGISTRY)


def test_4_equipment_v1_artifact_hash_matches_model_registry():
    payload = baseline.build()
    registry = json.loads(baseline._read(baseline.MODEL_REGISTRY))
    v1 = baseline._model_registry_entry(registry, "equipment_recognition", "v1")
    v1_out = payload["modelArtifacts"]["equipment_recognition@v1"]
    assert v1_out["sha256"] == v1["artifact_sha256"]
    assert v1_out["sha256"] == file_sha256(baseline.TFLITE_MODEL)
    assert v1_out["bytes"] == v1["artifact_bytes"]


def test_5_v1_v2_deployment_truth_matches_registry():
    payload = baseline.build()
    registry = json.loads(baseline._read(baseline.MODEL_REGISTRY))
    v1 = baseline._model_registry_entry(registry, "equipment_recognition", "v1")
    v2 = baseline._model_registry_entry(registry, "equipment_recognition", "v2")

    # The keys themselves must be present in the registry, not just absent-vs-False
    # indistinguishable — a dropped key must fail test_5, not pass vacuously
    # (an internal review caught `_require`'s predecessor, `dict.get()`, letting
    # this happen silently).
    for key in ("bundled", "champion", "class_count", "supports_unknown_or_abstain"):
        assert key in v1, f"MODEL_REGISTRY.json equipment_recognition@v1 is missing {key!r}"
    assert "bundled" in v2, "MODEL_REGISTRY.json equipment_recognition@v2 is missing 'bundled'"

    v1_out = payload["modelArtifacts"]["equipment_recognition@v1"]
    assert v1_out["deploymentStatus"] == v1["deployment_status"]
    assert v1_out["bundledInApk"] == bool(v1["bundled"])
    assert v1_out["champion"] == bool(v1["champion"])
    assert v1_out["classCount"] == v1["class_count"]
    assert v1_out["supportsUnknownOrAbstain"] == bool(v1["supports_unknown_or_abstain"])

    v2_out = payload["modelArtifacts"]["equipment_recognition@v2"]
    assert v2_out["deploymentStatus"] == v2["deployment_status"]
    assert v2_out["deploymentStatus"] == "NOT_SHIPPED"
    assert v2_out["bundledInApk"] is False


def test_5b_missing_registry_key_fails_loudly_not_silently():
    entry = {"bundled": True}
    with pytest.raises(baseline.BaselineError):
        baseline._require(entry, "champion", "test-entry")


def test_6_legacy_inventory_can_never_say_training_allowed_true():
    payload = baseline.build_legacy_inventory()
    assert payload["trainingAllowed"] is False
    assert payload["datasetRole"] == "LEGACY_REAL_GYM_REGRESSION"


def test_7_legacy_inventory_can_never_say_sealed_blind_evaluation_true():
    payload = baseline.build_legacy_inventory()
    assert payload["sealedBlindEvaluation"] is False
    assert payload["promotionHoldout"] is False


def test_8_offline_fallback_invariant_remains_non_settled():
    payload = baseline.build()
    invariants = payload["genericInvariants"]
    assert invariants["photoPathOfflineFallbackNeverReportsConfident"] is True
    # The live-viewfinder path is a separate fact, deliberately not folded
    # into the photo-path key above (an internal review caught the two paths
    # being described as one unscoped invariant — see baseline.py's
    # `_live_mode_has_no_offline_downgrade_guard` docstring).
    live = invariants["liveMode"]
    assert live["livePathIsOnDeviceOnly"] is True
    assert live["settledLiveReadingHasNoOfflineDowngradeEquivalent"] is True
    assert live["settledLiveReadingsAreWrittenToHistory"] is True


def test_9_baseline_does_not_alter_source():
    before = {
        p: file_sha256(p)
        for p in (
            baseline.FUNCTIONAL_CATALOG,
            baseline.MODEL_REGISTRY,
            baseline.TFLITE_MODEL,
            baseline.B1_MEASUREMENT_NOTE,
        )
    }
    baseline.build()
    baseline.build_legacy_inventory()
    after = {p: file_sha256(p) for p in before}
    assert before == after


def test_exact_identity_concepts_are_absent_from_current_source():
    payload = baseline.build()
    exact_identity = payload["genericInvariants"]["exactIdentity"]
    assert exact_identity["exactIdentityConceptsAbsent"] is True
    assert exact_identity["hits"] == []


def test_legacy_raw_photo_dir_absent_yields_honest_unavailable_marker():
    payload = baseline.build_legacy_inventory()
    raw = payload["rawPhotoSet"]
    if raw["presentInThisCheckout"]:
        assert raw["rawContentHashes"] != "UNAVAILABLE_IN_THIS_CHECKOUT"
    else:
        assert raw["rawContentHashes"] == "UNAVAILABLE_IN_THIS_CHECKOUT"


def test_legacy_frames_are_grounded_in_the_b1_note_text():
    note_text = baseline._read(baseline.B1_MEASUREMENT_NOTE)
    baseline._verify_legacy_frames(note_text)


def test_write_then_check_round_trips_cleanly(tmp_path):
    out_baseline = tmp_path / "recognition_baseline_v1.json"
    out_legacy = tmp_path / "legacy_real_gym_regression_inventory.json"
    rc_write = baseline.main(["--write", "--target", "baseline", "--out", str(out_baseline)])
    assert rc_write == 0
    assert out_baseline.exists()
    rc_check = baseline.main(["--check", "--target", "baseline", "--out", str(out_baseline)])
    assert rc_check == 0

    rc_write2 = baseline.main(["--write", "--target", "legacy", "--out", str(out_legacy)])
    assert rc_write2 == 0
    rc_check2 = baseline.main(["--check", "--target", "legacy", "--out", str(out_legacy)])
    assert rc_check2 == 0
