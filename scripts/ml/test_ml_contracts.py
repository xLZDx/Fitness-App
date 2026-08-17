# -*- coding: utf-8 -*-
"""ML lifecycle and dataset registry: the two implications, and drift.

    python -m pytest scripts/ml/test_ml_contracts.py -q

Both subjects here are green today and would stay green against a guard that
does nothing, so almost every test below breaks the thing it guards rather than
asserting the happy path.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dataset_registry import (  # noqa: E402
    OUT,
    REQUIRED,
    STATUSES,
    DatasetRegistryError,
    _validate,
    build,
)
from lifecycle import (  # noqa: E402
    DEPLOYABLE,
    REGISTRY,
    TRANSITIONS,
    LifecycleError,
    assert_no_train_deploy_coupling,
    assert_states_declared,
    assert_transition,
    audit,
)


def _registry():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------
# the two implications this exists to deny
# --------------------------------------------------------------------------


def test_trained_does_not_imply_challenger():
    """Being built is not evidence of being better."""
    assert_transition("TRAINED", "EVALUATED")            # the legal move
    for illegal in ("CHALLENGER_CANDIDATE", "SHADOW_READY", "SHADOW",
                    "PROMOTION_REVIEW", "CHAMPION"):
        with pytest.raises(LifecycleError, match="not a legal transition"):
            assert_transition("TRAINED", illegal)


def test_challenger_does_not_imply_champion():
    """Being better is not authority to ship. PROMOTION_REVIEW is a human
    decision and it is the only door."""
    for source in sorted(TRANSITIONS):
        if source in ("PROMOTION_REVIEW", "CHAMPION"):
            continue
        with pytest.raises(LifecycleError):
            assert_transition(source, "CHAMPION")
    assert_transition("PROMOTION_REVIEW", "CHAMPION")


def test_champion_is_reachable_at_all():
    """Otherwise the two tests above are satisfied by a table with no edges."""
    path = ["TRAINED", "EVALUATED", "CHALLENGER_CANDIDATE", "SHADOW_READY",
            "SHADOW", "PROMOTION_REVIEW", "CHAMPION"]
    for before, after in zip(path, path[1:]):
        assert_transition(before, after)


def test_every_state_can_be_rejected():
    """CT != CD: a training cycle may legitimately end at REJECTED, and that
    is a successful cycle. A lifecycle with no exit forces a promotion."""
    for state in sorted(TRANSITIONS):
        if state in ("REJECTED", "RETIRED"):
            continue
        assert_transition(state, "REJECTED")


def test_rejected_and_retired_go_nowhere():
    """A rejected candidate is retrained as a NEW version, not moved."""
    for terminal in ("REJECTED", "RETIRED"):
        assert TRANSITIONS[terminal] == frozenset()
        with pytest.raises(LifecycleError, match="terminal"):
            assert_transition(terminal, "EVALUATED")


def test_an_unknown_state_is_refused_at_both_ends():
    with pytest.raises(LifecycleError, match="not a lifecycle state"):
        assert_transition("PROBABLY_FINE", "CHAMPION")
    with pytest.raises(LifecycleError, match="not a lifecycle state"):
        assert_transition("CHAMPION", "PROBABLY_FINE")


def test_staying_put_is_not_a_transition():
    for state in sorted(TRANSITIONS):
        assert_transition(state, state)


# --------------------------------------------------------------------------
# CT != CD, against the real registry
# --------------------------------------------------------------------------


def test_the_shipped_registry_is_consistent():
    report = audit(_registry())
    assert report["verdict"] == "LIFECYCLE_CONSISTENT"
    assert report["models_checked"], "no models, so this proves nothing"
    assert report["champions"], "no champion, so the deployable check is vacuous"


def test_a_non_champion_reporting_a_live_deployment_is_refused():
    """The mutation. A model in a pre-champion state with a live
    deployment_status is a model that shipped without a promotion decision."""
    registry = _registry()
    assert_no_train_deploy_coupling(registry)          # green before
    for m in registry["models"]:
        if m["lifecycle_state"] != "CHAMPION":
            m["deployment_status"] = "deployed"
            break
    with pytest.raises(LifecycleError, match="authority to ship"):
        assert_no_train_deploy_coupling(registry)


def test_shadow_is_not_a_deployable_state():
    """A shadow model runs and its output is recorded and discarded. That is
    not deployment, and giving it a deployment_status would make the two
    indistinguishable."""
    assert DEPLOYABLE == frozenset({"CHAMPION"})
    assert "SHADOW" not in DEPLOYABLE


def test_an_empty_registry_is_refused_rather_than_passing_everything():
    with pytest.raises(LifecycleError, match="no models"):
        assert_no_train_deploy_coupling({"models": []})


def test_the_registrys_declared_states_and_this_table_must_agree():
    """If they drift, one is enforcing a lifecycle the other does not have and
    no reader can tell which."""
    assert_states_declared(_registry())
    with pytest.raises(LifecycleError, match="disagree"):
        assert_states_declared({"lifecycle_states": ["TRAINED", "CHAMPION"]})


def test_the_audit_states_what_it_cannot_see():
    """It reads a current state, not a history. A model edited straight from
    TRAINED to CHAMPION in one commit is invisible here."""
    report = audit(_registry())
    assert "not a history" in report["scope"]


# --------------------------------------------------------------------------
# dataset registry
# --------------------------------------------------------------------------


def test_the_committed_registry_is_the_one_the_artefacts_produce():
    """Drift is a CI failure rather than a discovery. Same contract the CT-1
    dataset and review batch already hold themselves to."""
    committed = json.loads(OUT.read_text(encoding="utf-8"))
    rebuilt = build()
    committed.pop("registry_commit", None)
    rebuilt.pop("registry_commit", None)
    assert committed == rebuilt


def test_every_entry_resolves_every_required_field():
    for entry in build()["datasets"]:
        _validate(entry)
        assert set(REQUIRED) <= set(entry), entry["dataset_id"]


def test_an_entry_missing_a_required_field_is_refused():
    """A partly described dataset is worse than an absent one: it looks
    checked."""
    entry = dict(build()["datasets"][0])
    entry.pop("label_provenance")
    with pytest.raises(DatasetRegistryError, match="missing"):
        _validate(entry)


def test_an_available_dataset_whose_bytes_moved_is_refused():
    """The check that makes a model card's `training_dataset_version`
    meaningful: the file under that name today is the file it describes."""
    entry = dict(build()["datasets"][0])
    entry["artifact"] = {**entry["artifact"], "sha256": "0" * 64}
    with pytest.raises(DatasetRegistryError, match="not the one this entry"):
        _validate(entry)


def test_an_available_dataset_with_no_digest_is_refused():
    entry = dict(build()["datasets"][0])
    entry["artifact"] = {"path": entry["artifact"]["path"]}
    with pytest.raises(DatasetRegistryError, match="no artefact"):
        _validate(entry)


def test_an_available_dataset_pointing_at_nothing_is_refused():
    entry = dict(build()["datasets"][0])
    entry["artifact"] = {**entry["artifact"], "path": "core/ml/not-here.json"}
    with pytest.raises(DatasetRegistryError, match="not there"):
        _validate(entry)


def test_an_unknown_status_is_refused():
    entry = dict(build()["datasets"][0])
    entry["status"] = "PROBABLY_FINE"
    with pytest.raises(DatasetRegistryError, match="not one of"):
        _validate(entry)


def test_the_untraceable_scanner_corpus_is_recorded_rather_than_omitted():
    """An entry that says it cannot be traced is evidence. One that is
    silently absent is not."""
    entries = {e["dataset_id"]: e for e in build()["datasets"]}
    scanner = entries["equipment_recognition_training"]
    assert scanner["status"] == "UNRESOLVED"
    assert scanner["source_commit"] == "UNRESOLVED"
    assert scanner["blocks"] == "ML-2a"
    assert "not a git repository" in scanner["sources"]["note"]
    # And UNRESOLVED is a first-class status, not a hole in the vocabulary.
    assert "UNRESOLVED" in STATUSES


def test_the_review_batches_are_registered_with_their_supersession():
    entries = {e["dataset_id"]: e for e in build()["datasets"]}
    live = [e for e in entries.values() if e["dataset_id"].startswith("ct1_review")
            and e["status"] == "AVAILABLE"]
    dead = [e for e in entries.values() if e["dataset_id"].startswith("ct1_review")
            and e["status"] == "SUPERSEDED"]
    assert len(live) == 1, "exactly one review batch may be live"
    assert dead, "the superseded ones are kept as evidence and must be listed"
    for e in dead:
        assert e["superseded_by"] == live[0]["dataset_id"].upper()


def test_no_review_batch_claims_a_human_label():
    """BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED. The registry is exactly the
    place a zero would quietly become a number."""
    for e in build()["datasets"]:
        if e["dataset_id"].startswith("ct1_review"):
            assert e["label_provenance"]["returned_human_labels"] == 0
            assert e["may_train_on"] is False


def test_the_clinical_worklist_is_registered_with_its_zero():
    """D1 is the largest open decision in this repository and its dataset is
    the one nobody has returned. A registry silent about it would answer "what
    data exists" without mentioning the gap that blocks the most."""
    entries = {e["dataset_id"]: e for e in build()["datasets"]}
    worklist = entries["clinical_contraindication_worklist"]
    assert worklist["status"] == "AVAILABLE"        # the sheet exists...
    assert worklist["label_provenance"]["returned_clinical_labels"] == 0
    assert "H3 = HOLD" in worklist["label_provenance"]["note"]
    assert worklist["may_train_on"] is False
    assert worklist["row_count"] == 1887
    assert (worklist["splits"]["tagged"], worklist["splits"]["untagged"]) \
        == (1527, 360)


def test_the_worklist_entry_is_pinned_to_its_source_not_to_the_last_commit():
    """A field that moves with every commit inside a re-derived payload makes
    `--check` fail on every commit, and a drift alarm that fires constantly is
    one nobody reads. Found when it did exactly that."""
    import subprocess

    from dataset_registry import REPO

    entries = {e["dataset_id"]: e for e in build()["datasets"]}
    worklist = entries["clinical_contraindication_worklist"]
    catalogue = subprocess.run(
        ["git", "-C", str(REPO), "log", "-1", "--format=%H", "--",
         "mobile/assets/data/exercises_vendor.json"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    assert worklist["source_commit"] == catalogue
    head = subprocess.run(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    assert worklist["source_commit"] != head, (
        "the entry names HEAD, so it will differ the moment anything is "
        "committed and --check will fail with nothing actually wrong"
    )


def test_no_registered_dataset_carries_a_human_or_clinical_label():
    """One assertion over the whole registry rather than per-entry, so a NEW
    dataset added later cannot arrive with a manufactured label count and no
    test to notice."""
    for e in build()["datasets"]:
        provenance = e["label_provenance"]
        for field, count in provenance.items():
            if field.startswith("returned_"):
                assert count == 0, f"{e['dataset_id']} claims {field}={count}"


def test_the_registry_says_that_being_registered_is_not_permission_to_train():
    assert "never may" in build()["training_eligibility"]
