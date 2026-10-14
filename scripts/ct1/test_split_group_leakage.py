# -*- coding: utf-8 -*-
"""Known-baseline report: near-duplicate groups that straddle train/holdout.

    python -m pytest scripts/ct1/test_split_group_leakage.py -q

`split_for` hashes the item id, so rows whose content is identical but whose ids
differ can land on opposite sides of the split. Making the split group-aware
would change every existing assignment and dataset hash, so it is deliberately
NOT changed here. This test measures the leakage and pins today's number as a
KNOWN BASELINE: a change in the number means the corpus or the split moved and
the new figure must be recorded on purpose (a group-aware split should drive it
to 0 in a future dataset version).
"""
from __future__ import annotations

import collections
import json
import re
import subprocess

import pytest

from baseline import DATA
from build_dataset import split_for

# Measured on exercises_vendor.json (1,887 rows) when this test was written:
# 13 groups of rows sharing an identical normalised steps block are split
# across train and holdout. No title group straddles.
KNOWN_STEPS_GROUPS_STRADDLING = 9
KNOWN_TITLE_GROUPS_STRADDLING = 0


def _norm(text) -> str:
    return re.sub(r"\W+", " ", (text or "").lower()).strip()


def _straddling(rows, key) -> int:
    splits: dict[str, set[str]] = collections.defaultdict(set)
    for row in rows:
        k = key(row)
        if k and row.get("id"):
            splits[k].add(split_for(row["id"]))
    return sum(1 for v in splits.values() if len(v) > 1)


def _rows():
    # Pinned to the COMMITTED catalogue (HEAD), not the working tree: the catalogue
    # data is edited by other work and a moving input cannot hold a baseline.
    try:
        raw = subprocess.run(
            ["git", "show", "HEAD:mobile/assets/data/exercises_vendor.json"],
            capture_output=True, check=True, timeout=30, cwd=str(DATA),
        ).stdout
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        pytest.skip("git unavailable: cannot read the committed catalogue")
    return json.loads(raw.decode("utf-8"))


def test_a_synthetic_duplicate_pair_is_detected_as_straddling():
    # Proves the measurement can fail: find two ids on opposite sides and give
    # them identical steps.
    a = next(f"a{i}" for i in range(1000) if split_for(f"a{i}") == "train")
    b = next(f"b{i}" for i in range(1000) if split_for(f"b{i}") == "holdout")
    rows = [{"id": a, "steps": ["Do x"]}, {"id": b, "steps": ["do x."]}]
    assert _straddling(rows, lambda r: _norm(" ".join(r["steps"]))) == 1


def test_known_baseline_of_near_duplicate_groups_straddling_the_split():
    rows = _rows()
    steps = _straddling(
        rows, lambda r: "|".join(_norm(s) for s in r.get("steps") or []))
    title = _straddling(rows, lambda r: _norm(r.get("title")))
    print(f"near-duplicate groups straddling train/holdout: "
          f"steps={steps} title={title}")
    assert steps == KNOWN_STEPS_GROUPS_STRADDLING
    assert title == KNOWN_TITLE_GROUPS_STRADDLING
