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
    ("Walking Lunge", "lunge"),
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
    # Not in the sagittal plane -- a side-on camera sees these edge-on.
    "4 Punches Side Squat",
    "Balance Board Lateral Squat",
    "Curtsy Squat",
    "Cossack Squat",
    "Counterbalanced Skater Squat",
    # Not bilateral; the target draws two legs together.
    "Dumbbell Single Leg Squat",
    "Jumping Pistol Squat",
    "Bodyweight Kneeling Sissy Squat",
    # Not upright.
    "Barbell Kneeling Squat",
    # Isometric: RepCounter needs a full lap of the phase ladder, and a hold
    # never leaves the bottom.
    "Plate Squat Hold",
    "Wall Squat Bodyweight",
    # Two movements in one.
    "Band Squat Row",
    "Landmine Squat and Press",
    "Burpee Squat",
    "Bodyweight Squat to Side Leg",
    # The word is in the equipment's name, not the movement's.
    "Barbell Incline Shoulders Press (inside Squat Cage)",
])
def test_only_the_bilateral_sagittal_squat_is_tagged(vocab, title):
    """`squat` is the ONE pattern the coach supports, so a false positive here
    reaches a user immediately -- with a target that scores their correct rep
    badly, which is exactly the lesson `formCoachSupports` exists to prevent.

    Found by listing all 69 rows the first rule tagged and reading them, not by
    reasoning about the regex.
    """
    assert tag(vocab, title) is None


@pytest.mark.parametrize("title", [
    # A depth cue, not a second movement.
    "Barbell Squat to Grass",
    # A paused rep still completes a lap.
    "Barbell Squat with 2 Sec Hold",
    "Barbell Full Squat(with Rack)",
    "Dumbbell Goblet Squat",
    "Barbell Low Bar Squat",
])
def test_the_pruning_did_not_take_real_squats_with_it(vocab, title):
    assert tag(vocab, title) == "squat"


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


@pytest.mark.parametrize("title", [
    # Supine. The hinge target draws a standing deadlift; these are done on
    # the back. A hip hinge at the JOINT is not the hinge SILHOUETTE, and the
    # tag is about the silhouette.
    "Glute Bridge",
    "Barbell Hip Thrust",
    "Dumbbell Feet Elevated Single Leg Glute Bridge",
    "Kettlebell Hip Thrusts",
    # The wrist moves and the elbow does not, which is the whole signal.
    "Barbell Standing Back Wrist Curl",
    "Dumbbell One Arm Reverse Wrist Curl",
    # Rotation and lateral flexion: a side-on camera sees them edge-on.
    "Oblique Crunch",
    "Air Twisting Crunch",
    "Hanging Oblique Crunches",
    # A hold never completes a lap of the phase ladder.
    "Hollow Hold",
    "Plate Hollow Hold",
    # A step-up rises onto a platform; the lunge target drops a knee toward
    # the floor. Opposite direction, and the platform is not in the drawing.
    "Dumbbell Step-up",
    "Barbell Side Step Up",
    # Rolled ninety degrees out of the plank shape this pattern draws.
    "Side Plank",
    "Dumbbell Side Plank with Rear Fly",
])
def test_the_silhouette_not_the_joint(vocab, title):
    """Gate C, 2026-09-07: six families where the rule had matched the movement
    rather than the shape.

    The distinction is the module header's own: a tag says this row's
    silhouette, seen from the side, IS the pattern. `Glute Bridge` was tagged
    `hinge` because a hip thrust hinges at the hip, and 43 rows inherited a
    standing deadlift animation for a movement performed on the back.

    `Side Plank` is here on GPT-PM's finding, not mine: `pushup` reaches no
    user today, and I argued that made the false tag harmless. It does not.
    The tag asserts what the shape is, so it stays wrong until the day the
    pattern becomes coachable and then it is wrong in front of someone.
    """
    assert tag(vocab, title) is None


@pytest.mark.parametrize("title,expected", [
    # The narrowing is title-shaped, so the risk is that it reaches further
    # than it was argued to. These are the neighbours of each removed family.
    ("Barbell Romanian Deadlift", "hinge"),
    ("Kettlebell Swing", "hinge"),
    ("Barbell Good Morning", "hinge"),
    ("Walking Lunge", "lunge"),
    ("Dumbbell Rear Lunge From Step", "lunge"),   # a lunge that starts on a step
    ("Bulgarian Split Squat", "lunge"),
    ("Hammer Curl", "curl"),
    ("Barbell Preacher Curl", "curl"),
    ("Bicycle Crunch", "situp"),
    ("Decline Sit Up", "situp"),
    ("Front Plank", "pushup"),                    # deliberately still a pushup
    ("Wide Push-up", "pushup"),
])
def test_the_narrowing_took_nothing_real_with_it(vocab, title, expected):
    assert tag(vocab, title) == expected


def test_the_shipped_catalog_matches_the_rules(vocab):
    """The asset must equal what the rules produce -- every row, nulls included.

    This is the control whose absence let seven rows drift: they carried tags
    the rules had stopped producing (all seven excluded by `equipmentLabel`,
    six on `Weight bench`), and nothing anywhere compared the two. A test over
    a list of families would not have found them; only equality does.

    It also means a hand edit to `poseTargetId` fails here rather than
    surviving quietly -- `build_vendor_catalog.py` treats the field as CURATED
    and preserves it, so the builder will not correct one.
    """
    patterns, ex_title, ex_equipment = vocab
    rows = json.loads(CATALOG.read_text("utf-8"))
    assert len(rows) == 1887, "the catalog changed size; re-read this test"
    wrong = [
        (r["id"], r.get("poseTargetId"), classify(r, patterns, ex_title, ex_equipment)[0])
        for r in rows
        if r.get("poseTargetId") != classify(r, patterns, ex_title, ex_equipment)[0]
    ]
    assert not wrong, (
        f"{len(wrong)} of {len(rows)} rows disagree with the rules; "
        f"run `python scripts/catalog/tag_pose_targets.py --transitions`: {wrong[:10]}"
    )


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
