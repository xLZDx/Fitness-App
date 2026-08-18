# -*- coding: utf-8 -*-
"""ML-2a: the pin, the probe, and the claims the module makes about them.

    python -m pytest scripts/ml/test_scanner_provenance.py -q

The subject is a module that describes a directory living on ONE machine and in
no checkout. That is exactly the shape where a test suite can pass everywhere
while proving nothing, so the tests below are split by what they can honestly
assert:

  * the pin is self-consistent and the module cannot silently disagree with
    itself -- true on every machine, including CI;
  * the probe reports absence as absence -- exercised against a path that is
    guaranteed not to exist, so it runs everywhere;
  * the manifest algorithm is the one the docstring claims -- built from a
    temporary tree, so it never depends on D:/tools;
  * the pinned digests match the bytes -- SKIPPED, loudly, where the pipeline
    is not present. A skip that names why is evidence; a test quietly asserting
    True is not.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scanner_provenance import (  # noqa: E402
    CLASSIFICATIONS,
    PINNED,
    PIPELINE_ROOT,
    RECOVERY_CONTRACT,
    SHIPPED_MODEL,
    SHIPPED_MODEL_SHA256,
    corpus_manifest,
    probe,
)

HAVE_PIPELINE = Path(PIPELINE_ROOT).exists()
needs_pipeline = pytest.mark.skipif(
    not HAVE_PIPELINE,
    reason=(
        f"{PIPELINE_ROOT} is not on this machine. The pin cannot be "
        "re-verified here, and that is the documented case -- not a pass."
    ),
)


# --------------------------------------------------------------- the pin
def test_the_shipped_model_is_in_this_repository():
    # The one artefact that is not machine-dependent. If this ever fails, the
    # pin describes a model the app no longer ships, and every claim built on
    # it is about the wrong file.
    assert SHIPPED_MODEL.exists(), SHIPPED_MODEL
    got = hashlib.sha256(SHIPPED_MODEL.read_bytes()).hexdigest()
    assert got == SHIPPED_MODEL_SHA256


def test_the_pin_and_the_shipped_model_agree_with_each_other():
    # The module states the v1 chain twice: once as SHIPPED_MODEL_SHA256 and
    # once inside PINNED["artifacts"]. Two copies of one fact drift. The whole
    # "byte-identical to the pipeline's own output" claim is exactly the
    # equality of these two constants, so it is asserted rather than trusted.
    assert PINNED["artifacts"]["out/equipment_v1.tflite"]["sha256"] == (
        SHIPPED_MODEL_SHA256
    )


def test_every_pinned_digest_is_a_sha256():
    for name, pin in PINNED["artifacts"].items():
        assert len(pin["sha256"]) == 64, name
        assert int(pin["sha256"], 16) >= 0, name
        assert pin["bytes"] > 0, name
    for name, pin in PINNED["corpora"].items():
        assert len(pin["manifest"]) == 64, name
        assert pin["files"] > 0, name


def test_the_pin_is_dated():
    # A measurement with no date is not a measurement, it is a rumour. The
    # probe's whole contract is "pinned on this day, re-verifiable later".
    assert PINNED["measured_at"] == "2026-08-18"
    assert PINNED["is_git_repository"] is False


# ------------------------------------------------------------- the probe
def test_absence_is_reported_as_absence_not_as_loss():
    # The failure this guards against is a report that reads "the scanner
    # pipeline could not be found" on a machine that was simply never the one
    # holding it. Run against a path that cannot exist.
    missing = Path(__file__).resolve().parent / "no_such_pipeline_dir_zzz"
    assert not missing.exists()
    result = probe(missing)
    assert result["classification"] == "NOT_PRESENT_ON_THIS_MACHINE"
    assert "is NOT evidence that the pipeline is gone" in result["note"]
    # The pin still travels with the answer, so the reader can verify it
    # elsewhere rather than being told to go and find the machine first.
    assert result["pinned"] == PINNED
    assert result["mismatches"] == []


def test_the_probe_never_invents_a_classification():
    missing = Path(__file__).resolve().parent / "no_such_pipeline_dir_zzz"
    assert probe(missing)["classification"] in CLASSIFICATIONS


def test_an_empty_directory_is_not_a_pipeline(tmp_path):
    # Present but empty: every artefact absent, nothing verified. The point is
    # that the probe reports mismatches rather than classifying an empty
    # directory as a found pipeline with nothing wrong.
    result = probe(tmp_path)
    assert result["classification"] == "FOUND_UNVERSIONED_PIPELINE"
    assert result["verified"] == []
    problems = {m["problem"] for m in result["mismatches"]}
    assert problems == {"absent"}
    assert len(result["mismatches"]) == (
        len(PINNED["artifacts"]) + len(PINNED["corpora"])
    )


def test_a_git_directory_flips_the_classification(tmp_path):
    # The single fact ML-2a turns on. If `git init` ever happens at the real
    # path, the probe must say so on its own rather than needing this module
    # edited to notice.
    (tmp_path / ".git").mkdir()
    assert probe(tmp_path)["classification"] == "FOUND_VERSIONED_PIPELINE"


# ------------------------------------------------------ the manifest
def _write(root: Path, rel: str, content: bytes) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


def test_the_manifest_is_deterministic_across_walk_order(tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    _write(a, "z/2.jpg", b"two")
    _write(a, "m/1.jpg", b"one")
    _write(b, "m/1.jpg", b"one")
    _write(b, "z/2.jpg", b"two")
    assert corpus_manifest(a) == corpus_manifest(b)


def test_renaming_a_file_changes_the_manifest(tmp_path):
    # The docstring's stated reason for hashing paths: in a
    # class-per-directory image corpus a rename IS a relabel, and a
    # content-only digest would call the relabelled corpus identical.
    a, b = tmp_path / "a", tmp_path / "b"
    _write(a, "barbell/1.jpg", b"same bytes")
    _write(b, "dumbbell/1.jpg", b"same bytes")
    assert corpus_manifest(a)[0] == corpus_manifest(b)[0] == 1
    assert corpus_manifest(a)[1] != corpus_manifest(b)[1]


def test_editing_a_file_changes_the_manifest(tmp_path):
    a = tmp_path / "a"
    _write(a, "barbell/1.jpg", b"before")
    first = corpus_manifest(a)
    _write(a, "barbell/1.jpg", b"after")
    assert corpus_manifest(a) != first


def test_an_empty_tree_has_a_stable_digest(tmp_path):
    (tmp_path / "empty").mkdir()
    count, digest = corpus_manifest(tmp_path / "empty")
    assert count == 0
    assert digest == hashlib.sha256(b"").hexdigest()


# ------------------------------------------------ the recovery contract
def test_the_contract_says_what_is_NOT_missing():
    # ML-2a's whole correction to the registry note. A contract that lists
    # only what is missing reproduces the error it exists to fix, because a
    # reader plans a re-crawl for data that is sitting on disk.
    text = " ".join(RECOVERY_CONTRACT["what_is_NOT_missing"]).lower()
    assert "corpus" in text
    assert "byte-identical" in text
    assert len(RECOVERY_CONTRACT["what_is_NOT_missing"]) >= 3


def test_every_required_item_names_a_state_and_an_action():
    items = RECOVERY_CONTRACT["required_to_close"]
    assert len(items) == 6
    for it in items:
        assert it["item"] and it["state"] and it["required"]
        # An action, not a lament: each entry must say what to DO.
        assert len(it["required"]) > 40, it["item"]


def test_closing_ML_2a_does_not_promote_anything():
    # The boundary the whole programme rests on. Reproducibility is not
    # promotion, and this module must keep saying so where a reader of the
    # contract will see it.
    text = RECOVERY_CONTRACT["does_not_close"]
    assert "does not promote" in text
    assert "PRODUCTION_IMAGE_COLLECTION stays DISABLED" in text
    assert "still only TRAINED" in text


def test_the_v2_run_record_is_recorded_as_contradicted_not_merely_absent():
    # The finding that stops a retro-fitted v2 manifest: the one log on disk
    # describes a 29-class run and the registered artefact carries 37 labels.
    # Recorded as CONTRADICTED because "missing" would invite somebody to
    # supply the log they have.
    item = next(i for i in RECOVERY_CONTRACT["required_to_close"]
                if i["item"] == "RUN_RECORD_FOR_V2")
    assert item["state"] == "MISSING_AND_CONTRADICTED"
    assert "29" in item["required"] and "37" in item["required"]


# ------------------------------------------- only where the bytes are here
@needs_pipeline
def test_the_pinned_artefacts_match_the_bytes_on_this_machine():
    result = probe()
    assert result["mismatches"] == [], result["mismatches"]
    assert len(result["verified"]) == (
        len(PINNED["artifacts"]) + len(PINNED["corpora"])
    )


@needs_pipeline
def test_the_pipeline_is_still_not_a_git_repository():
    # The assertion that makes ML-2a OPEN. It is expected to FAIL the day
    # somebody runs `git init` there -- that failure is the item closing, and
    # the fix is to update the pin and the registry, not to delete this test.
    result = probe()
    assert result["is_git_repository"] is False
    assert result["classification"] == "FOUND_UNVERSIONED_PIPELINE"


@needs_pipeline
def test_the_shipped_model_is_the_pipelines_own_output():
    # The claim that makes v1 recoverable at all, checked against both files
    # rather than against the pin twice.
    built = Path(PIPELINE_ROOT) / "out" / "equipment_v1.tflite"
    assert built.exists()
    assert (hashlib.sha256(built.read_bytes()).hexdigest()
            == hashlib.sha256(SHIPPED_MODEL.read_bytes()).hexdigest())
