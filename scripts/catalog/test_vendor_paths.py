# -*- coding: utf-8 -*-
"""One definition of where the vendor library is, and what happens when it is not there.

Four scripts each carried their own absolute path to the same three files and
three of them were stale. What made that expensive was not the typo: it was
that the resulting FileNotFoundError reads as a statement about the machine,
and it was written down as one -- in two commit messages and repeatedly in
chat -- rather than as a one-line bug. These tests are about the class of
failure, not the instance.
"""

from __future__ import annotations

import ast
import importlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import vendor_paths  # noqa: E402


class TestTheDefaultLocation:
    def test_the_three_files_the_pipeline_needs_are_named(self):
        assert vendor_paths.BUNDLE_ZIP.name == "4K UHD 2160P.zip"
        assert vendor_paths.VENDOR_META.name == "1500+ exercise data.xlsx"
        assert vendor_paths.EXERCISE_LIST.name == "EXERCISE LIST.xlsx"

    def test_they_all_sit_under_one_directory(self):
        # The bug was one directory of depth. Asserting the shared parent is
        # what stops a future edit from fixing two of three again.
        for path in (
            vendor_paths.BUNDLE_ZIP,
            vendor_paths.VENDOR_META,
            vendor_paths.EXERCISE_LIST,
        ):
            assert path.parent == vendor_paths.VENDOR_DIR

    def test_the_default_is_the_operators_copy(self):
        assert vendor_paths.DEFAULT_VENDOR_DIR == Path("D:/Downloads/Video/New folder")


class TestTheOverride:
    def test_an_env_var_moves_every_path_together(self, monkeypatch, tmp_path):
        monkeypatch.setenv("FITNESS_VENDOR_DIR", str(tmp_path))
        reloaded = importlib.reload(vendor_paths)
        try:
            assert reloaded.VENDOR_DIR == tmp_path
            assert reloaded.BUNDLE_ZIP.parent == tmp_path
            assert reloaded.VENDOR_META.parent == tmp_path
        finally:
            monkeypatch.delenv("FITNESS_VENDOR_DIR")
            importlib.reload(vendor_paths)

    def test_an_empty_env_var_falls_back_rather_than_pointing_at_cwd(
        self, monkeypatch
    ):
        # `os.environ.get(...) or DEFAULT` rather than a bare `get` with a
        # default: an exported-but-empty variable is common on Windows and
        # would otherwise resolve every vendor path to the current directory.
        monkeypatch.setenv("FITNESS_VENDOR_DIR", "")
        reloaded = importlib.reload(vendor_paths)
        try:
            assert reloaded.VENDOR_DIR == reloaded.DEFAULT_VENDOR_DIR
        finally:
            monkeypatch.delenv("FITNESS_VENDOR_DIR")
            importlib.reload(vendor_paths)


class TestTheErrorMessage:
    def test_missing_reports_only_what_is_absent(self, tmp_path):
        present = tmp_path / "here.txt"
        present.write_text("x", encoding="utf-8")
        absent = tmp_path / "gone.txt"
        assert vendor_paths.missing(present, absent) == [absent]

    def test_require_passes_when_everything_is_there(self, tmp_path):
        present = tmp_path / "here.txt"
        present.write_text("x", encoding="utf-8")
        vendor_paths.require(present)  # must not raise

    def test_require_names_the_file_and_the_directory_searched(self, tmp_path):
        absent = tmp_path / "4K UHD 2160P.zip"
        with pytest.raises(SystemExit) as exit_info:
            vendor_paths.require(absent)
        message = str(exit_info.value)
        assert "4K UHD 2160P.zip" in message
        assert str(vendor_paths.VENDOR_DIR) in message
        # The half that was missing before: telling the reader the path is a
        # setting, not a property of their machine.
        assert "FITNESS_VENDOR_DIR" in message


class TestNothingHardcodesItAnyMore:
    """The enforcement, rather than a comment asking people not to.

    Parsed rather than grepped, and docstrings are excluded deliberately: a
    usage example that names the real directory is documentation doing its job,
    while the same string as a default argument is a fourth copy waiting to go
    stale. The first version of this test could not tell them apart and flagged
    two `--drop` usage lines alongside three genuine bugs.
    """

    def _string_literals_in_code(self, source: str):
        tree = ast.parse(source)
        docstrings = {
            node.value
            for node in ast.walk(tree)
            if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant)
        }
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Constant)
                and isinstance(node.value, str)
                and node not in docstrings
            ):
                yield node.lineno, node.value

    def test_no_catalog_script_carries_its_own_vendor_path(self):
        offenders = []
        for script in sorted(Path(__file__).parent.glob("*.py")):
            if script.name in {"vendor_paths.py", Path(__file__).name}:
                continue
            source = script.read_text(encoding="utf-8")
            for lineno, text in self._string_literals_in_code(source):
                if "Downloads" in text:
                    offenders.append(f"{script.name}:{lineno}: {text!r}")
        assert offenders == [], (
            "these carry their own copy of a vendor path; import vendor_paths "
            "instead:\n" + "\n".join(offenders)
        )

    def test_the_check_would_catch_one(self):
        # Vacuous once the paths are clean, and a vacuous test reads exactly
        # like a passing one -- so the assertion itself is put under test.
        found = list(
            self._string_literals_in_code("X = 'D:/Downloads/Video'\n")
        )
        assert found == [(1, "D:/Downloads/Video")]

    def test_a_docstring_mention_is_not_an_offender(self):
        source = '"""Run with --drop D:/Downloads/Video."""\nX = 1\n'
        assert list(self._string_literals_in_code(source)) == []
