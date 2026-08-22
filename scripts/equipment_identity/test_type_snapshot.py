# -*- coding: utf-8 -*-
"""P0.G4 tests for scripts/equipment_identity/type_snapshot.py.

    python -m pytest scripts/equipment_identity/test_type_snapshot.py -q
"""
from __future__ import annotations

import json
import random
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import type_snapshot as ts  # noqa: E402
from canonical_json import dump_pretty  # noqa: E402


def _write_equipment_json(tmp_path: Path, entries: list[dict]) -> Path:
    path = tmp_path / "equipment.json"
    path.write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _sample_entries(n: int = 5) -> list[dict]:
    return [
        {
            "id": f"fixture_type_{i}",
            "name": f"Fixture Type {i}",
            "manufacturer": "Any",
            "category": "cardio",
            "description": f"Fixture entry #{i} for P0.G4 tests.",
        }
        for i in range(n)
    ]


# --- snapshot generation --------------------------------------------------

def test_current_equipment_json_produces_a_deterministic_snapshot():
    snapshot_a, manifest_a = ts.build_snapshot()
    snapshot_b, manifest_b = ts.build_snapshot()
    assert manifest_a["snapshotSha256"] == manifest_b["snapshotSha256"]
    assert snapshot_a == snapshot_b
    real = json.loads(ts.EQUIPMENT_JSON.read_text(encoding="utf-8"))
    assert manifest_a["typeCount"] == len(real)
    assert snapshot_a["typeCount"] == len(real)


def test_reordering_the_source_input_yields_the_same_semantic_snapshot_hash(tmp_path):
    real = json.loads(ts.EQUIPMENT_JSON.read_text(encoding="utf-8"))
    shuffled = list(real)
    random.Random(42).shuffle(shuffled)
    assert [e["id"] for e in shuffled] != [e["id"] for e in real]  # actually reordered

    shuffled_path = _write_equipment_json(tmp_path, shuffled)
    _, manifest_real = ts.build_snapshot(ts.EQUIPMENT_JSON)
    _, manifest_shuffled = ts.build_snapshot(shuffled_path)
    assert manifest_real["snapshotSha256"] == manifest_shuffled["snapshotSha256"]


def test_duplicate_equipment_id_fails(tmp_path):
    entries = _sample_entries(3)
    entries.append(dict(entries[0]))
    path = _write_equipment_json(tmp_path, entries)
    with pytest.raises(ts.TypeSnapshotError, match="duplicate"):
        ts.load_source_entries(path)


def test_non_list_source_fails():
    path_text = json.dumps({"not": "a list"})
    import tempfile
    import os
    fd, name = tempfile.mkstemp(suffix=".json")
    try:
        os.write(fd, path_text.encode("utf-8"))
        os.close(fd)
        with pytest.raises(ts.TypeSnapshotError, match="array"):
            ts.load_source_entries(Path(name))
    finally:
        os.unlink(name)


def test_rerun_generator_yields_byte_identical_generated_files(tmp_path):
    snapshot, manifest = ts.build_snapshot()
    snapshot_path_a = tmp_path / "a" / "snapshot.json"
    manifest_path_a = tmp_path / "a" / "manifest.json"
    snapshot_path_b = tmp_path / "b" / "snapshot.json"
    manifest_path_b = tmp_path / "b" / "manifest.json"

    snapshot_path_a.parent.mkdir(parents=True)
    snapshot_path_b.parent.mkdir(parents=True)
    snapshot_path_a.write_text(dump_pretty(snapshot), encoding="utf-8")
    manifest_path_a.write_text(dump_pretty(manifest), encoding="utf-8")

    snapshot2, manifest2 = ts.build_snapshot()
    snapshot_path_b.write_text(dump_pretty(snapshot2), encoding="utf-8")
    manifest_path_b.write_text(dump_pretty(manifest2), encoding="utf-8")

    assert snapshot_path_a.read_bytes() == snapshot_path_b.read_bytes()
    assert manifest_path_a.read_bytes() == manifest_path_b.read_bytes()


def test_generated_files_on_disk_match_a_fresh_build():
    # The committed snapshot/manifest must themselves be exactly what
    # build_snapshot() produces right now -- proves the checked-in files are
    # not hand-edited and are not stale relative to equipment.json.
    fresh_snapshot, fresh_manifest = ts.build_snapshot()
    committed_snapshot = ts.load_snapshot()
    committed_manifest = json.loads(ts.MANIFEST_PATH.read_text(encoding="utf-8"))
    assert committed_snapshot == fresh_snapshot
    assert committed_manifest == fresh_manifest


def test_snapshot_never_edits_the_source_file():
    before = ts.EQUIPMENT_JSON.read_bytes()
    ts.build_snapshot()
    ts.load_source_entries()
    after = ts.EQUIPMENT_JSON.read_bytes()
    assert before == after


# --- validate_type_reference ----------------------------------------------

def _fixture_snapshot() -> dict:
    return {"types": [{"id": "type_a"}, {"id": "type_b"}, {"id": "type_c"}]}


def test_exact_model_fixture_with_nonexistent_primary_type_id_fails():
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="primaryTypeId"):
        ts.validate_type_reference("does_not_exist", ["does_not_exist"], snapshot)


def test_nonexistent_supported_type_id_fails():
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="supportedTypeId"):
        ts.validate_type_reference("type_a", ["type_a", "bogus_type"], snapshot)


def test_valid_multifunction_fixture_passes():
    snapshot = _fixture_snapshot()
    # Must not raise.
    ts.validate_type_reference("type_a", ["type_a", "type_b"], snapshot)


def test_primary_type_id_must_be_present_in_supported_type_ids():
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="supportedTypeIds"):
        ts.validate_type_reference("type_a", ["type_b"], snapshot)


def test_duplicate_supported_type_ids_fail():
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="duplicate"):
        ts.validate_type_reference("type_a", ["type_a", "type_a"], snapshot)


def test_malformed_snapshot_missing_types_key_raises_type_snapshot_error():
    # Found by type-design-analyzer in the P0.G4 review round: a snapshot
    # dict without a "types" key (e.g. the manifest payload passed by
    # mistake instead of the snapshot payload) must raise the module's own
    # error type, not an unrelated bare KeyError a caller's
    # `except TypeSnapshotError` would not catch.
    with pytest.raises(ts.TypeSnapshotError, match="types"):
        ts.validate_type_reference("type_a", ["type_a"], {"schemaVersion": 1})


def test_snapshot_entry_without_an_id_raises_type_snapshot_error():
    snapshot = {"types": [{"id": "type_a"}, {"name": "no id field here"}]}
    with pytest.raises(ts.TypeSnapshotError, match="id"):
        ts.validate_type_reference("type_a", ["type_a"], snapshot)


def test_non_string_supported_type_id_raises_type_snapshot_error_not_type_error():
    # Found by type-design-analyzer: a dict accidentally passed instead of
    # an extracted id string used to crash with an unrelated
    # `TypeError: unhashable type` before any TypeSnapshotError check ran.
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="string"):
        ts.validate_type_reference("type_a", ["type_a", {"id": "type_b"}], snapshot)


def test_non_string_primary_type_id_raises_type_snapshot_error():
    snapshot = _fixture_snapshot()
    with pytest.raises(ts.TypeSnapshotError, match="primaryTypeId"):
        ts.validate_type_reference(None, ["type_a"], snapshot)


def test_validate_type_reference_against_the_real_current_snapshot():
    snapshot = ts.load_snapshot()
    real_ids = [t["id"] for t in snapshot["types"]]
    assert len(real_ids) >= 2
    a, b = real_ids[0], real_ids[1]
    ts.validate_type_reference(a, [a], snapshot)  # single-function model
    ts.validate_type_reference(a, [a, b], snapshot)  # multi-function model
    with pytest.raises(ts.TypeSnapshotError, match="primaryTypeId"):
        ts.validate_type_reference("nonexistent_equipment_id", [a], snapshot)


# --- P1.G1 T5: cross-language behavioral-parity fixtures ------------------
# The same cases in core/equipment_identity/p1/type_reference_validation_
# fixtures.json also drive functions-equipment-identity/src/p1/__tests__/
# p1_type_snapshot.test.ts's validateTypeReference (the TS port). Both
# languages must agree case-by-case, not just "both raise on invalid input."

_FIXTURES_PATH = (
    Path(__file__).resolve().parents[2]
    / "core" / "equipment_identity" / "p1" / "type_reference_validation_fixtures.json"
)


def _load_shared_fixtures() -> dict:
    return json.loads(_FIXTURES_PATH.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "case",
    _load_shared_fixtures()["cases"],
    ids=lambda case: case["name"],
)
def test_shared_type_reference_validation_fixture_case(case: dict) -> None:
    snapshot = _load_shared_fixtures()["snapshot"]
    if case["valid"]:
        ts.validate_type_reference(case["primaryTypeId"], case["supportedTypeIds"], snapshot)
    else:
        with pytest.raises(ts.TypeSnapshotError, match=re.escape(case["errorContains"])):
            ts.validate_type_reference(case["primaryTypeId"], case["supportedTypeIds"], snapshot)
