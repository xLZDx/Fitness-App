# -*- coding: utf-8 -*-
"""The generated legal surfaces must equal what `legal_text.py` renders.

    python -m pytest scripts/legal/test_build_legal_in_sync.py -q

`public/privacy.html`, `public/terms.html` and the keys `legalPrivacyBody`,
`legalTermsBody`, `legalLastUpdated` of `mobile/lib/l10n/app_{en,ru}.arb` are
generated. This test only reads: it calls `build_legal`'s own renderers and
compares in memory, so a hand edit of a generated file is caught without any
file being written. The positive control proves the comparison can fail.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_legal as bl  # noqa: E402

FIX = (
    "edit scripts/legal/legal_text.py and run scripts/legal/build_legal.py; "
    "never edit the generated files"
)
LEGAL_ARB_KEYS = ("legalPrivacyBody", "legalTermsBody", "legalLastUpdated")


def _first_difference(expected: str, actual: str) -> str:
    """Empty when equal, else a short description of the first differing spot."""
    if expected == actual:
        return ""
    n = next(
        (i for i, (a, b) in enumerate(zip(expected, actual)) if a != b),
        min(len(expected), len(actual)),
    )
    return (
        f"first difference at character {n}: rendered {expected[n:n + 60]!r} "
        f"vs on disk {actual[n:n + 60]!r} (lengths {len(expected)} vs {len(actual)})"
    )


def _stale_message(path: Path, detail: str) -> str:
    return f"{path.relative_to(bl.ROOT).as_posix()} is stale or hand-edited ({detail}). {FIX}."


@pytest.mark.parametrize("doc", sorted(bl.DOCS))
def test_public_page_matches_the_render(doc):
    path = bl.PUBLIC_DIR / f"{doc}.html"
    assert path.exists(), _stale_message(path, "file is missing")
    detail = _first_difference(bl.render_html(doc), path.read_text(encoding="utf-8"))
    assert not detail, _stale_message(path, detail)


@pytest.mark.parametrize("lang", ["en", "ru"])
def test_arb_legal_keys_match_the_render(lang):
    path = bl.ARB_DIR / f"app_{lang}.arb"
    data = json.loads(path.read_text(encoding="utf-8"))
    expected = bl.arb_updates(lang)
    assert set(expected) == set(LEGAL_ARB_KEYS), "build_legal changed the set of legal ARB keys; update this test"
    for key in LEGAL_ARB_KEYS:
        assert key in data, _stale_message(path, f"key {key} is missing")
        detail = _first_difference(expected[key], data[key])
        assert not detail, _stale_message(path, f"{key}: {detail}")


# ------------------------------------------------------------ positive controls

def test_the_comparison_reports_a_difference_for_an_altered_string():
    """Without this, the tests above would pass against a comparison that always succeeds."""
    rendered = bl.render_html("privacy")
    assert _first_difference(rendered, rendered) == ""
    altered = rendered.replace("<h2>", "<h3>", 1)
    assert altered != rendered, "the control string was not altered"
    assert _first_difference(rendered, altered) != ""
    assert _first_difference(rendered, rendered + " ") != "", "a trailing difference must be reported"
    assert _first_difference(rendered, rendered[:-1]) != "", "a truncated file must be reported"


def test_the_failure_message_names_the_file_and_the_fix():
    msg = _stale_message(bl.PUBLIC_DIR / "privacy.html", "x")
    assert "public/privacy.html" in msg
    assert "edit scripts/legal/legal_text.py" in msg
    assert "never edit the generated files" in msg
