# -*- coding: utf-8 -*-
"""B1 step 15 -- the registry B1 must never touch, verified as an invariant.

B1 builds a terms-CAPTURE mechanism. It never grants a right, never flips a
review state, and never edits `source_registry.json` -- that file stays under
P0.G3/P1.G5's own governance, untouched by this gate. These tests pin that
claim to the actual committed registry rather than to a description of it, and
the git-diff test below pins it to the actual working tree rather than to a
memory of what B1's own commits touched.

    python -m pytest scripts/equipment_identity/test_b1_registry_invariants.py -q
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rights  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

#: The six ways a source may be used, per rights.py's own vocabulary. All
#: false on every one of the 17 records: B1 finds captures, it does not grant
#: uses. See rights.py's REQUIRED_RIGHTS_FIELDS / validate_rights for where
#: these names are the real schema, not a copy of it.
GRANT_FIELDS = (
    "commercialAllowed", "displayAllowed", "recognitionProcessingAllowed",
    "trainingAllowed", "derivativeAllowed", "redistributionAllowed",
)


def test_the_real_registry_validates_under_rights_py():
    """`load_registry` raises on the first invalid record -- reaching a
    result at all is the proof, not a side effect of getting one."""
    sources = rights.load_registry()
    assert len(sources) >= 1


def test_the_real_registry_holds_exactly_seventeen_sources():
    """Pinned to the actual count as of B1's closure. A future source added
    by a LATER gate should fail this test loudly rather than let a stale
    '17' quietly become false -- at which point the number here is the thing
    to update, with a note for why it grew."""
    sources = rights.load_registry()
    assert len(sources) == 17


def test_every_source_is_unreviewed_with_every_grant_false():
    sources = rights.load_registry()
    assert len(sources) >= 1
    for record in sources:
        source_id = record["sourceId"]
        r = record["rights"]
        assert r["legalReviewState"] == "UNREVIEWED", (
            f"{source_id}: legalReviewState is {r['legalReviewState']!r}, not UNREVIEWED -- "
            "B1 must never observe a source that has already been reviewed by a different gate"
        )
        for field in GRANT_FIELDS:
            assert r[field] is False, f"{source_id}: {field} is {r[field]!r}, not False"
        assert r["noAiRestriction"] is True, (
            f"{source_id}: noAiRestriction is {r['noAiRestriction']!r}, not True"
        )
        assert r["termsCaptured"] is False, (
            f"{source_id}: termsCaptured is {r['termsCaptured']!r}, not False -- B1 builds the "
            "capture MECHANISM (B1); it does not itself capture a real document (B2 stays "
            "human-blocked), so no record should show a completed capture yet"
        )


def test_source_registry_json_has_zero_uncommitted_diff():
    """The mechanical form of 'B1 never touches this file': not a claim about
    what B1's own commits contained, but a live check of the working tree at
    the moment this test runs, against the real git history."""
    completed = subprocess.run(
        ["git", "diff", "HEAD", "--", "core/equipment_identity/p0/source_registry.json"],
        cwd=REPO, capture_output=True, text=True, check=True,
    )
    assert completed.stdout == "", (
        f"source_registry.json has uncommitted changes:\n{completed.stdout}"
    )
