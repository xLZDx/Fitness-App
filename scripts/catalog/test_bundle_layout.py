# -*- coding: utf-8 -*-
"""Tests for the bundle naming policy.

Every case here is taken from the delivered archive rather than invented, and
the first group exists because the obvious implementation of it is wrong.

    python -m pytest scripts/catalog/test_bundle_layout.py -q
"""
from __future__ import annotations

import pytest

from bundle_layout import (
    canonical_stem,
    object_path,
    plan_import,
    split_gender,
)


class TestGender:
    """The suffix is inconsistently cased and 211 clips depend on noticing."""

    @pytest.mark.parametrize(
        "stem, expected",
        [
            ("Plate Squat Hold_Female", "girl"),
            ("plate squat hold_female", "girl"),
            ("Cable Fly_FEMALE", "girl"),
            ("Bodyweight Hip Thrust", "men"),
            ("Barbell Row_Male", "men"),
        ],
    )
    def test_case_does_not_decide_who_is_shown(self, stem, expected):
        assert split_gender(stem)[1] == expected

    def test_the_suffix_leaves_with_its_gender(self):
        # Otherwise every women's clip is a different exercise from the men's
        # one and nothing lines up.
        assert split_gender("Plate Squat Hold_Female")[0] == "Plate Squat Hold"
        assert split_gender("plate squat hold_female")[0] == "plate squat hold"

    def test_a_trailing_space_after_the_suffix_still_reads(self):
        assert split_gender("Cat Stretch_Female ") == ("Cat Stretch", "girl")

    def test_unsuffixed_is_the_male_render(self):
        # 1,815 of 2,578 carry no suffix, and many have a _Female twin.
        assert split_gender("Superman") == ("Superman", "men")

    def test_a_version_marker_after_the_gender_does_not_hide_it(self):
        # One delivered clip is `...Inverted Row on floor_female_1`. Anchoring
        # hard to the end filed it under men -- the same failure the
        # case-insensitivity guards against, arriving through a second door.
        assert split_gender("Inverted Row_female_1") == ("Inverted Row_1", "girl")
        assert split_gender("Inverted Row_1") == ("Inverted Row_1", "men")

    def test_the_versioned_pair_lines_up_as_one_exercise(self):
        # Both renders must land on the same stem, or the woman's clip is a
        # different exercise from the man's and nothing pairs.
        girl = split_gender("Inverted Row_female_1")
        men = split_gender("Inverted Row_1")
        assert girl[0] == men[0]
        assert {girl[1], men[1]} == {"girl", "men"}

    def test_a_word_ending_in_male_is_not_a_gender_marker(self):
        assert split_gender("Shemale Press")[1] == "men"
        assert split_gender("Barbell Row")[0] == "Barbell Row"

    @pytest.mark.parametrize(
        "stem, expected_stem",
        [
            ("Jump Rope Basic Jump Female", "Jump Rope Basic Jump"),
            ("Air Swing Walking Female", "Air Swing Walking"),
            ("Alternate Leg Raise with Head Up Female", "Alternate Leg Raise with Head Up"),
        ],
    )
    def test_a_space_before_the_suffix_counts_too(self, stem, expected_stem):
        # Thirteen delivered files write the separator as a space. All thirteen
        # were filed as men's clips AND kept the word "Female" in the title the
        # user reads -- a third variation on the same convention, after the
        # inconsistent casing and the trailing version marker.
        assert split_gender(stem) == (expected_stem, "girl")

    def test_the_spaced_pair_lines_up_with_its_male_twin(self):
        assert (split_gender("Jump Rope Basic Jump Female")[0]
                == split_gender("Jump Rope Basic Jump")[0])


class TestWhitespace:
    """297 delivered stems cannot be stored under their own names on Windows."""

    @pytest.mark.parametrize(
        "raw, expected",
        [
            ("superman ", "superman"),
            ("box jump  ", "box jump"),
            (" bird dog", "bird dog"),
            ("Dead  Bug", "Dead Bug"),
        ],
    )
    def test_ends_stripped_and_middle_collapsed(self, raw, expected):
        assert canonical_stem(raw) == expected

    def test_an_object_key_never_ends_in_a_space(self):
        key = object_path("Abdominals/box jump  .mp4")
        assert key == "exercises/men/Abdominals/box jump.mp4"
        assert " .mp4" not in key


class TestObjectPath:
    def test_matches_the_shape_the_signing_function_allows(self):
        # functions/src/video_urls.ts: exercises/(girl|men)/<seg>/<file>.mp4
        import re

        pattern = re.compile(r"^exercises/(girl|men)/[^/]{1,120}/[^/]{1,160}\.mp4$")
        for member in [
            "Legs/Plate Squat Hold_Female.mp4",
            "Calisthenics-Cardio-Plyo-Functional/box jump  .mp4",
            "Stretching - Mobility/cat stretch_female.mp4",
        ]:
            assert pattern.match(object_path(member)), member

    def test_the_group_folder_is_preserved(self):
        assert object_path("Yoga/Bird Dog.mp4") == "exercises/men/Yoga/Bird Dog.mp4"

    def test_a_loose_file_gets_a_home_rather_than_a_leading_slash(self):
        # A member at the archive root would otherwise produce
        # "exercises/men//name.mp4", which the allow-list rejects.
        assert object_path("orphan.mp4") == "exercises/men/Misc/orphan.mp4"


class TestPlanImport:
    def test_a_case_only_collision_is_one_exercise_not_two(self):
        # The delivered archive has 15 of these. Object keys are case-sensitive,
        # so keying on the exact name would ship both renders and leave the
        # catalog with two candidates for one movement.
        plan = plan_import({"Yoga/Bird Dog.mp4": 100, "Yoga/bird dog .mp4": 900})
        assert len(plan.chosen) == 1
        assert plan.chosen == {"exercises/men/Yoga/bird dog.mp4": "Yoga/bird dog .mp4"}
        assert plan.total_discarded == 1

    def test_an_exact_collision_keeps_the_larger(self):
        plan = plan_import({"Yoga/Bird Dog.mp4": 100, "Yoga/Bird Dog  .mp4": 900})
        assert plan.chosen["exercises/men/Yoga/Bird Dog.mp4"] == "Yoga/Bird Dog  .mp4"
        assert plan.discarded["exercises/men/Yoga/Bird Dog.mp4"] == ["Yoga/Bird Dog.mp4"]

    def test_a_tie_is_broken_the_same_way_every_run(self):
        # An import that shuffles between runs is not reproducible.
        listing = {"Legs/Squat .mp4": 500, "Legs/Squat.mp4": 500}
        first = plan_import(listing).chosen
        second = plan_import(dict(reversed(list(listing.items())))).chosen
        assert first == second

    def test_the_one_genuinely_ambiguous_pair_is_reported_not_guessed(self):
        plan = plan_import(
            {
                "Legs/calf raise on hack squat machine.mp4": 100,
                "Legs/calf raise on hack squat machine .mp4": 900,
            }
        )
        assert plan.ambiguous == [
            "exercises/men/Legs/calf raise on hack squat machine.mp4"
        ]

    def test_men_and_women_are_never_the_same_key(self):
        plan = plan_import(
            {"Legs/Squat.mp4": 100, "Legs/Squat_Female.mp4": 100}
        )
        assert set(plan.chosen) == {
            "exercises/men/Legs/Squat.mp4",
            "exercises/girl/Legs/Squat.mp4",
        }
        assert not plan.discarded

    def test_non_video_members_are_ignored(self):
        plan = plan_import({"Legs/Squat.mp4": 1, "Legs/readme.txt": 1})
        assert list(plan.chosen) == ["exercises/men/Legs/Squat.mp4"]
