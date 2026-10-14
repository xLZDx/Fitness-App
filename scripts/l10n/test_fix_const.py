"""fix_const.py: a failing `flutter analyze` must not look like a clean tree."""
from __future__ import annotations

import importlib.util
import subprocess
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location(
    "fix_const_under_test", Path(__file__).with_name("fix_const.py"))
fix_const = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fix_const)


def _proc(code, out="", err=""):
    return subprocess.CompletedProcess(["flutter"], code, out, err)


def test_missing_flutter_is_a_failure_not_clean(monkeypatch):
    monkeypatch.setattr(fix_const.shutil, "which", lambda _n: None)
    with pytest.raises(fix_const.AnalyzeError):
        fix_const.analyze()


def test_nonzero_exit_without_findings_is_a_failure(monkeypatch):
    monkeypatch.setattr(fix_const.shutil, "which", lambda _n: "flutter.bat")
    monkeypatch.setattr(fix_const.subprocess, "run",
                        lambda *a, **k: _proc(2, "", "Could not resolve pub"))
    with pytest.raises(fix_const.AnalyzeError):
        fix_const.analyze()


def test_findings_on_stderr_are_parsed_and_use_no_shell(monkeypatch):
    seen = {}

    def run(*a, **k):
        seen.update(k)
        return _proc(1, "", "  error - x - lib\\a.dart:43:14 - const_eval_method_invocation\n")

    monkeypatch.setattr(fix_const.shutil, "which", lambda _n: "flutter.bat")
    monkeypatch.setattr(fix_const.subprocess, "run", run)
    hits = fix_const.analyze()
    assert hits == [(fix_const.MOBILE / "lib/a.dart", 43)]
    assert not seen.get("shell")


def test_strip_const_preserves_crlf(tmp_path):
    p = tmp_path / "a.dart"
    p.write_bytes(b"a\r\nconst Text('x');\r\nb\r\n")
    assert fix_const.strip_const_near(p, 2)
    assert p.read_bytes() == b"a\r\nText('x');\r\nb\r\n"
