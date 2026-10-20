"""dump_json must be atomic: serialise first, temp file, bounded-retry replace."""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location(
    "json_io_atomic_under_test", Path(__file__).with_name("json_io.py"))
json_io = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(json_io)


def test_unserialisable_data_leaves_the_file_untouched(tmp_path):
    p = tmp_path / "f.json"
    p.write_bytes(b'{\n "a": 1\n}\n')
    with pytest.raises(TypeError):
        json_io.dump_json(p, {"a": object()})
    assert p.read_bytes() == b'{\n "a": 1\n}\n'
    assert not list(tmp_path.glob("*.tmp"))


def test_transient_replace_failure_is_retried(tmp_path, monkeypatch):
    p = tmp_path / "f.json"
    p.write_bytes(b'{\n "a": 1\n}\n')
    real = json_io.os.replace
    state = {"n": 0}

    def flaky(src, dst):
        state["n"] += 1
        if state["n"] < 3:
            raise PermissionError(13, "winerror 5")
        return real(src, dst)

    monkeypatch.setattr(json_io.os, "replace", flaky)
    monkeypatch.setattr(json_io.time, "sleep", lambda _s: None)
    json_io.dump_json(p, {"a": 2})
    assert p.read_bytes() == b'{\n "a": 2\n}\n'
    assert state["n"] == 3


def test_persistent_replace_failure_raises_and_cleans_tmp(tmp_path, monkeypatch):
    p = tmp_path / "f.json"
    p.write_bytes(b'{\n "a": 1\n}\n')

    def always(src, dst):
        raise PermissionError(13, "locked")

    monkeypatch.setattr(json_io.os, "replace", always)
    monkeypatch.setattr(json_io.time, "sleep", lambda _s: None)
    with pytest.raises(PermissionError):
        json_io.dump_json(p, {"a": 2})
    assert p.read_bytes() == b'{\n "a": 1\n}\n'
    assert not list(tmp_path.glob("*.tmp"))
