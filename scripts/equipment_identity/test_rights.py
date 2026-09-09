# -*- coding: utf-8 -*-
"""P0.G3 tests for scripts/equipment_identity/rights.py.

    python -m pytest scripts/equipment_identity/test_rights.py -q
"""
from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import jsonschema
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rights  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
P0_DIR = REPO / "core" / "equipment_identity" / "p0"

#: A real, committed, synthetic snapshot under the real snapshot root. Most
#: fixtures below redirect the root into `tmp_path`, which is right for the
#: escape cases but would leave the PRODUCTION path — the actual directory,
#: the actual repo-relative resolution — as a phantom nothing ever traverses.
#: This one file means the ordinary REVIEWED fixture exercises it end to end.
SYNTHETIC_SNAPSHOT_REL = (
    "core/equipment_identity/p0/terms_snapshots/synthetic_test_terms.txt"
)
#: Pinned by literal, deliberately. Recomputing it from the file would make
#: this assertion agree with whatever the file happens to contain; pinning it
#: means an edit to those bytes fails loudly instead of quietly re-baselining.
SYNTHETIC_SNAPSHOT_SHA256 = (
    "115f485416170f03685c4db9195f215596cf4913228134f2864896669a4f53c2"
)

#: The object every pre-existing eligibility assertion is now asked about.
#: Adding it was a mechanical adaptation to the new signature: no expected
#: True/False anywhere in this file changed, because `_reviewed_permissive_
#: record` grants WHOLE_SOURCE over this very namespace.
_SUBJECT = rights.SubjectRef("test", "item1")

#: The two things a REVIEWED record now needs beyond what it needed before.
#: Spelled once so that the fixtures which hand-build a REVIEWED record can be
#: brought up to the new contract by adding a name, not by re-deciding what
#: each of those tests was for.
_EVIDENCE = {
    "termsSnapshotPath": SYNTHETIC_SNAPSHOT_REL,
    "termsSnapshotSha256": SYNTHETIC_SNAPSHOT_SHA256,
}
_WHOLE_TEST_SCOPE = {"kind": "WHOLE_SOURCE", "keyNamespace": "test"}


def _base_rights(**overrides) -> dict:
    base = {
        "legalReviewState": "UNREVIEWED",
        "commercialAllowed": False,
        "displayAllowed": False,
        "recognitionProcessingAllowed": False,
        "trainingAllowed": False,
        "derivativeAllowed": False,
        "redistributionAllowed": False,
        "attributionRequired": False,
        "shareAlike": False,
        "noAiRestriction": True,
        "termsCaptured": False,
    }
    base.update(overrides)
    return base


def _base_record(**overrides) -> dict:
    base = {
        "sourceId": "test_source",
        "providerName": "Test Provider",
        "sourceClass": "OFFICIAL_MANUFACTURER",
        "priority": "P0",
        "canonicalUrl": "https://example.com/",
        "retrievedAt": "2026-08-22T00:00:00Z",
        "termsUrl": None,
        "rights": _base_rights(),
    }
    base.update(overrides)
    return base


def _reviewed_permissive_record(**rights_overrides) -> dict:
    """A REVIEWED record that satisfies the evidence/scope matrix.

    The snapshot path/hash and the `rightsScope` are new here, and they are a
    mechanical consequence of the contract change rather than a change of
    intent: REVIEWED now requires byte-bound captured terms and a stated
    population, so a fixture without them is no longer a REVIEWED record at
    all. The scope is WHOLE_SOURCE over `_SUBJECT`'s namespace precisely so
    that every pre-existing assertion in this file keeps its original expected
    answer — the point of these tests did not change, only the shape of the
    record they operate on.
    """
    defaults = {
        "legalReviewState": "REVIEWED",
        "reviewedAt": "2026-08-22T00:00:00Z",
        "noAiRestriction": False,
        "termsCaptured": True,
        "commercialAllowed": True,
        "termsSnapshotPath": SYNTHETIC_SNAPSHOT_REL,
        "termsSnapshotSha256": SYNTHETIC_SNAPSHOT_SHA256,
        "rightsScope": {"kind": "WHOLE_SOURCE", "keyNamespace": "test"},
    }
    defaults.update(rights_overrides)
    return _base_record(rights=_base_rights(**defaults))


# --- registry-level -----------------------------------------------------

def test_every_registry_record_validates_schema():
    sources = rights.load_registry()
    assert len(sources) >= 1
    for record in sources:
        rights.validate_source_record(record)  # must not raise


def test_every_record_has_rights_state():
    sources = rights.load_registry()
    for record in sources:
        assert "rights" in record
        assert record["rights"]["legalReviewState"] in rights.LEGAL_REVIEW_STATES


def test_malformed_timestamp_fails_validation():
    record = _base_record(retrievedAt="not-a-date")
    with pytest.raises(rights.RightsValidationError, match="retrievedAt"):
        rights.validate_source_record(record)


def test_malformed_hash_fails_validation():
    r = _base_rights(termsCaptured=True, termsSnapshotSha256="not-a-hash")
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsSnapshotSha256"):
        rights.validate_source_record(record)


def test_missing_rights_object_fails_validation():
    record = _base_record()
    del record["rights"]
    with pytest.raises(rights.RightsValidationError, match="rights"):
        rights.validate_source_record(record)


def test_source_class_priority_is_deterministic():
    # A record may only declare a priority its sourceClass allows -- not any
    # of the six values freely.
    record = _base_record(sourceClass="WGER", priority="P0")
    with pytest.raises(rights.RightsValidationError, match="priority"):
        rights.validate_source_record(record)


def test_search_discovery_can_never_declare_a_non_discovery_priority():
    record = _base_record(sourceClass="SEARCH_DISCOVERY", priority="P0")
    with pytest.raises(rights.RightsValidationError, match="priority"):
        rights.validate_source_record(record)


# --- fail-closed eligibility ---------------------------------------------

def test_unreviewed_plus_any_requested_privileged_use_denies():
    record = _base_record(rights=_base_rights(
        legalReviewState="UNREVIEWED",
        # Even if every boolean were somehow true, UNREVIEWED must still deny.
    ))
    for use in rights.USES:
        assert rights.eligible_for(record, use, _SUBJECT) is False


def test_unreviewed_record_cannot_carry_a_granted_permission():
    # Structural: validate_source_record refuses UNREVIEWED+True, so the
    # "even if every boolean were true" scenario above can't occur for a
    # record that passes validation in the first place.
    r = _base_rights(legalReviewState="UNREVIEWED", displayAllowed=True)
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="UNREVIEWED"):
        rights.validate_source_record(record)


def test_reviewed_and_allowed_grants_the_specific_use_only():
    record = _reviewed_permissive_record(displayAllowed=True)
    assert rights.eligible_for(record, "DISPLAY", _SUBJECT) is True
    assert rights.eligible_for(record, "TRAINING", _SUBJECT) is False
    assert rights.eligible_for(record, "RECOGNITION_PROCESSING", _SUBJECT) is False
    assert rights.eligible_for(record, "DERIVATIVE", _SUBJECT) is False
    assert rights.eligible_for(record, "REDISTRIBUTION", _SUBJECT) is False


def test_no_ai_restriction_blocks_recognition_training_derivative():
    record = _reviewed_permissive_record(
        recognitionProcessingAllowed=True, trainingAllowed=True,
        derivativeAllowed=True, redistributionAllowed=True, displayAllowed=True,
        noAiRestriction=True,
    )
    assert rights.eligible_for(record, "RECOGNITION_PROCESSING", _SUBJECT) is False
    assert rights.eligible_for(record, "TRAINING", _SUBJECT) is False
    assert rights.eligible_for(record, "DERIVATIVE", _SUBJECT) is False
    # noAiRestriction does not touch DISPLAY/REDISTRIBUTION -- those are not
    # AI processing uses.
    assert rights.eligible_for(record, "DISPLAY", _SUBJECT) is True
    assert rights.eligible_for(record, "REDISTRIBUTION", _SUBJECT) is True


def test_no_ai_restriction_false_on_unreviewed_source_is_not_permission():
    # noAiRestriction=false must never be read as permission on its own --
    # legalReviewState gates every decision before anything else is inspected.
    record = _base_record(rights=_base_rights(
        legalReviewState="UNREVIEWED", noAiRestriction=False,
    ))
    for use in rights.USES:
        assert rights.eligible_for(record, use, _SUBJECT) is False


def test_royalty_free_string_alone_cannot_grant_training():
    # decisionBasis is free text and is never read by any eligibility
    # function -- only the boolean fields are. A record whose decisionBasis
    # says "royalty free" but whose trainingAllowed is false (the honest
    # state for an unreviewed/undetermined source) must still deny training.
    r = _base_rights(
        legalReviewState="UNREVIEWED",
        trainingAllowed=False,
        decisionBasis="royalty free per provider marketing page",
    )
    record = _base_record(rights=r)
    assert rights.eligible_for(record, "TRAINING", _SUBJECT) is False
    # Also true even if legalReviewState were REVIEWED but trainingAllowed
    # was never actually set true by that review. termsCaptured=True here
    # only makes the fixture itself schema-valid (REVIEWED requires it,
    # per validate_rights) -- P1.G1 §6.8 hardening made eligible_for()
    # validate the record before reading any eligibility field, so an
    # inconsistent REVIEWED-without-termsCaptured fixture would now raise
    # RightsValidationError here rather than silently reaching the
    # trainingAllowed=False check this test actually means to exercise.
    r2 = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, **_EVIDENCE, rightsScope=_WHOLE_TEST_SCOPE,
        trainingAllowed=False, noAiRestriction=False,
        decisionBasis="royalty free per provider marketing page",
    )
    record2 = _base_record(rights=r2)
    assert rights.eligible_for(record2, "TRAINING", _SUBJECT) is False


def test_search_discovery_can_never_be_training_or_display_source():
    # Even a (hypothetically miswritten) REVIEWED+allowed SEARCH_DISCOVERY
    # record must still be refused -- the priority check is structural,
    # independent of the rights booleans. Every other gate (review state,
    # commercial clearance, terms captured, no-AI restriction) is
    # deliberately satisfied here so the only possible reason for denial is
    # the DISCOVERY_ONLY priority itself.
    record = _base_record(
        sourceClass="SEARCH_DISCOVERY", priority="DISCOVERY_ONLY",
        rights=_base_rights(
            legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
            displayAllowed=True, trainingAllowed=True, noAiRestriction=False,
            commercialAllowed=True, termsCaptured=True,
            **_EVIDENCE, rightsScope=_WHOLE_TEST_SCOPE,
        ),
    )
    assert rights.eligible_for(record, "DISPLAY", _SUBJECT) is False
    assert rights.eligible_for(record, "TRAINING", _SUBJECT) is False


def test_no_adapter_can_auto_promote_a_source():
    # Structural: this module exposes no function that mutates a record's
    # legalReviewState or any permission boolean -- only load/validate/read
    # eligibility. Promotion is a human editing source_registry.json by hand.
    import inspect
    mutating_names = [
        name for name, obj in vars(rights).items()
        if inspect.isfunction(obj) and (
            "promote" in name.lower() or "approve" in name.lower() or "grant" in name.lower()
        )
    ]
    assert mutating_names == []


def test_validator_never_rewrites_the_registry_file():
    before = rights.SOURCE_REGISTRY.read_bytes()
    rights.load_registry()
    rights.main()
    after = rights.SOURCE_REGISTRY.read_bytes()
    assert before == after


def test_reviewed_state_requires_reviewed_at():
    r = _base_rights(legalReviewState="REVIEWED")
    r.pop("reviewedAt", None)
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="reviewedAt"):
        rights.validate_source_record(record)


def test_terms_snapshot_hash_requires_terms_captured_flag():
    r = _base_rights(termsCaptured=False)
    r["termsSnapshotSha256"] = "a" * 64
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsCaptured"):
        rights.validate_source_record(record)


def test_reviewed_without_terms_captured_fails_validation():
    # A REVIEWED record whose terms were never actually captured is exactly
    # the "review by rumor" gap this registry exists to close -- caught by
    # security-reviewer and silent-failure-hunter independently in the
    # P0.G3 review round.
    r = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        displayAllowed=True, termsCaptured=False,
    )
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="termsCaptured"):
        rights.validate_source_record(record)


def test_blocked_state_cannot_carry_a_granted_permission():
    # BLOCKED means "review happened and the answer was no" -- a BLOCKED
    # record with a true permission boolean is a self-contradictory record
    # and must be rejected at validation, not just silently non-eligible.
    r = _base_rights(
        legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
        displayAllowed=True,
    )
    record = _base_record(rights=r)
    with pytest.raises(rights.RightsValidationError, match="BLOCKED"):
        rights.validate_source_record(record)


def test_commercial_clearance_is_required_for_every_privileged_use():
    # commercialAllowed is a required rights field but was, before this
    # fix, never read by any eligibility function -- a REVIEWED, otherwise-
    # fully-allowed, non-commercially-cleared source must still be refused
    # for every use, since SPTR is itself a commercial product.
    record = _reviewed_permissive_record(
        commercialAllowed=False,
        displayAllowed=True, recognitionProcessingAllowed=True,
        trainingAllowed=True, derivativeAllowed=True, redistributionAllowed=True,
    )
    for use in rights.USES:
        assert rights.eligible_for(record, use, _SUBJECT) is False


def test_load_registry_does_not_mutate_input_records():
    sources = rights.load_registry()
    snapshot = copy.deepcopy(sources)
    for record in sources:
        rights.validate_source_record(record)
        for use in rights.USES:
            rights.eligible_for(record, use, _SUBJECT)
    assert sources == snapshot


# --- P1.G2 review: duplicate sourceId ------------------------------------

def test_load_registry_rejects_a_duplicate_source_id(tmp_path):
    # Reviewer-found gap (P1.G2 review, 2026-08-22): neither load_registry
    # nor the JSON Schema previously checked sourceId uniqueness -- a
    # duplicate would pass every per-record check and silently shadow the
    # original in any consumer keying a {sourceId: record} map.
    duplicate_id = "duplicate_source_for_test"
    registry_path = tmp_path / "source_registry.json"
    registry_path.write_text(
        json.dumps({
            "schemaVersion": 1,
            "sources": [
                _base_record(sourceId=duplicate_id),
                _base_record(sourceId=duplicate_id, providerName="Different Provider"),
            ],
        }),
        encoding="utf-8",
    )
    with pytest.raises(rights.RightsValidationError, match="duplicate sourceId"):
        rights.load_registry(registry_path)


def test_load_registry_accepts_distinct_source_ids(tmp_path):
    registry_path = tmp_path / "source_registry.json"
    registry_path.write_text(
        json.dumps({
            "schemaVersion": 1,
            "sources": [
                _base_record(sourceId="source_one"),
                _base_record(sourceId="source_two"),
            ],
        }),
        encoding="utf-8",
    )
    sources = rights.load_registry(registry_path)
    assert len(sources) == 2


# --- P1.G1 §6.8 hardening: eligible_for() validates before deciding -------

def test_eligible_for_rejects_a_record_that_never_passed_validate_source_record():
    # Before this hardening, a hand-built record that skipped
    # validate_source_record (e.g. missing a required field, or REVIEWED
    # without termsCaptured) could reach an eligibility function directly
    # and either raise an untyped KeyError or silently read a wrong value.
    # eligible_for() must now refuse it the same way validate_source_record
    # itself would, with the same typed error.
    malformed = _base_record(
        rights=_base_rights(legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z"),
        # termsCaptured left False -- REVIEWED requires it true.
    )
    with pytest.raises(rights.RightsValidationError, match="termsCaptured"):
        rights.eligible_for(malformed, "DISPLAY", _SUBJECT)


def test_eligible_for_rejects_a_record_missing_a_required_field():
    malformed = _base_record()
    del malformed["canonicalUrl"]
    with pytest.raises(rights.RightsValidationError, match="canonicalUrl"):
        rights.eligible_for(malformed, "DISPLAY", _SUBJECT)


# --- P1.G1 §6.8 hardening: schema/code consistency (drift becomes CI-visible) ---
#
# rights.py's constants are hand-maintained copies of what
# rights_decision.schema.json and source_registry.schema.json declare (see
# both schema files' own top-of-file comments: "this module is the
# executable enforcement those schemas can only describe"). Nothing before
# this test caught the two drifting apart -- e.g. a future
# `termsCaptured`-class field added to one schema and not the other, or to
# a schema but not rights.py's REQUIRED_*_FIELDS/enums. This test is that
# CI-visible tripwire.

def _load_schema(name: str) -> dict:
    return json.loads((P0_DIR / name).read_text(encoding="utf-8"))


def test_rights_decision_schema_required_fields_match_rights_py():
    schema = _load_schema("rights_decision.schema.json")
    assert set(schema["required"]) == set(rights.REQUIRED_RIGHTS_FIELDS)


def test_rights_decision_schema_legal_review_state_enum_matches_rights_py():
    schema = _load_schema("rights_decision.schema.json")
    assert set(schema["properties"]["legalReviewState"]["enum"]) == set(rights.LEGAL_REVIEW_STATES)


def test_source_registry_schema_required_fields_match_rights_py():
    schema = _load_schema("source_registry.schema.json")
    assert set(schema["required"]) == set(rights.REQUIRED_SOURCE_FIELDS)


def test_source_registry_schema_source_class_enum_matches_rights_py():
    schema = _load_schema("source_registry.schema.json")
    assert set(schema["properties"]["sourceClass"]["enum"]) == set(rights.SOURCE_CLASSES)


def test_source_registry_schema_priority_enum_matches_rights_py():
    schema = _load_schema("source_registry.schema.json")
    assert set(schema["properties"]["priority"]["enum"]) == set(rights.PRIORITIES)


def test_canonical_priorities_by_source_class_covers_every_declared_class():
    # Every sourceClass the schema knows about must have a canonical
    # priority mapping in rights.py -- a class present in the schema but
    # absent from CANONICAL_PRIORITIES_BY_SOURCE_CLASS would KeyError the
    # first time validate_source_record saw a record of that class, rather
    # than failing loudly ahead of time.
    schema = _load_schema("source_registry.schema.json")
    schema_classes = set(schema["properties"]["sourceClass"]["enum"])
    assert schema_classes == set(rights.CANONICAL_PRIORITIES_BY_SOURCE_CLASS.keys())
    for allowed in rights.CANONICAL_PRIORITIES_BY_SOURCE_CLASS.values():
        assert allowed.issubset(rights.PRIORITIES)


# ===========================================================================
# G3 — the rights contract gains bytes, a subject and one shared grammar
# ===========================================================================
#
# Every block below has a negative half, and the guards they cover are
# mutation-checked separately (see the gate report). The recurring failure
# this project has shipped before is a check that passes for a reason other
# than the one it claims, so where two guards could mask each other the
# fixtures are chosen specifically to tell them apart.


@pytest.fixture
def snapshot_root(tmp_path, monkeypatch):
    """Relocate the whole repository, not just the snapshot directory.

    `termsSnapshotPath` is recorded relative to the repository root and then
    confined to the snapshot root, so a test that moved only one of the two
    would exercise a path shape that cannot occur in production. Rebuilding
    the real layout under `tmp_path` keeps the recorded paths identical in
    form to the ones a real record would carry.
    """
    root = tmp_path / "core" / "equipment_identity" / "p0" / "terms_snapshots"
    root.mkdir(parents=True)
    monkeypatch.setattr(rights, "REPO", tmp_path)
    monkeypatch.setattr(rights, "TERMS_SNAPSHOT_ROOT", root)
    return root


def _rel(name: str) -> str:
    return f"core/equipment_identity/p0/terms_snapshots/{name}"


def _captured_rights(path_value, sha256, **overrides) -> dict:
    fields = {"termsCaptured": True, "termsSnapshotPath": path_value,
              "termsSnapshotSha256": sha256}
    fields.update(overrides)
    return _base_rights(**fields)


def _write_snapshot(root: Path, name: str, body: bytes) -> str:
    (root / name).write_bytes(body)
    return hashlib.sha256(body).hexdigest()


# --- the snapshot is bound to bytes, not to a well-formed string -----------

def test_captured_terms_require_a_path_not_only_a_hash(snapshot_root):
    r = _base_rights(termsCaptured=True, termsSnapshotSha256="0" * 64)
    with pytest.raises(rights.RightsValidationError, match="termsSnapshotPath"):
        rights.validate_rights(r, context="t")


def test_captured_terms_require_a_hash_not_only_a_path(snapshot_root):
    r = _base_rights(termsCaptured=True, termsSnapshotPath=_rel("x.txt"))
    with pytest.raises(rights.RightsValidationError, match="termsSnapshotSha256"):
        rights.validate_rights(r, context="t")


def test_a_path_pointing_at_no_file_is_refused(snapshot_root):
    r = _captured_rights(_rel("absent.txt"), "0" * 64)
    with pytest.raises(rights.RightsValidationError, match="not a regular file"):
        rights.validate_rights(r, context="t")


def test_a_hash_that_does_not_match_the_bytes_is_refused(snapshot_root):
    _write_snapshot(snapshot_root, "terms.txt", b"the real terms")
    # A perfectly well-formed sha256 that simply is not this file's.
    r = _captured_rights(_rel("terms.txt"), "a" * 64)
    with pytest.raises(rights.RightsValidationError, match="hash to"):
        rights.validate_rights(r, context="t")


def test_the_exact_snapshot_and_its_true_hash_are_accepted(snapshot_root):
    digest = _write_snapshot(snapshot_root, "terms.txt", b"the real terms")
    rights.validate_rights(_captured_rights(_rel("terms.txt"), digest), context="t")


def test_editing_the_snapshot_after_the_fact_invalidates_the_decision(snapshot_root):
    """The whole point, stated as a test: the declared hash stays put and only
    the bytes change. If this passed, nothing would be reading the file."""
    digest = _write_snapshot(snapshot_root, "terms.txt", b"the real terms")
    r = _captured_rights(_rel("terms.txt"), digest)
    rights.validate_rights(r, context="t")
    (snapshot_root / "terms.txt").write_bytes(b"the real terms, quietly amended")
    with pytest.raises(rights.RightsValidationError, match="hash to"):
        rights.validate_rights(r, context="t")


def test_the_committed_synthetic_fixture_resolves_under_the_real_root():
    """Exercise the production path itself — the real repo root, the real
    snapshot directory, the real relative resolution — so that directory is
    not a phantom every test politely steps around."""
    rights.validate_rights(
        _captured_rights(SYNTHETIC_SNAPSHOT_REL, SYNTHETIC_SNAPSHOT_SHA256),
        context="t",
    )
    on_disk = (REPO / SYNTHETIC_SNAPSHOT_REL).read_bytes()
    assert hashlib.sha256(on_disk).hexdigest() == SYNTHETIC_SNAPSHOT_SHA256


# --- confinement: ONE fixture per guard, so a mutant cannot hide -----------
#
# Guard A is the `..` ban. Guard B resolves and requires containment in the
# snapshot root. The portable-path grammar sits before both and rejects the
# absolute, drive, UNC, stream-syntax and non-ASCII forms by shape.
#
# A `..` path that resolves OUTSIDE the root is caught by both guards, so it
# proves neither. The two fixtures below are each caught by exactly one:
#   * `sub/../terms.txt` resolves INSIDE the root and matches the grammar —
#     only Guard A refuses it.
#   * an in-root link to a file outside contains no `..` at all and matches
#     the grammar — only Guard B refuses it.
#
# There is deliberately no fourth guard for the absolute/drive/UNC class. One
# existed and was removed after a closure review proved it unkillable: see
# `test_the_absolute_path_class_is_the_grammars_job_not_a_dead_guards` below
# for the measurement, which is the reason rather than an assertion about it.

def test_an_absolute_posix_path_is_refused(snapshot_root):
    r = _captured_rights("/etc/passwd", "0" * 64)
    with pytest.raises(rights.RightsValidationError, match="must be relative"):
        rights.validate_rights(r, context="t")


def test_an_absolute_windows_path_is_refused(snapshot_root):
    r = _captured_rights("C:\\Windows\\win.ini", "0" * 64)
    with pytest.raises(rights.RightsValidationError, match="must be relative"):
        rights.validate_rights(r, context="t")


def test_a_unc_path_is_refused(snapshot_root):
    r = _captured_rights("\\\\server\\share\\terms.txt", "0" * 64)
    with pytest.raises(rights.RightsValidationError, match="must be relative"):
        rights.validate_rights(r, context="t")


def test_the_absolute_path_class_is_the_grammars_job_not_a_dead_guards():
    """Why there is no separate absolute/drive/UNC check any more.

    The three tests above still pass, and the class is still refused — but a
    dedicated guard for it could be deleted with every test staying green,
    because everything that makes a path absolute is already outside the
    grammar's alphabet. A guard indistinguishable from its own absence is not
    defence in depth; it is a claim, and this file exists to stop claims that
    are broader than their checks.

    So the subsumption is asserted here rather than asserted about: an
    exhaustive search over the grammar's own alphabet plus the four characters
    that could possibly make a path absolute, up to length 4, looking for ONE
    string the grammar accepts and an absolute check would reject. If such a
    string is ever found, the guard becomes provable and should come back —
    this test failing is the signal to bring it back, not to delete the test.
    """
    import itertools
    from pathlib import PureWindowsPath, PurePosixPath

    def would_have_been_rejected(value: str) -> bool:
        w, p = PureWindowsPath(value), PurePosixPath(value)
        return w.is_absolute() or p.is_absolute() or bool(w.drive) or bool(w.root)

    alphabet = "aZ0._-/:\\ "
    distinguishing = [
        "".join(t)
        for n in range(1, 5)
        for t in itertools.product(alphabet, repeat=n)
        if rights._SNAPSHOT_PATH_RE.search("".join(t))
        and would_have_been_rejected("".join(t))
    ]
    assert distinguishing == [], (
        "the absolute/drive/UNC guard would now be separately provable on "
        f"{distinguishing[:5]} — restore it, with that fixture as its test"
    )
    # And the premise, so this cannot pass by searching nothing: the same
    # space really does contain strings the grammar accepts.
    accepted = [
        "".join(t)
        for n in range(1, 4)
        for t in itertools.product(alphabet, repeat=n)
        if rights._SNAPSHOT_PATH_RE.search("".join(t))
    ]
    assert len(accepted) > 100, f"the search space was nearly empty: {len(accepted)}"


def test_guard_a_refuses_dotdot_even_when_it_resolves_back_inside(snapshot_root):
    """The fixture that isolates the lexical guard.

    `sub/../terms.txt` resolves to a real file inside the snapshot root, so
    resolved containment accepts it happily. Only the `..` ban refuses it —
    which is what makes this fixture able to kill a mutant that deletes only
    that ban, and unable to be rescued by the other guard.
    """
    digest = _write_snapshot(snapshot_root, "terms.txt", b"inside all along")
    (snapshot_root / "sub").mkdir()
    dirty = _rel("sub/../terms.txt")
    assert (rights.REPO / dirty).resolve() == (snapshot_root / "terms.txt").resolve()
    with pytest.raises(rights.RightsValidationError, match=r"'\.\.' component"):
        rights.validate_rights(_captured_rights(dirty, digest), context="t")


def _make_escape_link(root: Path, outside: Path) -> str | None:
    """An in-root name whose resolved target is outside the root, containing
    no `..` anywhere. Returns the recorded path, or None if this machine can
    make neither a junction nor a symlink.

    Windows needs Developer Mode or elevation for `os.symlink`, but a
    DIRECTORY JUNCTION needs neither and `Path.resolve()` follows it — so the
    usual "skipped on Windows" outcome is avoidable here, and a security guard
    that is only ever proven on someone else's machine is not really proven.
    """
    link = root / "escape"
    try:
        os.symlink(outside, link, target_is_directory=True)
        return _rel("escape/terms.txt")
    except (OSError, NotImplementedError, AttributeError):
        pass
    if os.name == "nt":
        completed = subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(link), str(outside)],
            capture_output=True, text=True,
        )
        if completed.returncode == 0:
            return _rel("escape/terms.txt")
    return None


def test_guard_b_refuses_a_lexically_clean_link_out_of_the_root(snapshot_root, tmp_path):
    """The fixture that isolates resolved containment.

    The recorded path is `.../terms_snapshots/escape/terms.txt`: no `..`, no
    drive, not absolute — the lexical guard has nothing to object to. Only
    resolving it reveals that `escape` is a link and the file is elsewhere.
    """
    outside = tmp_path / "somewhere_else"
    outside.mkdir()
    body = b"terms that live outside the repository"
    (outside / "terms.txt").write_bytes(body)
    recorded = _make_escape_link(snapshot_root, outside)
    if recorded is None:
        pytest.skip(
            "cannot create a symlink or a directory junction on this machine; "
            "this SKIP is not evidence that resolved containment works — the "
            "gate report must carry a run from a machine that could"
        )
    assert ".." not in recorded
    assert not Path(recorded).is_absolute()
    with pytest.raises(rights.RightsValidationError, match="outside the snapshot root"):
        rights.validate_rights(
            _captured_rights(recorded, hashlib.sha256(body).hexdigest()), context="t"
        )


def test_a_directory_is_not_a_snapshot(snapshot_root):
    (snapshot_root / "adirectory").mkdir()
    r = _captured_rights(_rel("adirectory"), "0" * 64)
    with pytest.raises(rights.RightsValidationError, match="not a regular file"):
        rights.validate_rights(r, context="t")


# --- the identifier grammar, and why it is spelled so oddly ----------------

_ID_CASES = json.loads(
    (Path(__file__).resolve().parent / "scope_identifier_cases.json").read_text(
        encoding="utf-8"
    )
)


@pytest.mark.parametrize("value", _ID_CASES["valid"])
def test_python_accepts_every_valid_identifier(value):
    assert rights._IDENTIFIER_RE.search(value), value


@pytest.mark.parametrize("value", _ID_CASES["invalid"])
def test_python_refuses_every_invalid_identifier(value):
    assert not rights._IDENTIFIER_RE.search(value), repr(value)


def test_the_cross_runtime_cases_are_all_refused():
    """The four inputs on which two engines given byte-identical patterns
    disagree. They are listed separately from the rest because they are the
    reason the grammar avoids `\\S` and `$` at all; if this ever passes for
    a pattern that uses either, the parity claim is false."""
    for value in _ID_CASES["cross_runtime"]:
        assert value in _ID_CASES["invalid"], repr(value)
        assert not rights._IDENTIFIER_RE.search(value), repr(value)


def test_a_trailing_newline_is_refused_which_a_dollar_anchor_would_allow():
    """Python's `$` matches just before a trailing newline; JavaScript's does
    not. Pinned as its own test because the difference is invisible in the
    pattern text and someone will eventually 'tidy' the end assertion."""
    assert re.search(r"^[A-Za-z0-9]+$", "abc\n"), "premise: Python's $ allows it"
    assert not rights._IDENTIFIER_RE.search("abc\n")


def test_subject_ref_refuses_an_identity_that_is_nothing():
    for namespace, key in [("", "k"), ("  ", "k"), ("ns", ""), ("ns", " ")]:
        with pytest.raises(rights.RightsValidationError, match="scope identifier"):
            rights.SubjectRef(namespace, key)


def test_subject_ref_refuses_a_non_string_identity():
    with pytest.raises(rights.RightsValidationError, match="scope identifier"):
        rights.SubjectRef(None, "k")
    with pytest.raises(rights.RightsValidationError, match="scope identifier"):
        rights.SubjectRef("ns", 123)


def test_frozen_alone_would_not_have_been_enough():
    """`@dataclass(frozen=True)` prevents reassignment and says nothing about
    content. This test states the distinction, because an earlier draft of
    this contract claimed frozen-ness delivered the invariant."""
    subject = rights.SubjectRef("ns", "k")
    with pytest.raises(Exception):
        subject.key = "other"          # frozen: this is what frozen buys
    with pytest.raises(rights.RightsValidationError):
        rights.SubjectRef("", "")      # content: this is what __post_init__ buys


def test_a_scope_with_an_empty_namespace_is_refused():
    record = _reviewed_permissive_record(
        displayAllowed=True, rightsScope={"kind": "WHOLE_SOURCE", "keyNamespace": ""},
    )
    with pytest.raises(rights.RightsValidationError, match="keyNamespace"):
        rights.validate_source_record(record)


def test_a_subset_covering_nothing_is_refused():
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "SUBSET", "keyNamespace": "test", "keys": []},
    )
    with pytest.raises(rights.RightsValidationError, match="non-empty array"):
        rights.validate_source_record(record)


def test_a_subset_key_that_is_not_an_identifier_is_refused():
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "SUBSET", "keyNamespace": "test", "keys": ["ok", " "]},
    )
    with pytest.raises(rights.RightsValidationError, match="keys entry"):
        rights.validate_source_record(record)


def test_an_unrecognised_scope_kind_grants_nothing():
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "EVERYTHING_FOREVER", "keyNamespace": "test"},
    )
    with pytest.raises(rights.RightsValidationError, match="rightsScope.kind"):
        rights.validate_source_record(record)


# --- the evidence/scope matrix, all four rows ------------------------------

def test_unreviewed_without_capture_may_not_carry_a_snapshot():
    r = _base_rights(termsCaptured=False, termsSnapshotSha256="0" * 64)
    with pytest.raises(rights.RightsValidationError, match="termsCaptured=false"):
        rights.validate_rights(r, context="t")


def test_unreviewed_may_capture_terms_before_anyone_reviews_them(snapshot_root):
    """Capture-before-review, preserved deliberately.

    P0_G3_RIGHTS_GOVERNANCE.md states that `termsCaptured` is factual metadata
    independent of review — a source can honestly have its terms captured and
    still be entirely unreviewed. An earlier draft of this gate would have
    forbidden exactly this, fusing capture and legal review into one atomic
    act. What the matrix requires is that a capture be re-checkable, never
    that it wait for a review.
    """
    digest = _write_snapshot(snapshot_root, "terms.txt", b"captured, not yet read")
    rights.validate_rights(_captured_rights(_rel("terms.txt"), digest), context="t")


def test_captured_evidence_is_not_by_itself_a_permission(snapshot_root):
    """The other half of the row above: having the terms on disk grants
    nothing until a human has read them and said so."""
    digest = _write_snapshot(snapshot_root, "terms.txt", b"captured, not yet read")
    record = _base_record(rights=_captured_rights(_rel("terms.txt"), digest))
    for use in rights.USES:
        assert rights.eligible_for(record, use, _SUBJECT) is False


def test_an_unreviewed_record_carrying_a_permission_is_refused(snapshot_root):
    """The OUTER of the two guards behind capture-is-not-permission: an
    UNREVIEWED record may not even be built with a true permission boolean, so
    the eligibility layer never sees one. Kept as its own test because the
    inner guard (`_reviewed`) is unreachable from here while this one holds —
    see `test_reviewed_predicate_is_the_inner_guard`."""
    digest = _write_snapshot(snapshot_root, "terms.txt", b"captured, not yet read")
    r = _captured_rights(_rel("terms.txt"), digest, displayAllowed=True)
    with pytest.raises(rights.RightsValidationError, match="already true"):
        rights.validate_rights(r, context="t")


def test_reviewed_predicate_is_the_inner_guard(snapshot_root):
    """Deliberately white-box, and it has to be.

    Capture-is-not-permission is defended twice: validation refuses an
    UNREVIEWED record carrying a permission, and `_reviewed()` separately gates
    on `legalReviewState`. With the first guard standing, NO record reachable
    through the public API can distinguish the second — so the only way to
    show the inner layer is real is to hand a per-use predicate a record that
    never went through validation. Reported as defence in depth with one
    publicly provable layer, rather than as one invariant proven twice.

    **The fixture is invalid in exactly ONE dimension, and that took a second
    attempt.** The first version omitted `rightsScope` as well as being
    UNREVIEWED. Under the mutation that makes `_reviewed()` accept captured
    terms, execution then fell through to `_subject_in_scope`, which reads that
    missing scope and raised `KeyError` — pytest went red, the harness counted
    a kill, and nothing whatever had been shown about `_reviewed()`. A mutant
    killed by an unrelated exception is the same masked-proof defect this gate
    exists to remove. So the scope is present and well-formed here: the ONLY
    thing wrong with this record is its state, and the mutation must therefore
    flip the answer from False to True rather than crash on the way.
    """
    digest = _write_snapshot(snapshot_root, "terms.txt", b"captured, not yet read")
    unvalidated = _base_record(
        rights=_captured_rights(
            _rel("terms.txt"), digest, displayAllowed=True, commercialAllowed=True,
            rightsScope=_WHOLE_TEST_SCOPE,
        )
    )
    # Everything except the state is in order: the subject is in scope, the use
    # is allowed, commercial clearance is present, the priority is fine.
    assert rights._subject_in_scope(unvalidated, _SUBJECT) is True
    assert rights._eligible_for_display(unvalidated, _SUBJECT) is False


def test_unreviewed_may_not_carry_a_scope():
    r = _base_rights(rightsScope=_WHOLE_TEST_SCOPE)
    with pytest.raises(rights.RightsValidationError, match="must not carry rightsScope"):
        rights.validate_rights(r, context="t")


def test_reviewed_without_a_scope_is_refused():
    r = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, **_EVIDENCE,
    )
    with pytest.raises(rights.RightsValidationError, match="requires rightsScope"):
        rights.validate_rights(r, context="t")


def test_blocked_must_carry_captured_terms():
    r = _base_rights(legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z")
    with pytest.raises(rights.RightsValidationError, match="requires termsCaptured=true"):
        rights.validate_rights(r, context="t")


def test_blocked_is_bound_to_the_bytes_like_any_other_conclusion():
    r = _base_rights(
        legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, termsSnapshotPath=SYNTHETIC_SNAPSHOT_REL,
        termsSnapshotSha256="b" * 64,
    )
    with pytest.raises(rights.RightsValidationError, match="hash to"):
        rights.validate_rights(r, context="t")


def test_blocked_may_not_carry_a_scope():
    r = _base_rights(
        legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, **_EVIDENCE, rightsScope=_WHOLE_TEST_SCOPE,
    )
    with pytest.raises(rights.RightsValidationError, match="must not carry rightsScope"):
        rights.validate_rights(r, context="t")


# --- scope: one record, two subjects ---------------------------------------

def test_one_record_grants_one_subject_and_denies_another():
    """The pair the previous contract could not express at all.

    Same record, same use, same everything — only the key differs. Before
    `rightsScope` and `SubjectRef`, a grant was source-wide and there was
    nothing for these two calls to disagree about.
    """
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "SUBSET", "keyNamespace": "wger", "keys": ["123"]},
    )
    assert rights.eligible_for(record, "DISPLAY", rights.SubjectRef("wger", "123")) is True
    assert rights.eligible_for(record, "DISPLAY", rights.SubjectRef("wger", "999")) is False


def test_the_namespace_reaches_the_authorization_boundary():
    """Same key, different namespace. Two upstream catalogues can each number
    an item `123`; if the namespace were recorded but never consulted, both
    calls would answer alike and the scope would be identifying nothing."""
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "SUBSET", "keyNamespace": "wger", "keys": ["123"]},
    )
    assert rights.eligible_for(record, "DISPLAY", rights.SubjectRef("wger", "123")) is True
    assert rights.eligible_for(
        record, "DISPLAY", rights.SubjectRef("exercisedb", "123")
    ) is False


def test_whole_source_admits_any_key_but_not_any_namespace():
    """WHOLE_SOURCE trusts upstream provenance about membership — the registry
    has no population oracle and cannot know a key does NOT belong. It does
    not trust the caller about which catalogue they are in, because the source
    declares that itself."""
    record = _reviewed_permissive_record(
        displayAllowed=True,
        rightsScope={"kind": "WHOLE_SOURCE", "keyNamespace": "wger"},
    )
    assert rights.eligible_for(
        record, "DISPLAY", rights.SubjectRef("wger", "never-seen-before")
    ) is True
    assert rights.eligible_for(
        record, "DISPLAY", rights.SubjectRef("exercisedb", "never-seen-before")
    ) is False


def test_a_permission_cannot_be_obtained_without_naming_an_object():
    record = _reviewed_permissive_record(displayAllowed=True)
    for bad in [None, "wger:123", ("wger", "123"), 123]:
        with pytest.raises(rights.RightsValidationError, match="needs the object"):
            rights.eligible_for(record, "DISPLAY", bad)


# --- non-bypassability, by what the module exposes rather than by naming ----

def test_no_module_level_container_publishes_a_permission_callable():
    """The check that the previous draft of this gate got wrong.

    That draft proposed grepping for a public `eligible_for_*` helper. It
    would have passed while `ELIGIBILITY_BY_USE` — a module-level dict whose
    VALUES were those same five functions — still let any caller write
    `ELIGIBILITY_BY_USE["DISPLAY"](record)` and receive a permission with no
    subject at all. Renaming the functions would not have closed that; not
    publishing callables does. So this walks the module's own assignments and
    asks what they actually hold.
    """
    import ast
    import inspect

    tree = ast.parse(Path(rights.__file__).read_text(encoding="utf-8"))
    module_level_names = {
        target.id
        for node in tree.body if isinstance(node, (ast.Assign, ast.AnnAssign))
        for target in (node.targets if isinstance(node, ast.Assign) else [node.target])
        if isinstance(target, ast.Name)
    }
    assert "USES" in module_level_names, "the AST walk found no assignments at all"

    offenders = []
    for name in module_level_names:
        value = getattr(rights, name, None)
        if isinstance(value, (dict, list, tuple, set, frozenset)):
            members = value.values() if isinstance(value, dict) else value
            for member in members:
                if callable(member) and not name.startswith("_"):
                    offenders.append(f"{name} -> {getattr(member, '__name__', member)}")
    assert offenders == [], (
        f"a public module-level container publishes callable(s): {offenders}. "
        "That is a route to a permission that never passes through eligible_for()"
    )


def test_every_dispatched_predicate_demands_the_subject_itself():
    """Belt AND braces, deliberately.

    The dispatch table being private is one defence; each entry independently
    refusing to answer without a `SubjectRef` is the other. Either alone would
    be defeatable — a leading underscore is a convention, and a front-door
    check is only as good as the front door being the only door.
    """
    import inspect

    assert set(rights._ELIGIBILITY_BY_USE) == set(rights.USES)
    record = _reviewed_permissive_record(displayAllowed=True)
    for use, predicate in rights._ELIGIBILITY_BY_USE.items():
        assert "subject" in inspect.signature(predicate).parameters, use
        with pytest.raises(rights.RightsValidationError, match="needs the object"):
            predicate(record, None)


def test_uses_publishes_names_not_functions():
    assert rights.USES == tuple(sorted(rights.USES, key=list(rights.USES).index))
    assert all(isinstance(u, str) for u in rights.USES)
    assert not hasattr(rights, "ELIGIBILITY_BY_USE"), (
        "the public callable dispatch table is back; it was the actual bypass"
    )


# --- the JSON Schema as an executable artifact, not as documentation -------

def _rights_schema_validator() -> jsonschema.Draft7Validator:
    schema = json.loads((P0_DIR / "rights_decision.schema.json").read_text(encoding="utf-8"))
    jsonschema.Draft7Validator.check_schema(schema)
    return jsonschema.Draft7Validator(schema)


@pytest.mark.parametrize("value", _ID_CASES["valid"])
def test_schema_accepts_every_valid_identifier(value):
    validator = _rights_schema_validator()
    r = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, **_EVIDENCE,
        rightsScope={"kind": "WHOLE_SOURCE", "keyNamespace": value},
    )
    assert list(validator.iter_errors(r)) == [], value


@pytest.mark.parametrize("value", _ID_CASES["invalid"])
def test_schema_refuses_every_invalid_identifier(value):
    validator = _rights_schema_validator()
    r = _base_rights(
        legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
        termsCaptured=True, **_EVIDENCE,
        rightsScope={"kind": "WHOLE_SOURCE", "keyNamespace": value},
    )
    assert list(validator.iter_errors(r)) != [], repr(value)


def test_schema_and_rights_py_agree_on_the_whole_matrix():
    """The same fixtures through both layers.

    Documentation asserting that three artifacts agree is not evidence, and
    neither is the pattern text being identical in all three files — that is
    exactly what the previous draft mistook for semantic equality. What counts
    is one fixture set and three engines answering.
    """
    validator = _rights_schema_validator()
    cases = {
        "unreviewed, nothing extra": (_base_rights(), True),
        "unreviewed + snapshot without the flag": (
            _base_rights(termsSnapshotPath=SYNTHETIC_SNAPSHOT_REL), False),
        "unreviewed + captured, bound": (
            _captured_rights(SYNTHETIC_SNAPSHOT_REL, SYNTHETIC_SNAPSHOT_SHA256), True),
        "unreviewed + captured, no path": (
            _base_rights(termsCaptured=True, termsSnapshotSha256=SYNTHETIC_SNAPSHOT_SHA256),
            False),
        "unreviewed + a scope": (_base_rights(rightsScope=_WHOLE_TEST_SCOPE), False),
        "reviewed, complete": (
            _base_rights(
                legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
                termsCaptured=True, **_EVIDENCE, rightsScope=_WHOLE_TEST_SCOPE,
            ), True),
        "reviewed, no scope": (
            _base_rights(
                legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
                termsCaptured=True, **_EVIDENCE,
            ), False),
        "reviewed, no capture": (
            _base_rights(
                legalReviewState="REVIEWED", reviewedAt="2026-08-22T00:00:00Z",
                rightsScope=_WHOLE_TEST_SCOPE,
            ), False),
        "blocked, complete": (
            _base_rights(
                legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
                termsCaptured=True, **_EVIDENCE,
            ), True),
        "blocked + a scope": (
            _base_rights(
                legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z",
                termsCaptured=True, **_EVIDENCE, rightsScope=_WHOLE_TEST_SCOPE,
            ), False),
        "blocked, no capture": (
            _base_rights(legalReviewState="BLOCKED", reviewedAt="2026-08-22T00:00:00Z"),
            False),
    }
    disagreements = []
    for label, (payload, expected_valid) in cases.items():
        schema_ok = not list(validator.iter_errors(payload))
        try:
            rights.validate_rights(copy.deepcopy(payload), context="t")
            python_ok = True
        except rights.RightsValidationError:
            python_ok = False
        if (schema_ok, python_ok) != (expected_valid, expected_valid):
            disagreements.append(
                f"{label}: schema={schema_ok} rights.py={python_ok} expected={expected_valid}"
            )
    assert disagreements == [], disagreements


def test_schema_documents_the_snapshot_path_it_now_requires():
    schema = json.loads((P0_DIR / "rights_decision.schema.json").read_text(encoding="utf-8"))
    assert "termsSnapshotPath" in schema["properties"]
    assert "rightsScope" in schema["properties"]
    # The stale half: the enum description used to say "ideally with
    # termsSnapshotSha256" while rights.py required nothing at all, and the
    # sha256 field's own description already claimed rights.py enforced it.
    # Both now say the same thing, and it is now true.
    assert "ideally" not in schema["properties"]["legalReviewState"]["description"]


def test_the_shared_identifier_pattern_is_literally_the_same_text():
    """Necessary, and openly not sufficient.

    Identical text is what the previous draft mistook for identical meaning;
    the tests that actually establish parity are the per-engine case runs
    above and their counterpart in the jest suite. This one only catches the
    cheaper failure of someone editing one copy and not the others.
    """
    schema = json.loads((P0_DIR / "rights_decision.schema.json").read_text(encoding="utf-8"))
    assert schema["definitions"]["scopeIdentifier"]["pattern"] == rights.IDENTIFIER_PATTERN
    contracts = (
        REPO / "functions-equipment-identity" / "src" / "p1" / "contracts.ts"
    ).read_text(encoding="utf-8")
    # The TypeScript source escapes the backslashes for its string literal.
    assert rights.IDENTIFIER_PATTERN.replace("\\", "\\\\") in contracts


# ===========================================================================
# Remediation of the closure review: an NTFS stream escape, a mutant killed
# by the wrong exception, parity that covered only one field, and an AST walk
# that did not walk functions.
# ===========================================================================

def test_an_alternate_data_stream_is_not_a_repository_file(snapshot_root):
    """`terms.txt:legal-review` is lexically innocent — not absolute, no
    drive, no `..`, inside the declared directory, resolving to a regular
    file — and on NTFS it addresses a SEPARATE stream whose bytes Git never
    stored and which `.gitattributes -text` cannot preserve.

    Measured before this guard existed: such a record validated and its hash
    matched, so a legal decision could be bound to bytes that simply do not
    exist in a fresh checkout. The colon is refused on every platform, not
    only Windows: a path naming one file on Linux and a hidden stream on
    Windows is not the portable repository reference this field claims to be,
    and a rule that changes by platform is not a contract.
    """
    main = snapshot_root / "tracked.txt"
    main.write_bytes(b"the tracked bytes")
    recorded = _rel("tracked.txt:legal-review")

    # The lexical guards that already existed have nothing to object to here,
    # which is the whole point of the case.
    assert not Path(recorded).is_absolute()
    assert ".." not in recorded

    hidden = b"BYTES GIT NEVER SAW"
    try:
        with open(str(main) + ":legal-review", "wb") as stream:
            stream.write(hidden)
        stream_exists = True
    except OSError:
        stream_exists = False  # not NTFS; the guard is still asserted below

    with pytest.raises(rights.RightsValidationError, match="portable relative path"):
        rights.validate_rights(
            _captured_rights(recorded, hashlib.sha256(hidden).hexdigest()), context="t"
        )
    if stream_exists:
        # The refusal is not incidental to the stream being absent: the bytes
        # really were there and really did hash to the recorded digest.
        with open(str(main) + ":legal-review", "rb") as stream:
            assert stream.read() == hidden


@pytest.mark.parametrize("value", _ID_CASES["snapshot_path_valid"])
def test_python_accepts_every_valid_snapshot_path(value):
    assert rights._SNAPSHOT_PATH_RE.search(value), repr(value)


@pytest.mark.parametrize("value", _ID_CASES["snapshot_path_invalid"])
def test_python_refuses_every_invalid_snapshot_path(value):
    assert not rights._SNAPSHOT_PATH_RE.search(value), repr(value)


@pytest.mark.parametrize("value", _ID_CASES["sha256_valid"])
def test_python_accepts_every_valid_digest(value):
    assert rights._SHA256_RE.search(value), repr(value)


@pytest.mark.parametrize("value", _ID_CASES["sha256_invalid"])
def test_python_refuses_every_invalid_digest(value):
    assert not rights._SHA256_RE.search(value), repr(value)


def test_a_digest_with_a_trailing_newline_would_have_passed_under_a_dollar():
    """The same `$` defect the identifier grammar fixed, left in the digest
    rule until a review found it. Pinned so it cannot come back."""
    assert re.search(r"^[0-9a-f]{64}$", "a" * 64 + "\n"), "premise: Python's $ allows it"
    assert not rights._SHA256_RE.search("a" * 64 + "\n")


@pytest.mark.parametrize("value", _ID_CASES["snapshot_path_invalid"])
def test_schema_refuses_every_invalid_snapshot_path(value):
    validator = _rights_schema_validator()
    r = _base_rights(
        termsCaptured=True, termsSnapshotPath=value,
        termsSnapshotSha256=SYNTHETIC_SNAPSHOT_SHA256,
    )
    assert list(validator.iter_errors(r)) != [], repr(value)


@pytest.mark.parametrize("value", _ID_CASES["sha256_invalid"])
def test_schema_refuses_every_invalid_digest(value):
    validator = _rights_schema_validator()
    r = _base_rights(
        termsCaptured=True, termsSnapshotPath=SYNTHETIC_SNAPSHOT_REL,
        termsSnapshotSha256=value,
    )
    assert list(validator.iter_errors(r)) != [], repr(value)


@pytest.mark.parametrize("value", _ID_CASES["snapshot_path_valid"])
def test_schema_accepts_every_valid_snapshot_path(value):
    validator = _rights_schema_validator()
    r = _base_rights(
        termsCaptured=True, termsSnapshotPath=value,
        termsSnapshotSha256=SYNTHETIC_SNAPSHOT_SHA256,
    )
    assert list(validator.iter_errors(r)) == [], repr(value)


def _permission_routes_without_a_subject(source: str, permission_fields) -> tuple:
    """Every module-level name that can hand out a permission answer without
    the caller supplying a subject, plus the set of names that can reach one.

    Returned as a pair so a test can assert both halves: that nothing is an
    offender, and that the rule matched something. A check whose rule matches
    nothing passes for the wrong reason, which is the defect this file keeps
    finding elsewhere.

    ## Six rounds of review, one mistake

    Every earlier version was correct about the FORM in front of it and wrong
    about the CLASS:

    1. a `PERMISSION_FIELDS` literal — missed a wrapper that only CALLS;
    2. a call graph — missed `_ELIGIBILITY_BY_USE[use](...)`, a call on a
       Subscript, so no edge at all;
    3. a reference graph judging `FunctionDef` — missed
       `export = lambda record: eligible_for(...)`;
    4. a parameter *named* `subject`, containers exempt, no class node;
    5. a fallback that said fail-closed and returned False, sinks seeded from
       `def`s only, and four statement types' worth of binding discovery;
    6. and then: one binding remembered per name, so a safe alias followed by
       an unsafe rebind read clean; a scope walker that dropped a `def` nested
       in module-level control flow; and a sink seeder still enumerating
       callable SHAPES, so `operator.itemgetter("displayAllowed")` and a
       class-level lambda never entered the graph.

    ## The three rules, none of them a list of syntax

    **Binding.** An explicit descent over module-scope statements, carrying a
    `conditional` flag. Every name bound at module scope is recorded WITH its
    position and whether it was reached unconditionally: `def`, `class`,
    assignment, `for` target, walrus (including one in a function default or
    a comprehension, which execute in the enclosing scope), `with ... as`,
    `except ... as`, and `match` captures. Nested scopes' BODIES bind their own
    names and are not descended into; the expressions around them are.

    A name can be bound more than once, and Python keeps the last one that
    runs. So the effective set is every binding at or after the last
    UNCONDITIONAL one — an earlier binding cannot survive an unconditional
    rebind, and a conditional one after it might. A name is an offender if ANY
    binding in that set is.

    **Reaching.** Edges are NAME REFERENCES, not calls, so a dispatch table
    relays and a subscript call is not a hole. Seeds are names whose value
    contains a permission-field literal and is not provably PASSIVE DATA — a
    constant, or a container/`frozenset(...)` of constants. That exception is
    what keeps `PERMISSION_FIELDS`, a tuple of exactly those strings, from
    being a sink and making every record validator inherit a subject
    requirement it has no use for. Everything else carrying such a literal
    seeds, whatever syntax produced it. Propagation runs to a fixed point.

    **Judging.** One question of every reaching name: *what callable does this
    expose, and can it be invoked without a MANDATORY subject?* A parameter
    named `subject` is not enough — `args.defaults`, `kw_defaults` and
    `posonlyargs` decide. A lambda is judged on its own args; an alias
    inherits the aliased signature; a container, `IfExp`, `BoolOp` or
    `Starred` recursively on every branch it can yield; a class on its
    methods AND its class-level attributes; `X = SomeClass()` on that class's
    callable surface; and anything else that can pull a permission in is an
    offender, because "cannot be shown to demand a subject" and "does not
    demand one" have to be treated alike. A false offender costs one argument
    in a review; a false clean is a permission handed out about nothing.

    No allowlist, deliberately. "These helpers are exempt" is exactly the
    bookkeeping that goes stale and lets the next bypass through, so
    `_commercially_allowed` takes and demands a subject it never reads rather
    than being written down somewhere as a special case.

    ## What this CANNOT prove — and a correction about what `_require_subject` is

    This is a static read of one module's own text, and it is a LINT.

    An earlier version of this docstring, and of the gate's own closure
    argument, said `_require_subject` was the real guarantee and this check
    merely defence in depth over it. **That was wrong**, and a review round
    caught it by pointing at the very bypass these rounds exist for:

        def eligible_for_export(record):
            return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))

    constructs a perfectly valid `SubjectRef` internally, so `_require_subject`
    is satisfied while the external caller named no object at all.
    `_require_subject` guarantees that the enforcement predicates RECEIVE a
    valid `SubjectRef`; it cannot establish who supplied it. "The caller must
    name the object" is a separate, public-surface invariant, and this check
    and its runtime counterpart are what carry it — so a miss here is a real
    miss, not something the runtime rescues.

    The runtime counterpart is
    `test_no_live_callable_answers_a_permission_without_a_subject`, which
    reads `vars(rights)` instead of modelling Python's scope rules, and so
    sees what the module actually bound.

    Outside its reach, stated so the claim stops growing: dynamic access
    (`getattr(rights, "_eligible_for_display")`), a callable assigned onto the
    module object after import, a decorator that rewrites a signature,
    `exec`/`eval`, and anything in another module. Within its reach it fails
    closed — an expression or binding form it cannot model is an offender
    rather than a silent pass — so the honest claim is: **no permission route
    that this lint can see is reachable by name from this module's own source
    without a mandatory subject, and one it cannot see is reported rather than
    ignored.**
    """
    import ast

    tree = ast.parse(source)
    scope_nodes = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda,
                   ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
    container_nodes = (ast.Dict, ast.List, ast.Tuple, ast.Set,
                       ast.DictComp, ast.ListComp, ast.SetComp, ast.GeneratorExp)

    #: name -> [(order, conditional, owner_statement, exposed_value_or_None)]
    bindings: dict = {}
    order = [0]

    def record(name, owner, value, conditional):
        order[0] += 1
        bindings.setdefault(name, []).append((order[0], conditional, owner, value))

    def stored(target) -> list:
        return [n.id for n in ast.walk(target)
                if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)]

    def walruses(expr) -> list:
        """A walrus binds in the ENCLOSING scope, including from inside a
        comprehension or a function default, so this walk is deliberately not
        scope-limited."""
        return [n for n in ast.walk(expr) if isinstance(n, ast.NamedExpr)]

    def captures(pattern) -> list:
        """`match` capture names live on the pattern nodes, not on `Name`."""
        out = []
        for node in ast.walk(pattern):
            name = getattr(node, "name", None)
            if isinstance(name, str):
                out.append(name)
            rest = getattr(node, "rest", None)
            if isinstance(rest, str):
                out.append(rest)
        return out

    def visit_expr(expr, owner, conditional):
        for walrus in walruses(expr):
            for name in stored(walrus.target):
                record(name, owner, walrus.value, conditional)

    def visit(stmt, conditional):
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            record(stmt.name, stmt, stmt, conditional)
            # Decorators, defaults and annotations run in THIS scope, so a
            # walrus in a default binds a module global. Only the BODY is a
            # separate scope.
            args = stmt.args
            for expr in (list(stmt.decorator_list) + list(args.defaults)
                         + [d for d in args.kw_defaults if d is not None]):
                visit_expr(expr, stmt, conditional)
            return
        if isinstance(stmt, ast.ClassDef):
            record(stmt.name, stmt, stmt, conditional)
            for expr in list(stmt.decorator_list) + list(stmt.bases):
                visit_expr(expr, stmt, conditional)
            return
        if isinstance(stmt, ast.Assign):
            for target in stmt.targets:
                for name in stored(target):
                    record(name, stmt, stmt.value, conditional)
            visit_expr(stmt.value, stmt, conditional)
            return
        if isinstance(stmt, ast.AnnAssign):
            if stmt.value is not None:
                for name in stored(stmt.target):
                    record(name, stmt, stmt.value, conditional)
                visit_expr(stmt.value, stmt, conditional)
            return
        if isinstance(stmt, (ast.For, ast.AsyncFor)):
            # The loop variable takes one element of the iterable, which is
            # exactly what the container rules recurse into.
            for name in stored(stmt.target):
                record(name, stmt, stmt.iter, True)
            visit_expr(stmt.iter, stmt, conditional)
            for child in stmt.body + stmt.orelse:
                visit(child, True)
            return
        if isinstance(stmt, (ast.If, ast.While)):
            visit_expr(stmt.test, stmt, conditional)
            for child in stmt.body + stmt.orelse:
                visit(child, True)
            return
        if isinstance(stmt, (ast.With, ast.AsyncWith)):
            for item in stmt.items:
                visit_expr(item.context_expr, stmt, conditional)
                if item.optional_vars is not None:
                    for name in stored(item.optional_vars):
                        record(name, stmt, None, conditional)
            for child in stmt.body:
                visit(child, conditional)
            return
        if isinstance(stmt, ast.Try) or type(stmt).__name__ == "TryStar":
            for handler in stmt.handlers:
                if handler.name:
                    record(handler.name, stmt, None, True)
                for child in handler.body:
                    visit(child, True)
            for child in stmt.body + stmt.orelse + stmt.finalbody:
                visit(child, True)
            return
        if type(stmt).__name__ == "Match":
            visit_expr(stmt.subject, stmt, conditional)
            for case in stmt.cases:
                for name in captures(case.pattern):
                    record(name, stmt, None, True)
                for child in case.body:
                    visit(child, True)
            return
        # Anything else: expressions, imports, `global`, and whatever the
        # language grows next. Walruses bind; any other module-scope store is
        # a binding whose value could not be identified, which fails closed.
        explained = set()
        for walrus in walruses(stmt):
            for name in stored(walrus.target):
                record(name, stmt, walrus.value, conditional)
                explained.add(name)
        stack, seen_nodes = [stmt], []
        while stack:
            current = stack.pop()
            seen_nodes.append(current)
            for child in ast.iter_child_nodes(current):
                if not isinstance(child, scope_nodes):
                    stack.append(child)
        for node in seen_nodes:
            if (isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store)
                    and node.id not in explained):
                record(node.id, stmt, None, conditional)

    for statement in tree.body:
        visit(statement, False)

    def effective(name) -> list:
        """Every binding that can still be the live one: the last
        unconditional binding plus anything bound after it."""
        entries = sorted(bindings[name])
        last_unconditional = max(
            (i for i, (_, cond, _, _) in enumerate(entries) if not cond), default=None
        )
        return entries if last_unconditional is None else entries[last_unconditional:]

    def is_def(value) -> bool:
        return isinstance(value, (ast.FunctionDef, ast.AsyncFunctionDef))

    def requires_subject(args) -> bool:
        """A parameter NAMED `subject` is not a subject requirement — it must
        be mandatory. `lambda record, subject=SubjectRef("t", "i"): ...` has
        the parameter and is still callable as `f(record)`."""
        positional = list(getattr(args, "posonlyargs", [])) + list(args.args)
        cut = len(positional) - len(args.defaults)
        mandatory = {a.arg for a in positional[:cut]}
        mandatory |= {a.arg for a, default in zip(args.kwonlyargs, args.kw_defaults)
                      if default is None}
        return "subject" in mandatory

    def literal_permission(node) -> bool:
        return any(
            isinstance(sub, ast.Constant) and isinstance(sub.value, str)
            and sub.value in permission_fields
            for sub in ast.walk(node)
        )

    def passive_data(value) -> bool:
        """Data that cannot be called. The ONE exception to fail-closed sink
        seeding, and it exists for exactly one shape: `PERMISSION_FIELDS`."""
        if isinstance(value, ast.Constant):
            return True
        if isinstance(value, (ast.List, ast.Tuple, ast.Set)):
            return all(passive_data(e) for e in value.elts)
        if isinstance(value, ast.Dict):
            return all(passive_data(e) for e in list(value.keys) + list(value.values)
                       if e is not None)
        if (isinstance(value, ast.Call) and isinstance(value.func, ast.Name)
                and value.func.id in {"frozenset", "set", "tuple", "list", "dict", "str"}):
            return all(passive_data(a) for a in value.args) and not value.keywords
        return False

    def class_members(cls) -> list:
        """Methods AND class-level attributes: `EligibleExport.export` is a
        callable surface as surely as `EligibleExport.__call__` is.

        Descends through class-body control flow, because
        `class X: \n  if FLAG: \n    export = lambda record: ...` binds a
        class attribute exactly as an unconditional line would — and reading
        only `cls.body` saw the `If` and stopped there. Nested `def`/`class`
        BODIES are not descended into; they are their own scopes.
        """
        out, stack = [], list(cls.body)
        while stack:
            member = stack.pop()
            if is_def(member):
                out.append(member)
            elif isinstance(member, ast.ClassDef):
                out.extend(class_members(member))
            elif isinstance(member, ast.Assign):
                out.append(member.value)
            elif isinstance(member, ast.AnnAssign) and member.value is not None:
                out.append(member.value)
            else:
                # Generic descent rather than another partial list of
                # control-flow child attributes: a `match` keeps its branches
                # under `cases`, which a body/orelse/finalbody/handlers list
                # does not mention, so a method bound inside one was invisible.
                for child in ast.iter_child_nodes(member):
                    if isinstance(child, ast.stmt) or hasattr(child, "body"):
                        stack.append(child)
        return out

    def seeds_permission(value) -> bool:
        if is_def(value):
            return literal_permission(value)
        if isinstance(value, ast.ClassDef):
            return any(seeds_permission(m) for m in class_members(value))
        if value is None:
            return False
        return literal_permission(value) and not passive_data(value)

    def named(node) -> set:
        own = getattr(node, "name", None)
        return {sub.id for sub in ast.walk(node)
                if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Load)
                and sub.id in bindings and sub.id != own}

    reaches = {name for name in bindings
               if any(seeds_permission(v) for _, _, _, v in effective(name))}
    edges = {name: set().union(*(named(o) for _, _, o, _ in effective(name)))
             for name in bindings}
    while True:
        grown = {n for n, refs in edges.items() if refs & reaches} - reaches
        if not grown:
            break
        reaches |= grown

    def class_is_a_route(cls) -> bool:
        """`EligibleExport.__call__(self, record)` is a permission route the
        moment an instance exists — and `EligibleExport()(record)` needs no
        instance bound to any name at all."""
        for member in class_members(cls):
            if is_def(member):
                if ((literal_permission(member) or bool(named(member) & reaches))
                        and not requires_subject(member.args)):
                    return True
            elif exposes_a_subjectless_callable(member):
                return True
        return False

    def elements(value) -> list:
        if isinstance(value, ast.Dict):
            return [v for v in list(value.keys) + list(value.values) if v is not None]
        if isinstance(value, (ast.List, ast.Tuple, ast.Set)):
            return list(value.elts)
        if isinstance(value, ast.DictComp):
            return [value.key, value.value]
        return [value.elt]

    def bound_value(name):
        """What the name exposes, if every live binding agrees on one shape."""
        values = [v for _, _, _, v in effective(name)]
        return values[-1] if values else None

    def exposes_a_subjectless_callable(value, seen=frozenset()) -> bool:
        if isinstance(value, ast.Lambda):
            return not requires_subject(value.args)
        if isinstance(value, ast.Name):
            if value.id in seen or value.id not in bindings:
                return value.id in reaches and value.id not in seen
            return any(
                _judge(v, seen | {value.id}) for _, _, _, v in effective(value.id)
            )
        if isinstance(value, ast.Call):
            func = value.func
            target = bound_value(func.id) if (isinstance(func, ast.Name)
                                              and func.id in bindings) else None
            if isinstance(target, ast.ClassDef):
                return class_is_a_route(target)
            # An unknown callable producer: `functools.partial(eligible_for,
            # subject=...)` and `operator.itemgetter("displayAllowed")` are the
            # worked examples. The signature cannot be read, so it fails closed
            # whenever it can pull a permission in.
            return bool(named(value) & reaches) or literal_permission(value)
        if isinstance(value, container_nodes):
            return any(exposes_a_subjectless_callable(e, seen) for e in elements(value))
        if isinstance(value, ast.IfExp):
            return any(exposes_a_subjectless_callable(b, seen)
                       for b in (value.body, value.orelse))
        if isinstance(value, ast.BoolOp):
            return any(exposes_a_subjectless_callable(v, seen) for v in value.values)
        if isinstance(value, ast.Starred):
            return exposes_a_subjectless_callable(value.value, seen)
        # A form this rule does not model. Clean only if it cannot pull a
        # permission in at all.
        return bool(named(value) & reaches) or literal_permission(value)

    def _judge(value, seen=frozenset()) -> bool:
        if is_def(value):
            return not requires_subject(value.args)
        if isinstance(value, ast.ClassDef):
            return class_is_a_route(value)
        if value is None:  # a binding whose value could not be identified
            return True
        return exposes_a_subjectless_callable(value, seen)

    offenders = sorted(
        name for name in reaches
        if any(_judge(v) for _, _, _, v in effective(name))
    )
    return offenders, sorted(reaches)


def test_no_module_level_function_reaches_a_permission_without_a_subject():
    """The real module, against the rule above."""
    source = Path(rights.__file__).read_text(encoding="utf-8")
    offenders, matched = _permission_routes_without_a_subject(
        source, set(rights.PERMISSION_FIELDS)
    )
    assert offenders == [], (
        f"module-level function(s) can reach a permission without requiring a "
        f"subject: {offenders}. Each is a route to a permission that never has to "
        "say what object it is about"
    )
    # The rule has teeth: a future refactor cannot satisfy it by arranging for
    # nothing to match.
    assert len(matched) >= 6, f"the rule matched almost nothing: {matched}"
    assert "eligible_for" in matched, matched


def test_the_bypass_is_caught_in_the_real_module_not_only_in_a_fixture():
    """The failure scenario from the review, run against `rights.py` itself.

    A fixture passing is weaker evidence than it looks: the rule could match
    the miniature module and still miss the real one, which is exactly what
    happened on the first attempt — `eligible_for` dispatches through a
    subscript, so a call-based graph gave it no edge to any sink and a wrapper
    around it would have been invisible. So the wrapper is appended to the
    actual source and the rule is asked about that.
    """
    source = Path(rights.__file__).read_text(encoding="utf-8")
    fields = set(rights.PERMISSION_FIELDS)
    assert _permission_routes_without_a_subject(source, fields)[0] == []

    wrapper = (
        '\n\n'
        'def eligible_for_export(record):\n'
        '    return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    offenders, _ = _permission_routes_without_a_subject(source + wrapper, fields)
    assert offenders == ["eligible_for_export"], offenders

    # The same wrapper reaching a PRIVATE predicate instead of the front door,
    # which the review named as the equivalent form.
    private = (
        '\n\n'
        'def eligible_for_export(record):\n'
        '    return _eligible_for_display(record, SubjectRef("test", "item1"))\n'
    )
    offenders, _ = _permission_routes_without_a_subject(source + private, fields)
    assert offenders == ["eligible_for_export"], offenders

    # And through the dispatch table directly, which is the route that was
    # invisible before the graph counted references rather than calls.
    table = (
        '\n\n'
        'def eligible_for_export(record):\n'
        '    return _ELIGIBILITY_BY_USE["DISPLAY"](record, SubjectRef("test", "item1"))\n'
    )
    offenders, _ = _permission_routes_without_a_subject(source + table, fields)
    assert offenders == ["eligible_for_export"], offenders

    # And as an ASSIGNMENT rather than a `def`, which is the form the next
    # review round found still invisible: the assignment relayed into the
    # graph and was then excluded from the offender set for being an
    # assignment. Measured before the fix: offenders was empty.
    lam = (
        '\n\n'
        'eligible_for_export = lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    offenders, _ = _permission_routes_without_a_subject(source + lam, fields)
    assert offenders == ["eligible_for_export"], offenders

    # Its control, differing only in taking the subject.
    lam_ok = (
        '\n\n'
        'eligible_for_export = lambda record, subject: '
        'eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + lam_ok, fields)[0] == []

    # A lambda hidden inside a container is the same escape wearing the
    # clothes of the relay that is allowed to be non-offending.
    buried = (
        '\n\n'
        'EXPORTS = {"DISPLAY": lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))}\n'
    )
    assert _permission_routes_without_a_subject(source + buried, fields)[0] == ["EXPORTS"]

    # A bare alias inherits the aliased function's signature: `eligible_for`
    # demands a subject, so aliasing it is not a bypass and must not be
    # flagged, or the rule would be "no aliases" rather than "no subjectless
    # routes".
    alias = "\n\npublic_eligible_for = eligible_for\n"
    assert _permission_routes_without_a_subject(source + alias, fields)[0] == []

    # The private dispatch table itself stays non-offending — it relays to
    # predicates that each demand a subject. If this ever flips, the rule has
    # become "no containers", which is a different and wrong rule.
    _, matched = _permission_routes_without_a_subject(source, fields)
    assert "_ELIGIBILITY_BY_USE" in matched, matched

    # --- a parameter named `subject` is not a subject requirement ----------
    # The next round's finding: the rule read the NAME and not the signature,
    # so a default made the parameter optional and the route stayed clean.

    defaulted_lambda = (
        '\n\n'
        'eligible_for_export = lambda record, subject=SubjectRef("test", "item1"): '
        'eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + defaulted_lambda, fields)[0] == [
        "eligible_for_export"
    ]

    defaulted_def = (
        '\n\n'
        'def eligible_for_export(record, subject=SubjectRef("test", "item1")):\n'
        '    return eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + defaulted_def, fields)[0] == [
        "eligible_for_export"
    ]

    # Their controls: the same two with the subject mandatory.
    mandatory_def = (
        '\n\n'
        'def eligible_for_export(record, subject):\n'
        '    return eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + mandatory_def, fields)[0] == []

    # Keyword-only counts as mandatory only when it has no default either.
    kwonly_defaulted = (
        '\n\n'
        'def eligible_for_export(record, *, subject=SubjectRef("test", "item1")):\n'
        '    return eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + kwonly_defaulted, fields)[0] == [
        "eligible_for_export"
    ]
    kwonly_mandatory = (
        '\n\n'
        'def eligible_for_export(record, *, subject):\n'
        '    return eligible_for(record, "DISPLAY", subject)\n'
    )
    assert _permission_routes_without_a_subject(source + kwonly_mandatory, fields)[0] == []

    # --- a container is judged on what it holds, not on holding no lambda --
    # Exempting every lambda-free container recreated the very bypass the
    # dispatch-table rule exists to prevent, with `partial` in place of a
    # direct predicate.

    partial_in_dict = (
        '\n\n'
        'EXPORTS = {"DISPLAY": functools.partial(eligible_for, use="DISPLAY", '
        'subject=SubjectRef("test", "item1"))}\n'
    )
    assert _permission_routes_without_a_subject(source + partial_in_dict, fields)[0] == [
        "EXPORTS"
    ]

    # Its control: a container of bare aliases to functions that each demand a
    # mandatory subject is exactly what `_ELIGIBILITY_BY_USE` is, and must
    # stay clean — otherwise the rule is "no containers" again.
    safe_container = '\n\nEXPORTS = {"DISPLAY": eligible_for}\n'
    assert _permission_routes_without_a_subject(source + safe_container, fields)[0] == []

    # --- a class is a callable surface too ---------------------------------

    callable_class = (
        '\n\n'
        'class EligibleExport:\n'
        '    def __call__(self, record):\n'
        '        return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
        '\n\n'
        'eligible_for_export = EligibleExport()\n'
    )
    # Both the class and the instance: `EligibleExport()(record)` is a route
    # even with no instance bound to a name anywhere.
    assert _permission_routes_without_a_subject(source + callable_class, fields)[0] == [
        "EligibleExport", "eligible_for_export",
    ]

    callable_class_ok = callable_class.replace(
        "def __call__(self, record):", "def __call__(self, record, subject):"
    ).replace('SubjectRef("test", "item1")', "subject")
    assert _permission_routes_without_a_subject(source + callable_class_ok, fields)[0] == []

    # --- an expression the rule cannot model must fail CLOSED --------------
    # The fallback SAID fail-closed and returned False, so an `IfExp` walked
    # straight through it while referencing the front door in one branch.

    conditional = (
        '\n\n'
        'eligible_for_export = (\n'
        '    functools.partial(eligible_for, use="DISPLAY", '
        'subject=SubjectRef("test", "item1"))\n'
        '    if ENABLE_EXPORT else eligible_for\n'
        ')\n'
    )
    assert _permission_routes_without_a_subject(source + conditional, fields)[0] == [
        "eligible_for_export"
    ]

    # Its control: both branches expose a callable that demands a subject, so
    # the branch analysis has to be real and not "any IfExp is an offender".
    conditional_ok = (
        '\n\n'
        'eligible_for_export = eligible_for if ENABLE_EXPORT else eligible_for\n'
    )
    assert _permission_routes_without_a_subject(source + conditional_ok, fields)[0] == []

    # --- a route that reads the permission ITSELF, in a non-function -------
    # Sinks were seeded from `def`s only, so neither of these entered the
    # graph at all: they call nothing, they just read the field.

    direct_lambda = (
        '\n\n'
        'eligible_for_export = lambda record: record["rights"]["displayAllowed"]\n'
    )
    assert _permission_routes_without_a_subject(source + direct_lambda, fields)[0] == [
        "eligible_for_export"
    ]
    direct_lambda_ok = (
        '\n\n'
        'eligible_for_export = lambda record, subject: record["rights"]["displayAllowed"]\n'
    )
    assert _permission_routes_without_a_subject(source + direct_lambda_ok, fields)[0] == []

    direct_class = (
        '\n\n'
        'class EligibleExport:\n'
        '    def __call__(self, record):\n'
        '        return record["rights"]["displayAllowed"]\n'
        '\n\n'
        'eligible_for_export = EligibleExport()\n'
    )
    assert _permission_routes_without_a_subject(source + direct_class, fields)[0] == [
        "EligibleExport", "eligible_for_export",
    ]
    direct_class_ok = direct_class.replace(
        "def __call__(self, record):", "def __call__(self, record, subject):"
    )
    assert _permission_routes_without_a_subject(source + direct_class_ok, fields)[0] == []

    # --- a module global bound by something other than `=` -----------------
    # `def`, `class`, `Assign` and `AnnAssign` were the only binding forms the
    # collector knew, so a walrus at module scope bound a name it never saw.
    # Bindings are now found by looking for module-scope STORES, which is why
    # a `for` target and a `with ... as` are covered by the same change rather
    # than by three more cases.

    walrus = (
        '\n\n'
        '(eligible_for_export := lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1")))\n'
    )
    assert _permission_routes_without_a_subject(source + walrus, fields)[0] == [
        "eligible_for_export"
    ]

    loop_bound = (
        '\n\n'
        'for eligible_for_export in [lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))]:\n'
        '    pass\n'
    )
    assert _permission_routes_without_a_subject(source + loop_bound, fields)[0] == [
        "eligible_for_export"
    ]

    # An unidentifiable value that still reaches a permission: `None` for the
    # exposed expression means offender, not a silent pass.
    with_bound = (
        '\n\n'
        'with contextlib.suppress(Exception) as eligible_for_export:\n'
        '    _ = eligible_for\n'
    )
    assert _permission_routes_without_a_subject(source + with_bound, fields)[0] == [
        "eligible_for_export"
    ]

    # --- a name can be bound more than once, and Python keeps the last -----
    # The model was one binding per name, first seen, so a safe alias placed
    # above an unsafe rebind hid it.

    rebound = (
        '\n\n'
        'eligible_for_export = eligible_for\n'
        'eligible_for_export = lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    assert _permission_routes_without_a_subject(source + rebound, fields)[0] == [
        "eligible_for_export"
    ]

    # The reverse order is the control, and it must be CLEAN: an
    # unconditional rebind really does overwrite what came before, so
    # flagging it would be modelling "any name ever bound unsafely".
    rebound_ok = (
        '\n\n'
        'eligible_for_export = lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
        'eligible_for_export = eligible_for\n'
    )
    assert _permission_routes_without_a_subject(source + rebound_ok, fields)[0] == []

    # A CONDITIONAL rebind after the last unconditional one can still be the
    # live value, so it is judged rather than assumed overwritten.
    conditional_rebind = (
        '\n\n'
        'eligible_for_export = eligible_for\n'
        'if ENABLE_EXPORT:\n'
        '    eligible_for_export = lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    assert _permission_routes_without_a_subject(
        source + conditional_rebind, fields
    )[0] == ["eligible_for_export"]

    # --- a binding does not have to be at the top level of the module ------

    nested_def = (
        '\n\n'
        'if ENABLE_EXPORT:\n'
        '    def eligible_for_export(record):\n'
        '        return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    assert _permission_routes_without_a_subject(source + nested_def, fields)[0] == [
        "eligible_for_export"
    ]

    # A function DEFAULT is evaluated in the enclosing scope, so a walrus
    # there binds a module global while the function body does not.
    default_walrus = (
        '\n\n'
        'def sentinel(x=(eligible_for_export := lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1")))):\n'
        '    pass\n'
    )
    # `sentinel` is flagged alongside it, and that is correct rather than
    # noise: `sentinel.__defaults__[0]` IS the subjectless lambda, so the
    # function really does carry a permission route in its own signature.
    assert _permission_routes_without_a_subject(source + default_walrus, fields)[0] == [
        "eligible_for_export", "sentinel",
    ]

    comprehension_walrus = (
        '\n\n'
        'USES_SEEN = [(eligible_for_export := lambda record: '
        'eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))) for _u in USES]\n'
    )
    # `USES_SEEN` is flagged too, and correctly: the list it builds holds
    # that same subjectless lambda, so `USES_SEEN[0](record)` is a route.
    assert _permission_routes_without_a_subject(
        source + comprehension_walrus, fields
    )[0] == ["USES_SEEN", "eligible_for_export"]

    # `match` capture names live on the pattern nodes, not on `Name`, so a
    # store-based collector cannot see them at all.
    match_capture = (
        '\n\n'
        'match {"export": eligible_for}:\n'
        '    case {"export": eligible_for_export}:\n'
        '        pass\n'
    )
    assert _permission_routes_without_a_subject(source + match_capture, fields)[0] == [
        "eligible_for_export"
    ]

    # --- a permission READER does not have to be a def, class or lambda ----
    # Sink seeding was still a list of callable shapes, so these never got as
    # far as the fail-closed judging stage.

    class_attribute = (
        '\n\n'
        'class EligibleExport:\n'
        '    export = lambda record: record["rights"]["displayAllowed"]\n'
    )
    assert _permission_routes_without_a_subject(source + class_attribute, fields)[0] == [
        "EligibleExport"
    ]
    class_attribute_ok = class_attribute.replace(
        "lambda record:", "lambda record, subject:"
    )
    assert _permission_routes_without_a_subject(
        source + class_attribute_ok, fields
    )[0] == []

    # The same attribute bound under class-body control flow. Reading only
    # `cls.body` saw the `If` and stopped, so the class never seeded — and the
    # runtime probe could not rescue it either, because probing the class
    # object CONSTRUCTS it rather than calling `.export`. Both instruments
    # were fixed for this one case; this is the static half.
    class_attribute_nested = (
        '\n\n'
        'class EligibleExport:\n'
        '    if ENABLE_EXPORT:\n'
        '        export = lambda record: record["rights"]["displayAllowed"]\n'
    )
    assert _permission_routes_without_a_subject(
        source + class_attribute_nested, fields
    )[0] == ["EligibleExport"]

    # A `match` keeps its branches under `cases`, which a
    # body/orelse/finalbody/handlers list does not mention — so the descent
    # through class-body control flow is generic now rather than another
    # partial list of child attributes. `@classmethod` is the runtime half of
    # the same case, covered independently by the live probe.
    class_match_classmethod = (
        '\n\n'
        'class EligibleExport:\n'
        '    match 1:\n'
        '        case 1:\n'
        '            @classmethod\n'
        '            def export(cls, record):\n'
        '                return record["rights"]["displayAllowed"]\n'
    )
    assert _permission_routes_without_a_subject(
        source + class_match_classmethod, fields
    )[0] == ["EligibleExport"]

    class_match_classmethod_ok = class_match_classmethod.replace(
        "def export(cls, record):", "def export(cls, record, subject):"
    )
    assert _permission_routes_without_a_subject(
        source + class_match_classmethod_ok, fields
    )[0] == []

    itemgetter = (
        '\n\n'
        'eligible_for_export = operator.itemgetter("displayAllowed")\n'
    )
    assert _permission_routes_without_a_subject(source + itemgetter, fields)[0] == [
        "eligible_for_export"
    ]

    # And the control that keeps the passive-data exception honest: a tuple
    # of exactly those strings is data, not a callable, and must NOT seed —
    # otherwise `PERMISSION_FIELDS` becomes a sink and every record validator
    # inherits a subject requirement it has no use for.
    passive = '\n\nAUDITED_FIELDS = ("displayAllowed", "commercialAllowed")\n'
    offenders, matched = _permission_routes_without_a_subject(source + passive, fields)
    assert offenders == [], offenders
    assert "AUDITED_FIELDS" not in matched, matched


def _grant_or_raise(record):
    """Grants by returning True, denies by raising — a permission surface all
    the same, and the shape that defeated the successful-answers-only probe.

    Written at module level rather than as a lambda because a `raise` is a
    statement, and because the probe below binds it onto the live module.
    """
    if record["rights"]["displayAllowed"]:
        return True
    raise rights.RightsValidationError("not allowed")


def test_no_live_callable_answers_a_permission_without_a_subject():
    """The complement the static lint above cannot be: a probe of what the
    module ACTUALLY binds, at runtime.

    Six review rounds of the AST check kept finding source forms it could not
    see, and the last of them named three more — a `match` capture, a `def`
    under a module-level `if`, an `operator.itemgetter` — because a static
    reader has to model Python's binding and scope rules, and modelling them
    exactly is not something a test helper is going to achieve. This test
    models nothing. It reads `vars(rights)`, which is the answer Python itself
    gives, and so it sees a conditional `def`, a walrus, a `match` capture, a
    class attribute and an `itemgetter` alike, with no rule to get wrong.

    **How a permission route is identified.** Ask each callable the same
    question across the WHOLE permission space: one record per combination of
    the `PERMISSION_FIELDS` booleans, everything else held permissive and
    equal. A callable whose successful boolean answer VARIES across that space
    has read a permission field and answered — from one positional record,
    with no subject supplied. A callable whose answer never varies read
    something else: `_reviewed` reports review state, `_not_discovery_only`
    reports priority, and both return the same value for every record.

    Two diagonal points are NOT enough, and the first version of this test
    used exactly two. `lambda record: displayAllowed != trainingAllowed`
    answers `False` on all-true and `False` on all-false, and `True` on a
    mixed record: two points cannot characterise a boolean function of six
    inputs. Six fields is 64 records, which costs nothing, so the space is
    enumerated rather than sampled — and the XOR case is a regression below.

    **Class attributes are surfaces too.** `EligibleExport.export(record)` is
    a route, and probing only `vars(rights)` would try to CONSTRUCT the class
    instead of calling its attribute. So the walk descends one level into
    classes the module itself defines.

    Two deliberate narrowings, stated rather than implied. Only `bool` answers
    count, so constructing an exception or a dataclass from a record is not
    mistaken for a permission; and only callables that accept a single
    positional record are probed, so `eligible_for(record, use, subject)` is
    skipped here — which costs nothing, because a signature that cannot be
    called without a subject is exactly what this test is looking for.
    """
    fields = tuple(rights.PERMISSION_FIELDS)
    space = [
        _reviewed_permissive_record(
            **{f: bool(mask >> i & 1) for i, f in enumerate(fields)}
        )
        for mask in range(2 ** len(fields))
    ]
    assert len(space) == 64, len(space)

    def answers_a_permission(obj) -> bool:
        """Does this callable's OUTCOME depend on the permission fields?

        Outcome, not return value. An earlier version collected successful
        boolean answers and skipped every exception, so a surface that grants
        by returning True and denies by RAISING looked constant — its `seen`
        set was `{True}` for all 64 records because each denial was discarded.
        That is a permission answer: the caller learns the grant either way.

        So a grant is a permission route when a boolean answer exists at all
        AND the outcome varies across the space — True vs False, or a boolean
        vs a refusal. A callable that raises for every record (wrong arity,
        say) never produces a boolean and is not a route.
        """
        outcomes, saw_bool = set(), False
        for record in space:
            try:
                answer = obj(record)
                outcome = (("bool", answer) if isinstance(answer, bool)
                           else ("value", type(answer).__name__))
                saw_bool = saw_bool or outcome[0] == "bool"
            except Exception as exc:  # noqa: BLE001 - refusal IS an outcome
                outcome = ("raise", type(exc).__name__)
            outcomes.add(outcome)
            if saw_bool and len(outcomes) > 1:
                return True
        return False

    def surfaces():
        """Every callable the module exposes by name, one level into the
        classes it defines itself.

        `getattr`, not `vars`, for the class attributes: a `classmethod` or
        `staticmethod` sits in `vars()` as a DESCRIPTOR, which is not itself
        callable, while `EligibleExport.export` is. Reading the raw stored
        value skipped exactly the descriptor forms.
        """
        for name, obj in vars(rights).items():
            if callable(obj):
                yield name, obj
            if isinstance(obj, type) and getattr(obj, "__module__", None) == rights.__name__:
                for attribute in vars(obj):
                    try:
                        member = getattr(obj, attribute)
                    except Exception:  # noqa: BLE001 - not an exposed surface
                        continue
                    if callable(member):
                        yield f"{name}.{attribute}", member

    offenders = sorted(
        name for name, obj in surfaces() if answers_a_permission(obj)
    )
    assert offenders == [], (
        f"callable(s) in the live module answer a permission question from a record "
        f"alone, with no subject: {offenders}"
    )

    # The teeth, proven rather than assumed. Three shapes, each removed again
    # in `finally` so a failure here cannot leak into another test.
    probes = {
        # The bypass the static check spent six rounds learning to see.
        "the wrapper": lambda record: record["rights"]["displayAllowed"],
        # The one that defeated the two-record version of this very test.
        "the xor": lambda record: (record["rights"]["displayAllowed"]
                                   != record["rights"]["trainingAllowed"]),
        # The one that defeated the successful-answers-only version: it
        # GRANTS by returning True and DENIES by raising, so collecting only
        # boolean answers saw the constant {True} and called it clean.
        "grant or raise": _grant_or_raise,
    }
    for label, probe in probes.items():
        try:
            rights.eligible_for_export = probe
            assert answers_a_permission(probe), label
            assert "eligible_for_export" in {n for n, _ in surfaces()}
        finally:
            del rights.eligible_for_export

    # The controls for the outcome rule: neither varies with the permission
    # fields, so neither may be flagged — otherwise the rule has become
    # "anything that ever raises".
    for label, control in {
        "constant value": lambda record: record["sourceId"],
        "always raises": lambda record: 1 / 0,
        "review state, not a permission": lambda record: (
            record["rights"]["legalReviewState"] == "REVIEWED"
        ),
    }.items():
        assert not answers_a_permission(control), label

    # And a class attribute, which is what `vars(rights)` alone cannot reach:
    # probing the class object constructs it rather than calling `.export`.
    class EligibleExport:
        export = staticmethod(lambda record: record["rights"]["displayAllowed"])

    EligibleExport.__module__ = rights.__name__
    try:
        rights.EligibleExport = EligibleExport
        found = sorted(name for name, obj in surfaces() if answers_a_permission(obj))
        assert found == ["EligibleExport.export"], found
    finally:
        del rights.EligibleExport

    # A `classmethod` is the form that reading `vars(cls)` cannot see: the
    # stored value is a DESCRIPTOR and is not itself callable, while
    # `EligibleExport.export` is. Detected here independently of the AST lint.
    class EligibleExportViaDescriptor:
        @classmethod
        def export(cls, record):
            return record["rights"]["displayAllowed"]

    EligibleExportViaDescriptor.__module__ = rights.__name__
    assert not callable(vars(EligibleExportViaDescriptor)["export"]), (
        "premise: the raw classmethod descriptor is not callable"
    )
    assert callable(EligibleExportViaDescriptor.export)
    try:
        rights.EligibleExport = EligibleExportViaDescriptor
        found = sorted(name for name, obj in surfaces() if answers_a_permission(obj))
        assert found == ["EligibleExport.export"], found
    finally:
        del rights.EligibleExport

    # The control that keeps the criterion from being "any bool-returning
    # callable": `_reviewed` reads review state, not a permission, so its
    # answer never varies across the space.
    assert not answers_a_permission(rights._reviewed)
    assert rights._reviewed(space[0]) is True


def test_the_rule_catches_the_wrapper_it_was_written_for():
    """Demonstrated on a fixture, not inferred from the real module passing.

    The previous version of this check was green against `rights.py` and would
    have stayed green while this exact wrapper was added — which is how a
    structural proof comes to prove nothing. So the rule is now exercised
    against a miniature module whose only defect is the bypass, and against a
    control that differs from it in one respect only: the subject parameter.
    """
    fields = {"displayAllowed", "commercialAllowed"}

    bypass = (
        'def _eligible_for_display(record, subject):\n'
        '    return record["rights"]["displayAllowed"]\n'
        '\n'
        'def eligible_for(record, use, subject):\n'
        '    return _eligible_for_display(record, subject)\n'
        '\n'
        'def eligible_for_export(record):\n'
        '    return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n'
    )
    offenders, matched = _permission_routes_without_a_subject(bypass, fields)
    assert offenders == ["eligible_for_export"], (offenders, matched)

    # One character of difference — the parameter — and it is no longer a
    # bypass. Without this control the assertion above could pass because the
    # rule flags everything.
    fixed = bypass.replace(
        "def eligible_for_export(record):", "def eligible_for_export(record, subject):"
    )
    assert _permission_routes_without_a_subject(fixed, fields)[0] == []

    # And a wrapper around the wrapper, to show reachability is transitive
    # rather than one level deep.
    nested = bypass + (
        '\n'
        'def convenience(record):\n'
        '    return eligible_for_export(record)\n'
    )
    assert _permission_routes_without_a_subject(nested, fields)[0] == [
        "convenience", "eligible_for_export",
    ]

    # A function that touches neither a permission field nor a permission
    # route is not flagged, so the rule is not simply "every function".
    innocent = bypass.replace(
        "def eligible_for_export(record):\n"
        '    return eligible_for(record, "DISPLAY", SubjectRef("test", "item1"))\n',
        "def describe(record):\n"
        '    return record["sourceId"]\n',
    )
    assert _permission_routes_without_a_subject(innocent, fields)[0] == []

    # The branch nothing else reaches: an assignment that reaches a sink and
    # is neither a lambda, an alias, nor a container. Its signature cannot be
    # read, so it cannot be shown to demand a subject, and the rule refuses to
    # assume one — a partial with the subject already bound is precisely the
    # escape this class covers.
    partial_form = bypass + (
        '\n'
        'exported = functools.partial(eligible_for, use="DISPLAY", '
        'subject=SubjectRef("test", "item1"))\n'
    )
    assert _permission_routes_without_a_subject(partial_form, fields)[0] == [
        "eligible_for_export", "exported",
    ]
