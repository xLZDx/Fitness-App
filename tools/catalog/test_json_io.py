"""Behaviour tests for tools/catalog/json_io.py: rewrite JSON without reformatting."""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("json_io_under_test", Path(__file__).with_name("json_io.py"))
json_io = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(json_io)


def _write(path: Path, text: str, newline: str) -> None:
    with open(path, "w", encoding="utf-8", newline=newline) as fh:
        fh.write(text)


@pytest.mark.parametrize("indent", [1, 2, 4])
@pytest.mark.parametrize("newline", ["\n", "\r\n"])
def test_detect_format_reads_indent_and_newline(tmp_path, indent, newline):
    p = tmp_path / "f.json"
    pad = " " * indent
    p.write_bytes(('{' + newline + pad + '"a": 1' + newline + '}' + newline).encode())
    assert json_io.detect_format(p) == (indent, newline)


def test_detect_format_defaults_when_nothing_is_indented(tmp_path):
    p = tmp_path / "f.json"
    _write(p, "[]\n", "\n")
    assert json_io.detect_format(p) == (2, "\n")


@pytest.mark.parametrize("indent", [1, 4])
@pytest.mark.parametrize("newline", ["\n", "\r\n"])
def test_dump_roundtrip_is_byte_identical_for_unchanged_data(tmp_path, indent, newline):
    p = tmp_path / "f.json"
    pad = " " * indent
    original = '{' + newline + pad + '"name": "Жим",' + newline + pad + '"n": [' + newline + pad * 2 + '1' + newline + pad + ']' + newline + '}' + newline
    p.write_bytes(original.encode("utf-8"))
    before = p.read_bytes()
    json_io.dump_json(p, json_io.load_json(p))
    assert p.read_bytes() == before  # no formatting-only diff, no \r\r\n, no \u escapes


def test_dump_keeps_non_ascii_literal_and_single_trailing_newline(tmp_path):
    p = tmp_path / "f.json"
    _write(p, '{\n "a": 1\n}\n', "\n")
    json_io.dump_json(p, {"a": "éж"})
    raw = p.read_bytes()
    assert "éж".encode("utf-8") in raw
    assert b"\\u" not in raw
    assert raw.endswith(b"}\n") and not raw.endswith(b"\n\n")
    assert b"\r" not in raw


def test_dump_on_crlf_file_never_doubles_carriage_returns(tmp_path):
    p = tmp_path / "f.json"
    p.write_bytes(b'{\r\n  "a": 1\r\n}\r\n')
    json_io.dump_json(p, {"a": 1, "b": 2})
    raw = p.read_bytes()
    assert b"\r\r" not in raw
    assert raw.count(b"\r\n") == raw.count(b"\n")


def test_load_json_rejects_invalid_and_non_utf8(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{not json", encoding="utf-8")
    with pytest.raises(ValueError):
        json_io.load_json(bad)
    latin = tmp_path / "latin.json"
    latin.write_bytes(b'{"a": "\xe9"}')
    with pytest.raises(UnicodeDecodeError):
        json_io.load_json(latin)


def test_load_json_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        json_io.load_json(tmp_path / "nope.json")
