# -*- coding: utf-8 -*-
"""P0.G4 — deterministic functional-type snapshot generator.

    python scripts/equipment_identity/type_snapshot.py
    python -m pytest scripts/equipment_identity/test_type_snapshot.py -q

`mobile/assets/data/equipment.json` remains the single functional-ontology
source of truth (Layer A per the v4.1 design doc — "Functional class used
by exercises/safety/programmes. Immutable semantics."). This module never
hand-authors a second catalogue; it only projects that file into an
immutable, hashed snapshot an exact-model layer (Layer B — EquipmentModel's
`primaryTypeId`/`supportedTypeIds`) can validate references against.
`validate_type_reference` is that validation, exposed as a pure function so
a future exact-model schema/server path can call it directly rather than
reimplementing the same check.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import canonical_json

REPO = Path(__file__).resolve().parents[2]
EQUIPMENT_JSON = REPO / "mobile" / "assets" / "data" / "equipment.json"
P0_DIR = REPO / "core" / "equipment_identity" / "p0"
SNAPSHOT_PATH = P0_DIR / "functional_type_snapshot_v1.json"
MANIFEST_PATH = P0_DIR / "functional_type_snapshot_manifest.json"

SCHEMA_VERSION = 1
SOURCE_RELATIVE_PATH = "mobile/assets/data/equipment.json"
SNAPSHOT_RELATIVE_PATH = "core/equipment_identity/p0/functional_type_snapshot_v1.json"


class TypeSnapshotError(RuntimeError):
    """The source catalogue, or a type reference checked against it, is
    invalid. Never silently normalized or dropped."""


def load_source_entries(path: Path = EQUIPMENT_JSON) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise TypeSnapshotError(f"{path}: expected a JSON array of equipment types")
    ids = [entry.get("id") for entry in data]
    if any(not isinstance(i, str) or not i for i in ids):
        raise TypeSnapshotError(f"{path}: every entry needs a non-empty string id")
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        raise TypeSnapshotError(f"{path}: duplicate equipment id(s) {dupes}")
    return data


def _types_compact_json(types: list[dict[str, Any]]) -> str:
    # Same canonical convention as canonical_json.dump_compact (sorted keys,
    # no insignificant whitespace) applied to a bare list rather than a
    # dict, because the hash must cover `types` alone -- hashing the whole
    # snapshot payload would make the hash depend on fields (sourceSha256,
    # typeCount) that are themselves derived from `types`, not on the type
    # data the hash exists to identify.
    return json.dumps(types, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def build_snapshot(equipment_json_path: Path = EQUIPMENT_JSON) -> tuple[dict[str, Any], dict[str, Any]]:
    """Returns (snapshot_payload, manifest_payload). A pure function of the
    input file's current bytes — rerunning on unchanged input reproduces
    both payloads byte-for-byte (no wall-clock timestamp is ever written)."""
    entries = load_source_entries(equipment_json_path)
    types = canonical_json.sort_by_key(entries, "id")
    snapshot_sha256 = hashlib.sha256(_types_compact_json(types).encode("utf-8")).hexdigest()
    snapshot_id = f"equipment-types-v1-{snapshot_sha256[:16]}"
    source_sha256 = canonical_json.file_sha256(equipment_json_path)

    snapshot_payload = {
        "schemaVersion": SCHEMA_VERSION,
        "sourcePath": SOURCE_RELATIVE_PATH,
        "sourceSha256": source_sha256,
        "typeCount": len(types),
        "types": types,
    }
    manifest_payload = {
        "schemaVersion": SCHEMA_VERSION,
        "snapshotId": snapshot_id,
        # Full hash, never a truncated prefix -- snapshotId's 16-char
        # prefix is a readable label, not the integrity check.
        "snapshotSha256": snapshot_sha256,
        "snapshotPath": SNAPSHOT_RELATIVE_PATH,
        "sourcePath": SOURCE_RELATIVE_PATH,
        "sourceSha256": source_sha256,
        "typeCount": len(types),
        "generatedBy": "scripts/equipment_identity/type_snapshot.py",
    }
    return snapshot_payload, manifest_payload


def write_snapshot(equipment_json_path: Path = EQUIPMENT_JSON) -> tuple[dict[str, Any], dict[str, Any]]:
    snapshot, manifest = build_snapshot(equipment_json_path)
    canonical_json.write_pretty(SNAPSHOT_PATH, snapshot)
    canonical_json.write_pretty(MANIFEST_PATH, manifest)
    return snapshot, manifest


def load_snapshot(path: Path = SNAPSHOT_PATH) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_type_reference(
    primary_type_id: str, supported_type_ids: list[str], snapshot: dict[str, Any]
) -> None:
    """Pure validator for one exact-model's type references against a
    snapshot. Raises `TypeSnapshotError` on any invalid reference — never
    silently normalizes, drops, or defaults an unknown id. No production
    EquipmentModel schema exists yet (P0.G4 scope); callers pass fixtures
    until one does."""
    if not isinstance(primary_type_id, str) or not primary_type_id:
        raise TypeSnapshotError(f"primaryTypeId must be a non-empty string, got {primary_type_id!r}")

    if not isinstance(supported_type_ids, list):
        raise TypeSnapshotError("supportedTypeIds must be a list")
    non_strings = [t for t in supported_type_ids if not isinstance(t, str) or not t]
    if non_strings:
        raise TypeSnapshotError(
            f"supportedTypeIds must contain only non-empty strings, got {non_strings!r}"
        )

    dupes = sorted({t for t in supported_type_ids if supported_type_ids.count(t) > 1})
    if dupes:
        raise TypeSnapshotError(f"duplicate type id(s) in supportedTypeIds: {dupes}")

    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("types"), list):
        raise TypeSnapshotError("snapshot must be a dict with a 'types' list")
    bad_entries = [t for t in snapshot["types"] if not isinstance(t, dict) or not isinstance(t.get("id"), str)]
    if bad_entries:
        raise TypeSnapshotError("snapshot['types'] contains an entry with no string 'id'")

    known_ids = {t["id"] for t in snapshot["types"]}

    if primary_type_id not in known_ids:
        raise TypeSnapshotError(
            f"primaryTypeId {primary_type_id!r} does not exist in the type snapshot"
        )

    unknown = [t for t in supported_type_ids if t not in known_ids]
    if unknown:
        raise TypeSnapshotError(
            f"supportedTypeId(s) {unknown} do not exist in the type snapshot"
        )

    if primary_type_id not in supported_type_ids:
        raise TypeSnapshotError(
            f"primaryTypeId {primary_type_id!r} must be present in "
            f"supportedTypeIds {supported_type_ids!r} — the default path is "
            "one of the model's own supported functions, not a separate claim"
        )


def main() -> int:
    snapshot, manifest = write_snapshot()
    print(f"wrote {SNAPSHOT_PATH} ({manifest['typeCount']} types)")
    print(f"snapshotId={manifest['snapshotId']}")
    print(f"snapshotSha256={manifest['snapshotSha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
