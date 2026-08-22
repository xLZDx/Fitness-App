# -*- coding: utf-8 -*-
"""P0.G2 — a provenance contract for FUTURE equipment-identity models.

    python -m pytest scripts/equipment_identity/test_provenance.py -q

Purpose: ratchet reproducibility BEFORE another learned recognition
component is added, without "fixing" the historical gaps that already exist.
`core/ml/SCANNER_PROVENANCE.md` already did the hard, honest work of
recording exactly what is and is not known about `equipment_recognition`
v1/v2 — this module does not repeat that investigation or attempt to close
any of its documented UNKNOWNs. `training_code_commit: UNKNOWN` for v1/v2 is
correct and permanent (the training pipeline was never under version
control); this module's job is to make sure the NEXT equipment-identity
model cannot ship with the same gap silently, the way v1 did.

## Reuses existing governance; does not duplicate it

- `scripts/ml/lifecycle.py`'s `TRANSITIONS` — the same nine lifecycle states
  and the same legal-transition table, imported directly, not redeclared.
- `scripts/ml/training_run.py`'s `_commit_exists` — the same git-backed
  commit check `training_run.validate` already uses to refuse ML-2a; a
  future equipment-identity model's `trainingCodeCommit` is held to the
  identical standard, not a laxer or stricter one invented here.
- `core/ml/DATASET_REGISTRY.json` — datasets are expected to be addressable
  the same way `training_run.py` already requires, not through a second
  dataset-registration mechanism.

## Two provenance classes, not one lenient schema

- **FUTURE** — a model that does not exist yet, or exists and is being
  proposed for anything beyond `TRAINED`/`EVALUATED`/`REJECTED`. Six fields
  get real, structural verification: `artifactSha256`/`datasetHash` (must be
  well-formed sha256), `artifactBytes` (positive int), `trainingCodeCommit`
  (must resolve to a real commit in this repository, via the same
  `_commit_exists` `training_run.validate` already uses), `evaluationDatasets`
  (non-empty, must not contain `datasetId`). The remaining free-text fields
  (`task`, `architecture`, `artifactPath`, `trainingCodeLocation`,
  `datasetId`, `datasetManifest`, `dependencyPin`, `inputSchema`,
  `outputSchema`, `deploymentSurface`) get a non-triviality check (not
  empty, not a bare 1-2 character placeholder) plus the shared refusal of
  `UNKNOWN`/`NOT_RECORDED`/`LEGACY` — real content, not deep semantic
  verification (this module does not, for example, confirm `artifactPath`
  exists on disk or that `trainingCodeLocation` is a real directory).
  `trainingTimestamp` must additionally parse as an ISO-8601 date. Reviewed
  2026-08-22 and found overclaiming "every field is verifiable" in an
  earlier draft of this docstring — corrected here, not just in the diff,
  so the claim matches what the code actually checks.
- **HISTORICAL_GRANDFATHERED** — restricted to `(modelId, modelVersion)`
  pairs that ALREADY exist in `MODEL_REGISTRY.json` — checked against the
  real registry at validation time, not merely self-declared by whoever
  writes the manifest. Today that is only `equipment_recognition@v1`/`@v2`.
  `UNKNOWN`/`NOT_RECORDED` are accepted for a genuinely-grandfathered entry,
  and an already-`CHAMPION` legacy model (v1 — "champion by default rather
  than by evaluation", the same first-of-its-kind precedent `content_qa`
  already records) is accepted as historical fact, not demoted. What is
  refused: a HISTORICAL_GRANDFATHERED manifest claiming
  `CHALLENGER_CANDIDATE`, `SHADOW_READY`, `SHADOW`, or `PROMOTION_REVIEW` —
  moving a still-incomplete model FURTHER along the track is a fresh
  decision, and a fresh decision needs real evidence, not inherited slack
  from a model that predates this governance. **Fixed 2026-08-22**: an
  earlier version let ANY `(modelId, modelVersion)` claim this class,
  including one that had never appeared in `MODEL_REGISTRY.json` at all —
  found by review, reproduced, closed by the registry cross-check.

This module never writes to `MODEL_REGISTRY.json`, `DATASET_REGISTRY.json`,
or anywhere else — it validates manifests handed to it and returns a
verdict; promotion (editing the actual registry) stays a separate, human
decision recorded there, exactly as `scripts/ml/lifecycle.py` already
insists for every other model.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
MODEL_REGISTRY = REPO / "core" / "ml" / "MODEL_REGISTRY.json"

sys.path.insert(0, str(REPO / "scripts" / "ml"))
from lifecycle import TRANSITIONS  # noqa: E402
from training_run import _commit_exists  # noqa: E402

#: Every field a FUTURE equipment-identity provenance manifest must carry.
#: Named to match this generator's own camelCase convention (see
#: `canonical_json.py`), not `MODEL_REGISTRY.json`'s snake_case — this is a
#: new schema for a new model family, not a restatement of the old one.
REQUIRED_FIELDS: tuple[str, ...] = (
    "modelId", "modelVersion", "task", "architecture",
    "artifactPath", "artifactSha256", "artifactBytes",
    "trainingCodeLocation", "trainingCodeCommit",
    "datasetId", "datasetHash", "datasetManifest",
    "dependencyPin", "inputSchema", "outputSchema",
    "trainingTimestamp", "evaluationDatasets",
    "primaryMetrics", "guardrailMetrics",
    "lifecycleState", "deploymentSurface", "rollbackTarget",
)

#: The only two placeholder strings a manifest may ever use for an unknown
#: value — the same vocabulary `MODEL_REGISTRY.json`'s own header rules use
#: ("Nothing here is fabricated. A value that is not known is stated as
#: UNKNOWN, NOT_RECORDED or LEGACY"). Never invent a third.
HISTORICAL_PLACEHOLDERS = frozenset({"UNKNOWN", "NOT_RECORDED", "LEGACY"})

#: A HISTORICAL_GRANDFATHERED manifest may describe a model that is ALREADY
#: `CHAMPION` — v1 is, by default rather than by evaluation, the same
#: "first-of-its-kind, no formal gate" precedent `MODEL_REGISTRY.json`
#: already records for `content_qa`. What grandfathering must never permit
#: is an ACTIVE decision to move a still-incomplete model further along the
#: track: these four states each represent a fresh promotion decision, and a
#: fresh decision needs real evidence, not inherited slack from a model that
#: predates this governance.
PROMOTION_TRACK_STATES = frozenset(
    {"CHALLENGER_CANDIDATE", "SHADOW_READY", "SHADOW", "PROMOTION_REVIEW"}
)

PROVENANCE_CLASSES = frozenset({"FUTURE", "HISTORICAL_GRANDFATHERED"})


class ProvenanceError(RuntimeError):
    """A manifest that would let a model reach production, or look like it
    could, without the evidence that claim requires."""


def _is_missing(manifest: dict[str, Any], field: str) -> bool:
    if field not in manifest:
        return True
    value = manifest[field]
    if field == "rollbackTarget":
        # `null` is a legitimate, meaningful value here -- "no rollback
        # target exists" (MODEL_REGISTRY.json itself records this as
        # `"rollback_target": null` for v1, its first-ever model). Missing
        # means the KEY is absent, not that its value is None -- but a
        # present value must still be None or a real string, never some
        # other type nothing downstream would validate (review-caught: an
        # earlier version accepted ANY value here, not just None/str).
        return not (value is None or isinstance(value, str))
    return value in ("", [], {}) or value is None


def _looks_like_sha256(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(
        c in "0123456789abcdef" for c in value.lower()
    )


#: Free-text FUTURE fields that get no deeper structural check than "this is
#: not a bare 1-2 character placeholder" -- `_is_missing` catches empty, the
#: `HISTORICAL_PLACEHOLDERS` scan catches UNKNOWN/NOT_RECORDED/LEGACY, and
#: this catches the third failure mode a review round found: a non-empty,
#: non-placeholder but content-free value like `"x"` or `"?"`. Not a claim
#: that these fields are semantically verified (this module does not confirm
#: `artifactPath` exists on disk, or that `task` names a real task) -- see
#: the module docstring for exactly what each field does and does not get.
_MIN_FREETEXT_LENGTH = 3
FREETEXT_FUTURE_FIELDS: tuple[str, ...] = (
    "task", "architecture", "artifactPath", "trainingCodeLocation",
    "datasetId", "datasetManifest", "dependencyPin", "inputSchema",
    "outputSchema", "deploymentSurface",
)


def _looks_trivial(value: Any) -> bool:
    return not isinstance(value, str) or len(value.strip()) < _MIN_FREETEXT_LENGTH


def _looks_like_iso_date(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    from datetime import date, datetime
    for fmt_fn in (date.fromisoformat, datetime.fromisoformat):
        try:
            fmt_fn(value)
            return True
        except ValueError:
            continue
    return False


def _grandfathered_registry_entries() -> frozenset[tuple[str, str]]:
    """The only `(modelId, modelVersion)` pairs a HISTORICAL_GRANDFATHERED
    manifest may claim to be -- read fresh from the real registry every call,
    never cached/hardcoded, so this can never silently drift from what
    `MODEL_REGISTRY.json` actually contains. A manifest for a pair NOT in
    this set is, by definition, not something that predates this contract."""
    registry = json.loads(MODEL_REGISTRY.read_text(encoding="utf-8"))
    return frozenset(
        (m.get("model_id"), m.get("model_version"))
        for m in registry.get("models", [])
    )


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    """Refuse a provenance manifest that cannot support the claims it makes.

    Returns a small verdict dict on success; raises `ProvenanceError` naming
    the exact reason on failure. Never mutates `manifest` or any file on disk."""
    provenance_class = manifest.get("provenanceClass")
    if provenance_class not in PROVENANCE_CLASSES:
        raise ProvenanceError(
            f"provenanceClass must be one of {sorted(PROVENANCE_CLASSES)}, "
            f"got {provenance_class!r}"
        )

    missing = [f for f in REQUIRED_FIELDS if _is_missing(manifest, f)]
    if missing:
        raise ProvenanceError(
            f"{manifest.get('modelId', '<unknown model>')}: missing required "
            f"provenance fields: {missing}. A partly described manifest is "
            "worse than none — it looks recorded"
        )

    state = manifest["lifecycleState"]
    if state not in TRANSITIONS:
        raise ProvenanceError(
            f"lifecycleState {state!r} is not one of {sorted(TRANSITIONS)} "
            "(scripts/ml/lifecycle.py's own transition table)"
        )

    if provenance_class == "HISTORICAL_GRANDFATHERED":
        pair = (manifest["modelId"], manifest["modelVersion"])
        grandfathered = _grandfathered_registry_entries()
        if pair not in grandfathered:
            raise ProvenanceError(
                f"{manifest['modelId']}@{manifest['modelVersion']}: claims "
                "provenanceClass=HISTORICAL_GRANDFATHERED but this (modelId, "
                f"modelVersion) pair is not in MODEL_REGISTRY.json ({sorted(grandfathered)}). "
                "Grandfathering is not self-declarable — it is restricted to "
                "models that already exist and predate this contract. A new "
                "model must use provenanceClass=FUTURE and pass its real "
                "checks, not claim historical status to skip them"
            )
        if state in PROMOTION_TRACK_STATES:
            raise ProvenanceError(
                f"{manifest['modelId']}@{manifest['modelVersion']}: a "
                "HISTORICAL_GRANDFATHERED manifest may not claim lifecycleState "
                f"{state!r} — an already-CHAMPION legacy model is grandfathered "
                "as historical fact, but moving a still-incomplete model FURTHER "
                "along the promotion track is a fresh decision that needs real "
                f"evidence. Promotion-track states are {sorted(PROMOTION_TRACK_STATES)}"
            )
        return {
            "ok": True,
            "provenanceClass": provenance_class,
            "promotable": False,
            "notes": "Historical entry, frozen evidence. UNKNOWN/NOT_RECORDED "
                     "fields are accepted as-is and never treated as blockers for "
                     "this class. `promotable: false` means this manifest's "
                     "incomplete provenance may never be used to justify "
                     "advancing it (or any other model) further — it does not "
                     "mean an already-CHAMPION legacy model is being demoted; "
                     "its current lifecycleState is read from the registry, "
                     "not decided here.",
        }

    # FUTURE: no placeholder value anywhere, every claim independently checkable.
    placeholder_fields = [
        f for f in REQUIRED_FIELDS
        if isinstance(manifest.get(f), str) and manifest[f] in HISTORICAL_PLACEHOLDERS
    ]
    if placeholder_fields:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: FUTURE "
            f"provenance cannot carry a placeholder value in {placeholder_fields} "
            "— UNKNOWN/NOT_RECORDED/LEGACY are only legal for "
            "provenanceClass=HISTORICAL_GRANDFATHERED"
        )

    trivial_fields = [f for f in FREETEXT_FUTURE_FIELDS if _looks_trivial(manifest.get(f))]
    if trivial_fields:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: FUTURE "
            f"provenance field(s) {trivial_fields} are present but too short/"
            f"content-free to be a real value (minimum {_MIN_FREETEXT_LENGTH} "
            "non-whitespace characters) — a placeholder like 'x' or '?' is not "
            "a concrete provenance claim any more than UNKNOWN is"
        )
    if not _looks_like_iso_date(manifest["trainingTimestamp"]):
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: trainingTimestamp "
            f"{manifest['trainingTimestamp']!r} does not parse as an ISO-8601 date"
        )

    if not _looks_like_sha256(manifest["artifactSha256"]):
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: artifactSha256 "
            f"{manifest['artifactSha256']!r} is not a 64-hex-character sha256"
        )
    if not isinstance(manifest["artifactBytes"], int) or manifest["artifactBytes"] <= 0:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: artifactBytes "
            f"must be a positive integer, got {manifest['artifactBytes']!r}"
        )
    if not _looks_like_sha256(manifest["datasetHash"]):
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: datasetHash "
            f"{manifest['datasetHash']!r} is not a 64-hex-character sha256"
        )
    if not _commit_exists(manifest["trainingCodeCommit"]):
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: "
            f"trainingCodeCommit={manifest['trainingCodeCommit']!r} does not "
            "name a commit in this repository. This is exactly ML-2a's failure "
            "mode (scripts/ml/training_run.py) and must not repeat for a new model"
        )

    evaluation_datasets = manifest["evaluationDatasets"]
    if not isinstance(evaluation_datasets, list) or not evaluation_datasets:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: FUTURE "
            "provenance requires at least one entry in evaluationDatasets — "
            "'it got better' is not a measurement without one"
        )
    if manifest["datasetId"] in evaluation_datasets:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: datasetId "
            f"{manifest['datasetId']!r} also appears in evaluationDatasets — a "
            "model measured on what it was trained on reports its memory, not "
            "its generalisation"
        )

    if not manifest["primaryMetrics"]:
        raise ProvenanceError(
            f"{manifest['modelId']}@{manifest['modelVersion']}: FUTURE "
            "provenance requires non-empty primaryMetrics"
        )

    return {
        "ok": True,
        "provenanceClass": "FUTURE",
        "promotable": state not in ("REJECTED", "RETIRED"),
        "checkedFields": list(REQUIRED_FIELDS),
    }


def manifest_from_registry_entry(
    entry: dict[str, Any], provenance_class: str = "HISTORICAL_GRANDFATHERED"
) -> dict[str, Any]:
    """Read-only remap of a real `MODEL_REGISTRY.json` entry (snake_case) into
    this module's schema shape (camelCase), so an existing entry can be run
    through `validate_manifest` without inventing a second copy of its data
    by hand. Never writes back to the registry; the returned dict is a new
    object, not a reference into the loaded registry."""
    return {
        "provenanceClass": provenance_class,
        "modelId": entry.get("model_id"),
        "modelVersion": entry.get("model_version"),
        "task": entry.get("task"),
        "architecture": entry.get("architecture"),
        "artifactPath": entry.get("artifact_path"),
        "artifactSha256": entry.get("artifact_sha256"),
        "artifactBytes": entry.get("artifact_bytes"),
        "trainingCodeLocation": entry.get("training_code_location"),
        "trainingCodeCommit": entry.get("training_code_commit"),
        "datasetId": entry.get("training_dataset_version") or "NOT_RECORDED",
        "datasetHash": "NOT_RECORDED",
        "datasetManifest": entry.get("training_dataset_description") or "NOT_RECORDED",
        "dependencyPin": "NOT_RECORDED",
        "inputSchema": entry.get("input_schema_version"),
        "outputSchema": entry.get("output_schema"),
        "trainingTimestamp": entry.get("training_timestamp"),
        "evaluationDatasets": [e.get("dataset", "NOT_RECORDED") for e in entry.get("evaluations", [])] or ["NOT_RECORDED"],
        "primaryMetrics": entry.get("primary_metrics") or {},
        "guardrailMetrics": entry.get("guardrail_metrics") or {},
        "lifecycleState": entry.get("lifecycle_state"),
        "deploymentSurface": entry.get("deployment_surface"),
        # `entry.get(..., "NOT_RECORDED")`, NOT `entry.get(...) or "NOT_RECORDED"`:
        # v1's `rollback_target` is a deliberately recorded `null` ("No
        # previous version exists. This is v1." -- MODEL_REGISTRY.json's own
        # note), not an absence. `or` would silently relabel that recorded
        # fact as the placeholder string reserved for genuinely unknown
        # values -- review-caught; `.get`'s own default only fires when the
        # KEY itself is missing, which preserves a real `None`.
        "rollbackTarget": entry.get("rollback_target", "NOT_RECORDED"),
    }


def _model_registry_entry(registry: dict[str, Any], model_id: str, version: str) -> dict[str, Any]:
    for m in registry.get("models", []):
        if m.get("model_id") == model_id and m.get("model_version") == version:
            return m
    raise ProvenanceError(f"MODEL_REGISTRY.json: no entry for {model_id}@{version}")


def main() -> int:
    registry = json.loads(MODEL_REGISTRY.read_text(encoding="utf-8"))
    for model_id, version in (("equipment_recognition", "v1"), ("equipment_recognition", "v2")):
        entry = _model_registry_entry(registry, model_id, version)
        manifest = manifest_from_registry_entry(entry)
        verdict = validate_manifest(manifest)
        print(f"{model_id}@{version}: {verdict['provenanceClass']}, promotable={verdict['promotable']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
