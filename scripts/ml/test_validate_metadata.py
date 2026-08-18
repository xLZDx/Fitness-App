# -*- coding: utf-8 -*-
"""What can be tested about a script that cannot run here.

The library this module calls does not exist on this machine, so none of these
tests prove the metadata is valid -- and the last one exists to make sure the
repository never starts claiming otherwise. What they do prove is the part that
would be dangerous if wrong: that reading a model cannot write to it, and that
an unavailable library reports as unavailable rather than as agreement.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from validate_metadata import (
    RECORDED_MIN_PARSER_VERSION,
    STATES,
    inspect,
    main,
    sha256,
)

REPO = Path(__file__).resolve().parents[2]
CHAMPION = REPO / "mobile" / "assets" / "models" / "equipment_v1.tflite"


@pytest.fixture()
def model(tmp_path: Path) -> Path:
    """A stand-in model. Never the champion -- see the last test for why."""
    p = tmp_path / "equipment_v1.tflite"
    p.write_bytes(b"TFL3" + b"\x00" * 512)
    return p


class _FakeDisplayer:
    def __init__(self, version, path):
        self._version, self._path = version, path

    def get_metadata_json(self):
        # Reading through the fake must still be reading the COPY.
        assert "copy-" in Path(self._path).name, self._path
        return json.dumps({
            "min_parser_version": self._version,
            "subgraph_metadata": [{
                "input_tensor_metadata": [{
                    "process_units": [{"options_type": "NormalizationOptions"}],
                }],
            }],
        })

    def get_packed_associated_file_list(self):
        return ["labels.txt"]


def _fake_library(monkeypatch, version):
    class _Lib:
        class MetadataDisplayer:
            @staticmethod
            def with_model_file(path):
                return _FakeDisplayer(version, path)

    monkeypatch.setattr(
        "validate_metadata.genuine_library", lambda: (_Lib, "fake-0.4.4")
    )


def test_the_source_model_is_never_written_to(model, monkeypatch, tmp_path):
    """The whole safety argument, exercised on the path that does the work.

    Asserted after a run that actually reaches the parser, not after an early
    return -- an untouched file proves nothing if nothing was attempted.
    """
    _fake_library(monkeypatch, "1.0.0")
    before = sha256(model)
    mtime = model.stat().st_mtime_ns

    report = inspect(model, tmp_path)

    assert report["state"] == "VALIDATED_MATCH", report
    assert sha256(model) == before
    assert model.stat().st_mtime_ns == mtime


def test_a_disagreeing_library_is_a_mismatch_not_a_correction(
    model, monkeypatch, tmp_path
):
    """The interesting outcome. It reports; it does not restamp anything."""
    _fake_library(monkeypatch, "1.3.0")
    report = inspect(model, tmp_path)

    assert report["state"] == "VALIDATED_MISMATCH"
    assert report["computed_min_parser_version"] == "1.3.0"
    assert report["recorded_min_parser_version"] == RECORDED_MIN_PARSER_VERSION
    assert sha256(model) == report["input_sha256"]


def test_a_parse_failure_is_reported_as_a_parse_failure(
    model, monkeypatch, tmp_path
):
    class _Exploding:
        class MetadataDisplayer:
            @staticmethod
            def with_model_file(path):
                raise ValueError("not a flatbuffer")

    monkeypatch.setattr(
        "validate_metadata.genuine_library", lambda: (_Exploding, "fake")
    )
    report = inspect(model, tmp_path)
    assert report["state"] == "PARSE_FAILED"
    assert "not a flatbuffer" in report["detail"]


def test_a_missing_library_is_not_agreement(model, monkeypatch, tmp_path):
    """The failure mode that would quietly close this track for the wrong reason.

    `VALIDATED_MATCH` because nothing was checked would be the same class of
    defect as the stub that started all this: an unasked question answered in
    the affirmative.
    """
    monkeypatch.setattr(
        "validate_metadata.genuine_library", lambda: (None, "unavailable: x")
    )
    report = inspect(model, tmp_path)

    assert report["state"] == "ENVIRONMENT_NOT_RUN"
    assert "computed_min_parser_version" not in report
    assert "not a result" in report["detail"]


def test_the_working_copy_is_verified_against_its_source(
    model, monkeypatch, tmp_path
):
    """If the copy is not the model, every number below it is about a stranger."""
    real_copy = __import__("shutil").copy2

    def _corrupting_copy(src, dst):
        real_copy(src, dst)
        Path(dst).write_bytes(b"something else entirely")
        return dst

    monkeypatch.setattr("validate_metadata.shutil.copy2", _corrupting_copy)
    _fake_library(monkeypatch, "1.0.0")

    report = inspect(model, tmp_path)
    assert report["state"] == "PARSE_FAILED"
    assert "does not match its source" in report["detail"]


def test_the_state_vocabulary_is_closed():
    assert set(STATES) == {
        "ENVIRONMENT_NOT_RUN",
        "VALIDATED_MATCH",
        "VALIDATED_MISMATCH",
        "PARSE_FAILED",
    }


@pytest.mark.skipif(not CHAMPION.exists(), reason="model asset absent")
def test_on_this_machine_the_answer_is_still_that_nobody_has_checked():
    """The claim this file most needs to keep honest.

    A green suite above could easily be read as "metadata validated". It is
    not. On any machine without the genuine library -- which is every machine
    this project has -- the run exits 3 and validates nothing, and the day that
    stops being true is the day someone has real news to record.
    """
    digest_before = sha256(CHAMPION)
    assert main(["--model", "mobile/assets/models/equipment_v1.tflite"]) == 3
    assert sha256(CHAMPION) == digest_before
