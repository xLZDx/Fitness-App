"""Behaviour tests for tools/evidence/validate_csv_evidence.py.

Each test builds a throwaway evidence tree and points the validator at it, so a
broken check turns the matching test red instead of passing on the real corpus.
"""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import io
import os
from contextlib import redirect_stdout
from pathlib import Path

import pytest

_MODULE_PATH = Path(__file__).with_name("validate_csv_evidence.py")

GO = "+ГО"  # the Cyrillic marker, written as escapes so the file's encoding cannot matter
GO_COMMIT = GO + "|КОМИТ"


@pytest.fixture()
def v(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("validate_csv_evidence_under_test", _MODULE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    (tmp_path / "core" / "plans").mkdir(parents=True)
    monkeypatch.setattr(mod, "REPO", str(tmp_path))
    monkeypatch.setattr(mod, "ACTION_LOG", str(tmp_path / "core" / "plans" / "log.csv"))
    # No git in the sandbox: every SHA is "known" unless a test says otherwise.
    monkeypatch.setattr(mod, "git", lambda *a: "commit")
    monkeypatch.setattr(mod, "_is_ancestor", lambda sha: True)
    mod.failures.clear()
    mod.notes.clear()
    mod._tmp = tmp_path
    return mod


def _row(seq="1", ts="2026-10-01T10:00:00", marker=GO, action="did a thing", commit=""):
    return [seq, ts, marker, action, "cmd", "target", "ok", "gate", commit, "not journalled"]


def _write_log(mod, rows, header=None, newline="\n"):
    header = header if header is not None else mod.ACTION_LOG_HEADER
    with open(mod.ACTION_LOG, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator=newline)
        w.writerow(header)
        w.writerows(rows)


def _run(mod):
    buf = io.StringIO()
    with redirect_stdout(buf):
        code = mod.main()
    return code, buf.getvalue()


def test_valid_log_without_audit_dir_exits_zero(v):
    _write_log(v, [_row("1"), _row("2", commit="")])
    code, out = _run(v)
    assert code == 0, out
    assert "all CSV evidence valid" in out


def test_missing_action_log_exits_one(v):
    code, out = _run(v)
    assert code == 1
    assert "action log missing" in out


def test_empty_action_log_fails(v):
    Path(v.ACTION_LOG).write_bytes(b"")
    assert _run(v)[0] == 1
    assert any("empty" in f for f in v.failures)


def test_wrong_header_fails(v):
    _write_log(v, [_row()], header=["a", "b"])
    assert _run(v)[0] == 1
    assert any("header" in f for f in v.failures)


def test_header_without_rows_fails(v):
    _write_log(v, [])
    assert _run(v)[0] == 1
    assert any("no rows" in f for f in v.failures)


def test_out_of_order_and_duplicate_sequence_fail(v):
    _write_log(v, [_row("2"), _row("1"), _row("2")])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "does not follow" in joined
    assert "duplicate sequence" in joined


def test_non_integer_sequence_and_bad_timestamp_fail(v):
    _write_log(v, [_row("x"), _row("2", ts="yesterday")])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "not an integer" in joined
    assert "ISO-8601" in joined


def test_unknown_marker_and_blank_action_fail(v):
    _write_log(v, [_row("1", marker="GO"), _row("2", action="   ")])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "marker" in joined
    assert "action is empty" in joined


def test_wrong_field_count_is_reported_not_crashed(v):
    _write_log(v, [_row("1")[:5]])
    assert _run(v)[0] == 1
    assert any("fields, expected" in f for f in v.failures)


def test_commit_marker_requires_sha_and_sha_must_be_hex(v):
    _write_log(v, [_row("1", marker=GO_COMMIT, commit=""), _row("2", commit="zzzzzzz")])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "commit column is empty" in joined
    assert "not a hex SHA" in joined


def test_sha_not_in_repository_or_not_ancestor_fails(v, monkeypatch):
    _write_log(v, [_row("1", commit="abcdef1"), _row("2", commit="abcdef2")])
    monkeypatch.setattr(v, "git", lambda *a: "" if a[-1] == "abcdef1" else "commit")
    monkeypatch.setattr(v, "_is_ancestor", lambda sha: False)
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "abcdef1, which is not a commit" in joined
    assert "abcdef2, which is not reachable" in joined


def test_historical_gap_note_must_stay(v):
    rows = [_row("1")]
    rows[0][-1] = "all good"
    _write_log(v, rows)
    assert _run(v)[0] == 1
    assert any("historical-gap" in f for f in v.failures)


def test_crlf_log_with_quoted_commas_parses(v):
    rows = [_row("1")]
    rows[0][3] = "action, with, commas — пример"
    _write_log(v, rows, newline="\r\n")
    code, out = _run(v)
    assert code == 0, out


def _manifest(directory: Path, rows, header=None):
    header = header or ["filename", "sha256", "bytes", "row_count", "state", "purpose"]
    with open(directory / "MANIFEST.csv", "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def _audit_dir(mod):
    d = mod._tmp / "core" / "audit" / "batch1"
    d.mkdir(parents=True)
    _write_log(mod, [_row("1")])
    return d


def _good_artifact(d: Path):
    data = b"a,b\n1,2\n3,4\n"
    (d / "data.csv").write_bytes(data)
    return ["data.csv", hashlib.sha256(data).hexdigest(), str(len(data)), "2", "ORIGINAL_PRESERVED", "why"]


def test_audit_manifest_happy_path(v):
    d = _audit_dir(v)
    _manifest(d, [_good_artifact(d)])
    code, out = _run(v)
    assert code == 0, out
    assert "hashes and row counts verified" in out


def test_audit_dir_without_manifest_fails(v):
    _audit_dir(v)
    assert _run(v)[0] == 1
    assert any("no MANIFEST.csv" in f for f in v.failures)


def test_tampered_file_fails_hash_and_size(v):
    d = _audit_dir(v)
    row = _good_artifact(d)
    (d / "data.csv").write_bytes(b"a,b\n1,2\n3,5!\n")
    _manifest(d, [row])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "hashes to" in joined
    assert "bytes, manifest says" in joined


def test_listed_but_absent_and_present_but_unlisted_fail(v):
    d = _audit_dir(v)
    good = _good_artifact(d)
    (d / "stray.csv").write_text("x\n", encoding="utf-8")
    _manifest(d, [good, ["gone.csv", "0" * 64, "1", "", "REGENERATED", "p"]])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "gone.csv is listed and absent" in joined
    assert "present and unlisted" in joined and "stray.csv" in joined


def test_bad_state_blank_purpose_and_missing_columns(v):
    d = _audit_dir(v)
    row = _good_artifact(d)
    row[4], row[5] = "EDITED", " "
    _manifest(d, [row])
    assert _run(v)[0] == 1
    joined = "\n".join(v.failures)
    assert "neither ORIGINAL_PRESERVED nor REGENERATED" in joined
    assert "no purpose recorded" in joined

    v.failures.clear()
    _manifest(d, [["data.csv", "x"]], header=["filename", "sha256"])
    assert _run(v)[0] == 1
    assert any("missing columns" in f for f in v.failures)


def test_ragged_rows_and_row_count_mismatch_fail(v):
    d = _audit_dir(v)
    data = b"a,b\n1,2\n3\n"
    (d / "data.csv").write_bytes(data)
    _manifest(d, [["data.csv", hashlib.sha256(data).hexdigest(), str(len(data)), "2", "ORIGINAL_PRESERVED", "p"]])
    assert _run(v)[0] == 1
    assert any("ragged rows" in f for f in v.failures)

    v.failures.clear()
    data = b"a,b\n1,2\n3,4\n"
    (d / "data.csv").write_bytes(data)
    _manifest(d, [["data.csv", hashlib.sha256(data).hexdigest(), str(len(data)), "5", "ORIGINAL_PRESERVED", "p"]])
    assert _run(v)[0] == 1
    assert any("has 2 rows, manifest says 5" in f for f in v.failures)


def test_utf8_bom_csv_header_is_not_counted_as_data(v):
    d = _audit_dir(v)
    data = b"\xef\xbb\xbfa,b\r\n1,2\r\n"
    (d / "data.csv").write_bytes(data)
    _manifest(d, [["data.csv", hashlib.sha256(data).hexdigest(), str(len(data)), "1", "ORIGINAL_PRESERVED", "p"]])
    code, out = _run(v)
    assert code == 0, out


def test_script_exit_code_is_the_process_exit_code(tmp_path):
    """Run as a real process: a failing tree must produce a non-zero status."""
    import subprocess
    import sys

    root = tmp_path / "repo"
    (root / "tools" / "evidence").mkdir(parents=True)
    (root / "tools" / "evidence" / "validate_csv_evidence.py").write_bytes(_MODULE_PATH.read_bytes())
    proc = subprocess.run(
        [sys.executable, str(root / "tools" / "evidence" / "validate_csv_evidence.py")],
        capture_output=True, text=True, encoding="utf-8", env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    assert proc.returncode == 1
    assert "action log missing" in proc.stdout
