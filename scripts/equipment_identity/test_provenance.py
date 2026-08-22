# -*- coding: utf-8 -*-
"""P0.G2 tests for scripts/equipment_identity/provenance.py.

    python -m pytest scripts/equipment_identity/test_provenance.py -q
"""
from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import provenance  # noqa: E402


def _real_commit() -> str:
    out = subprocess.run(
        ["git", "-C", str(provenance.REPO), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def _complete_future_manifest() -> dict:
    return {
        "provenanceClass": "FUTURE",
        "modelId": "equipment_identity",
        "modelVersion": "v1",
        "task": "exact-model equipment identification",
        "architecture": "vision transformer embedding + nearest-neighbour retrieval",
        "artifactPath": "core/equipment_identity/models/equipment_identity_v1.tflite",
        "artifactSha256": "a" * 64,
        "artifactBytes": 12345678,
        "trainingCodeLocation": "scripts/equipment_identity/train.py, in this repository",
        "trainingCodeCommit": _real_commit(),
        "datasetId": "equipment_identity_photos_v1",
        "datasetHash": "b" * 64,
        "datasetManifest": "core/ml/datasets/equipment_identity_photos_v1/manifest.json",
        "dependencyPin": "core/ml/pins/equipment_identity_train_env_v1.txt",
        "inputSchema": "float32 [1,224,224,3]",
        "outputSchema": "float32 [1,512] embedding",
        "trainingTimestamp": "2026-09-01",
        "evaluationDatasets": ["equipment_identity_holdout_v1"],
        "primaryMetrics": {"top_1_retrieval": 0.9},
        "guardrailMetrics": {"unknown_rejection_rate": 0.95},
        "lifecycleState": "TRAINED",
        "deploymentSurface": "ON_DEVICE",
        "rollbackTarget": None,
    }


def test_complete_future_manifest_passes():
    verdict = provenance.validate_manifest(_complete_future_manifest())
    assert verdict["ok"] is True
    assert verdict["provenanceClass"] == "FUTURE"


def test_missing_dataset_hash_fails():
    manifest = _complete_future_manifest()
    del manifest["datasetHash"]
    with pytest.raises(provenance.ProvenanceError, match="datasetHash"):
        provenance.validate_manifest(manifest)


def test_missing_artifact_hash_fails():
    manifest = _complete_future_manifest()
    manifest["artifactSha256"] = ""
    with pytest.raises(provenance.ProvenanceError, match="artifactSha256"):
        provenance.validate_manifest(manifest)


def test_missing_training_code_commit_with_no_permitted_historical_status_fails():
    manifest = _complete_future_manifest()
    manifest["trainingCodeCommit"] = "UNKNOWN"
    with pytest.raises(provenance.ProvenanceError, match="UNKNOWN|placeholder"):
        provenance.validate_manifest(manifest)


def test_future_artifact_with_not_recorded_pretending_production_ready_fails():
    manifest = _complete_future_manifest()
    manifest["lifecycleState"] = "CHAMPION"
    manifest["architecture"] = "NOT_RECORDED"
    with pytest.raises(provenance.ProvenanceError, match="placeholder"):
        provenance.validate_manifest(manifest)


def test_future_manifest_with_bogus_commit_fails():
    manifest = _complete_future_manifest()
    manifest["trainingCodeCommit"] = "f" * 40  # well-formed hex, does not exist in this repo
    with pytest.raises(provenance.ProvenanceError, match="does not name a commit"):
        provenance.validate_manifest(manifest)


def test_future_manifest_evaluated_on_its_own_training_dataset_fails():
    manifest = _complete_future_manifest()
    manifest["evaluationDatasets"] = [manifest["datasetId"]]
    with pytest.raises(provenance.ProvenanceError, match="its own training dataset|generalisation"):
        provenance.validate_manifest(manifest)


def test_future_manifest_with_no_evaluation_datasets_fails():
    manifest = _complete_future_manifest()
    manifest["evaluationDatasets"] = []
    with pytest.raises(provenance.ProvenanceError, match="evaluationDatasets"):
        provenance.validate_manifest(manifest)


def test_unknown_provenance_class_fails():
    manifest = _complete_future_manifest()
    manifest["provenanceClass"] = "RECOVERED"
    with pytest.raises(provenance.ProvenanceError, match="provenanceClass"):
        provenance.validate_manifest(manifest)


def test_future_manifest_with_trivial_freetext_field_fails():
    manifest = _complete_future_manifest()
    manifest["architecture"] = "x"
    with pytest.raises(provenance.ProvenanceError, match="content-free|architecture"):
        provenance.validate_manifest(manifest)


def test_future_manifest_with_unparseable_training_timestamp_fails():
    manifest = _complete_future_manifest()
    manifest["trainingTimestamp"] = "not-a-date"
    with pytest.raises(provenance.ProvenanceError, match="trainingTimestamp"):
        provenance.validate_manifest(manifest)


def test_a_fabricated_model_cannot_launder_through_historical_grandfathered():
    # Regression for a review-caught BLOCKER: HISTORICAL_GRANDFATHERED used
    # to be entirely self-declared, so a brand-new fabricated model could
    # claim it (plus lifecycleState=CHAMPION) and skip every FUTURE check.
    fabricated = {
        "provenanceClass": "HISTORICAL_GRANDFATHERED",
        "modelId": "equipment_identity", "modelVersion": "v1",
        "task": "UNKNOWN", "architecture": "UNKNOWN", "artifactPath": "UNKNOWN",
        "artifactSha256": "UNKNOWN", "artifactBytes": "UNKNOWN",
        "trainingCodeLocation": "UNKNOWN", "trainingCodeCommit": "UNKNOWN",
        "datasetId": "UNKNOWN", "datasetHash": "UNKNOWN", "datasetManifest": "UNKNOWN",
        "dependencyPin": "UNKNOWN", "inputSchema": "UNKNOWN", "outputSchema": "UNKNOWN",
        "trainingTimestamp": "UNKNOWN", "evaluationDatasets": ["UNKNOWN"],
        "primaryMetrics": {"x": 1}, "guardrailMetrics": {"x": 1},
        "lifecycleState": "CHAMPION", "deploymentSurface": "UNKNOWN", "rollbackTarget": None,
    }
    with pytest.raises(provenance.ProvenanceError, match="not in MODEL_REGISTRY.json|not.*self-declarable"):
        provenance.validate_manifest(fabricated)


def _real_registry() -> dict:
    return json.loads(provenance.MODEL_REGISTRY.read_text(encoding="utf-8"))


def test_legacy_v1_unknown_values_accepted_as_historical_not_promotable():
    registry = _real_registry()
    v1 = provenance._model_registry_entry(registry, "equipment_recognition", "v1")
    assert v1["training_code_commit"] == "UNKNOWN"  # still true; this test does not repair it
    manifest = provenance.manifest_from_registry_entry(v1)
    verdict = provenance.validate_manifest(manifest)
    assert verdict["ok"] is True
    assert verdict["provenanceClass"] == "HISTORICAL_GRANDFATHERED"
    assert verdict["promotable"] is False


def test_legacy_v1_champion_state_is_not_rejected_by_grandfathering():
    # v1 is already CHAMPION -- a HISTORICAL_GRANDFATHERED manifest reporting
    # that MUST pass (it is recorded fact), unlike CHALLENGER_CANDIDATE and
    # beyond, which represent a fresh, ungrounded promotion decision.
    registry = _real_registry()
    v1 = provenance._model_registry_entry(registry, "equipment_recognition", "v1")
    assert v1["lifecycle_state"] == "CHAMPION"
    manifest = provenance.manifest_from_registry_entry(v1)
    verdict = provenance.validate_manifest(manifest)
    assert verdict["ok"] is True


def test_manifest_from_registry_entry_preserves_a_real_null_rollback_target():
    # Regression: `entry.get(...) or "NOT_RECORDED"` silently relabeled v1's
    # deliberately-recorded `rollback_target: null` ("no previous version
    # exists") as the placeholder string reserved for genuinely unknown
    # values. `.get(key, default)` must only fall back when the KEY itself
    # is absent, preserving a real `None`.
    registry = _real_registry()
    v1 = provenance._model_registry_entry(registry, "equipment_recognition", "v1")
    assert v1["rollback_target"] is None  # ground truth in the real registry
    manifest = provenance.manifest_from_registry_entry(v1)
    assert manifest["rollbackTarget"] is None


def test_missing_rollback_target_key_still_defaults_to_not_recorded():
    entry_without_key = {"model_id": "x", "model_version": "y"}
    manifest = provenance.manifest_from_registry_entry(entry_without_key)
    assert manifest["rollbackTarget"] == "NOT_RECORDED"


def test_rollback_target_of_the_wrong_type_is_treated_as_missing():
    manifest = _complete_future_manifest()
    manifest["rollbackTarget"] = ["not", "a", "string"]
    with pytest.raises(provenance.ProvenanceError, match="rollbackTarget"):
        provenance.validate_manifest(manifest)


def test_legacy_v2_remains_not_shipped():
    registry = _real_registry()
    v2 = provenance._model_registry_entry(registry, "equipment_recognition", "v2")
    assert v2["deployment_status"] == "NOT_SHIPPED"
    manifest = provenance.manifest_from_registry_entry(v2)
    verdict = provenance.validate_manifest(manifest)
    assert verdict["ok"] is True
    assert verdict["promotable"] is False


def test_grandfathered_manifest_cannot_claim_promotion_track_state():
    registry = _real_registry()
    v2 = provenance._model_registry_entry(registry, "equipment_recognition", "v2")
    manifest = provenance.manifest_from_registry_entry(v2)
    manifest["lifecycleState"] = "CHALLENGER_CANDIDATE"
    with pytest.raises(provenance.ProvenanceError, match="promotion track|CHALLENGER_CANDIDATE"):
        provenance.validate_manifest(manifest)


def test_validator_never_rewrites_registry():
    before = provenance.MODEL_REGISTRY.read_bytes()
    registry = _real_registry()
    for model_id, version in (("equipment_recognition", "v1"), ("equipment_recognition", "v2")):
        entry = provenance._model_registry_entry(registry, model_id, version)
        provenance.validate_manifest(provenance.manifest_from_registry_entry(entry))
    provenance.validate_manifest(_complete_future_manifest())
    after = provenance.MODEL_REGISTRY.read_bytes()
    assert before == after


def test_manifest_from_registry_entry_does_not_mutate_input():
    registry = _real_registry()
    entry = provenance._model_registry_entry(registry, "equipment_recognition", "v1")
    entry_copy = copy.deepcopy(entry)
    provenance.manifest_from_registry_entry(entry)
    assert entry == entry_copy


def test_lifecycle_states_match_scripts_ml_lifecycle():
    # Structural proof this module reuses scripts/ml/lifecycle.py rather than
    # redeclaring a parallel, driftable copy of the same nine states.
    sys.path.insert(0, str(provenance.REPO / "scripts" / "ml"))
    import lifecycle  # noqa: E402
    assert provenance.TRANSITIONS is lifecycle.TRANSITIONS


def test_main_runs_against_real_registry():
    assert provenance.main() == 0
