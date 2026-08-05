# -*- coding: utf-8 -*-
"""Rules for the pose-pattern tagging pass.

The interesting cases are the ones that cost a rewrite: a title carrying two
pattern words that is not actually ambiguous, and a title carrying two that is.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from tag_pose_targets import CATALOG, classify, load_vocab  # noqa: E402


@pytest.fixture(scope="module")
def vocab():
    return load_vocab()


def tag(vocab, title, equipment=None):
    patterns, ex_title, ex_equipment = vocab
    row = {"title": title, "equipmentLabel": equipment}
    return classify(row, patterns, ex_title, ex_equipment)[0]


@pytest.mark.parametrize("title,expected", [
    ("Barbell Back Squat", "squat"),
    ("Goblet Squat", "squat"),
    ("Air Squat", "squat"),
    ("Barbell Romanian Deadlift", "hinge"),
    ("Kettlebell Swing", "hinge"),
    ("Glute Bridge", "hinge"),
    ("Walking Lunge", "lunge"),
    ("Dumbbell Step-up", "lunge"),
    ("Wide Push-up", "pushup"),
    ("Front Plank", "pushup"),
    ("Dumbbell Shoulder Press", "overhead_press"),
    ("Hammer Curl", "curl"),
    ("Bicycle Crunch", "situp"),
    ("Standing Calf Raise", "calf_raise"),
])
def test_tags_the_obvious_cases(vocab, title, expected):
    assert tag(vocab, title) == expected


@pytest.mark.parametrize("title", [
    "Bulgarian Split Squat",
    "Barbell Split Squat",
    "Band Single Leg Split Squat",
])
def test_split_squats_are_lunges_not_squats(vocab, title):
    """The rewrite this pass needed.

    These carry the word "squat" and are the split-stance silhouette. Without
    the per-pattern `notTitle` exclusion they matched two patterns and the
    ambiguity rule dropped all forty of them -- correct behaviour applied to a
    question that was never ambiguous.
    """
    assert tag(vocab, title) == "lunge"


@pytest.mark.parametrize("title", [
    "Dumbbell Lunge to Overhead Press",
    "Biceps Curl to Shoulder Press Resistance Band",
    "Alternating Plank Lunge",
])
def test_two_movements_in_one_stay_untagged(vocab, title):
    """Genuinely ambiguous, and it must stay that way.

    One silhouette cannot score two movements, and guessing which half the
    user is in is worse than offering nothing.
    """
    assert tag(vocab, title) is None


@pytest.mark.parametrize("title", [
    "Seated Calf Raise",
    "Lying Leg Curl",
    "Hack Squat Machine",
    "Smith Machine Squat",
    "Bench Press",
])
def test_the_camera_cannot_see_these(vocab, title):
    """Seated, lying, or hidden behind a machine or bench.

    One shared exclusion list rather than per-pattern rules, because the reason
    is always the same: the hip line is not visible, and BlazePose has no
    spinal landmark to fall back on.
    """
    assert tag(vocab, title) is None


def test_equipment_alone_can_exclude(vocab):
    assert tag(vocab, "Squat") == "squat"
    assert tag(vocab, "Squat", equipment="Smith Machine") is None


def test_the_shipped_catalog_carries_only_known_patterns(vocab):
    """Nothing in the catalog may carry a tag the vocabulary does not define.

    A typo'd id is invisible: `formCoachSupports` returns false for an unknown
    pattern, so the exercise just quietly loses its button.
    """
    patterns, _, _ = vocab
    known = {p["id"] for p in patterns}
    rows = json.loads(CATALOG.read_text("utf-8"))
    tags = {r["poseTargetId"] for r in rows if r.get("poseTargetId")}
    assert tags <= known, sorted(tags - known)
    assert tags, "the catalog has no pose tags at all -- was the pass run?"
