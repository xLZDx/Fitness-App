# -*- coding: utf-8 -*-
"""The safety tagger, with the defects a review found written down as tests.

A tag means "hide this from someone whose injury is in that region". A false
negative shows an injured user a dangerous exercise; a false positive hides a
safe one. They are not symmetric, and neither is free.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import tag_contraindications as tagger  # noqa: E402

CATALOG = Path(__file__).resolve().parents[2] / "mobile/assets/data/exercises_vendor.json"


def row(title: str, muscles: list[str] | None = None, **extra) -> dict:
    base = {
        "id": "ea_" + title.lower().replace(" ", "_"),
        "title": title,
        "primaryMuscles": muscles or [],
        "steps": [],
        "vendorGroup": "Legs",
    }
    base.update(extra)
    return base


def fires(title: str, region: str, muscles: list[str] | None = None) -> bool:
    return tagger.classify(row(title, muscles), region) is not None


class TestTheVocabularyGuard:
    def test_every_rule_key_is_a_legal_tag(self):
        # `--region` offers RULES keys and apply_tags writes them verbatim,
        # while every reader silently drops a tag it does not recognise. A
        # renamed key would ship into the catalog, filter nobody, and appear in
        # no count and no test.
        assert tagger.unknown_regions() == []

    def test_the_guard_would_catch_a_stray_key(self, monkeypatch):
        monkeypatch.setitem(tagger.RULES, "kneee", [])
        assert tagger.unknown_regions() == ["kneee"]


class TestSpelling:
    """The class of false negative that a spot-check of the audit CSV found."""

    def test_a_plural_still_matches(self):
        # `\\bsquat\\b` missed "Barbell Front Squats".
        assert fires("Barbell Front Squats", "knee")

    def test_an_underscore_does_not_end_the_word(self):
        # `\\bleg curl\\b` missed "LEG Curl_single Leg": an underscore is a word
        # character, so the word never ended.
        assert fires("Hammer Strength Iso-lateral LEG Curl_single Leg", "knee")

    def test_a_hyphen_and_a_space_are_the_same_phrase(self):
        assert fires("Push-Up", "wrist")
        assert fires("Push Up", "wrist")

    @pytest.mark.parametrize("title", ["Running", "Jogging", "Treadmill Running"])
    def test_gerunds_are_caught(self, title):
        # The `(s|es)?` suffix cannot reach "running" from "run" -- the n
        # doubles -- so these were shown to knee- and ankle-injured users.
        assert fires(title, "knee"), title
        assert fires(title, "ankle"), title


class TestTheMuscleGate:
    """Words that name two different movements depending on the body part."""

    def test_an_arm_curl_is_an_elbow_contraindication(self):
        assert fires("Dumbbell Bicep Curl", "elbow", ["biceps"])

    def test_a_hamstring_curl_is_not(self):
        # "Alternating Hamstring Curl", primaryMuscles ["hamstrings"] -- a leg
        # machine that was being hidden from anyone with a sore elbow.
        assert not fires("Alternating Hamstring Curl", "elbow", ["hamstrings"])

    def test_a_glute_kickback_is_a_hip_contraindication(self):
        assert fires("Cable Glute Kickback", "hip", ["glutes"])

    def test_a_triceps_kickback_is_not(self):
        # "Dumbbell Kickback", primaryMuscles ["triceps"] -- one of five
        # triceps isolations hidden from hip-injured users.
        assert not fires("Dumbbell Kickback", "hip", ["triceps"])

    def test_a_donkey_calf_raise_is_an_ankle_contraindication(self):
        assert fires("Donkey Calf Raise", "ankle", ["calves"])

    def test_donkey_kicks_are_not(self):
        # Bare "donkey" swallowed a glute exercise that loads no ankle at all.
        assert not fires("Donkey Kicks Bodyweight", "ankle", ["glutes"])


class TestApplying:
    def test_it_is_additive_across_regions(self):
        rows = [row("Barbell Squat", ["quads"])]
        tagger.apply_tags(rows, "knee", tagger.tag(rows, "knee"))
        tagger.apply_tags(rows, "hip", tagger.tag(rows, "hip"))
        assert rows[0]["contraindications"] == ["hip", "knee"]

    def test_it_is_idempotent(self):
        rows = [row("Barbell Squat", ["quads"])]
        first = tagger.apply_tags(rows, "knee", tagger.tag(rows, "knee"))
        second = tagger.apply_tags(rows, "knee", tagger.tag(rows, "knee"))
        assert (first, second) == (1, 0)

    def test_it_never_touches_another_regions_tag(self):
        rows = [row("Barbell Squat", ["quads"], contraindications=["neck"])]
        tagger.apply_tags(rows, "knee", tagger.tag(rows, "knee"))
        assert "neck" in rows[0]["contraindications"]

    def test_an_untagged_row_is_left_without_the_key(self):
        # Writing `contraindications: []` onto every row would make "untagged"
        # and "checked and cleared" identical on disk, which is the distinction
        # the whole coverage number turns on.
        rows = [row("Seated Calf Machine", ["calves"])]
        tagger.apply_tags(rows, "knee", tagger.tag(rows, "knee"))
        assert "contraindications" not in rows[0]


class TestTheShippedCatalog:
    @pytest.fixture(scope="class")
    def rows(self):
        return json.loads(CATALOG.read_text(encoding="utf-8"))

    def test_every_written_tag_is_legal(self, rows):
        legal = set(tagger.load_vocabulary())
        stray = {
            tag
            for r in rows
            for tag in r.get("contraindications") or []
            if tag not in legal
        }
        assert stray == set()

    def test_tags_are_sorted_and_unique_per_row(self, rows):
        for r in rows:
            tags = r.get("contraindications") or []
            assert tags == sorted(set(tags)), r["id"]

    def test_the_batches_shipped_so_far(self, rows):
        # Mirrors the Dart ratchet in safety_coverage_test.dart. Two sides,
        # because the Python writer and the Dart reader can disagree and the
        # disagreement is silent by construction.
        counts = tagger.coverage(rows, tagger.load_vocabulary())
        assert counts == {
            "neck": 0,
            "shoulder": 486,
            "elbow": 0,
            "wrist": 0,
            "lower_back": 312,
            "hip": 0,
            "knee": 362,
            "ankle": 0,
        }

    def test_no_injury_hides_most_of_the_catalog(self, rows):
        # The other direction of failure. An injured user shown almost nothing
        # has been failed by the product that claims to be for them.
        counts = tagger.coverage(rows, tagger.load_vocabulary())
        for region, hidden in counts.items():
            assert hidden / len(rows) < 0.45, f"{region} hides {hidden}"

    def test_three_injuries_at_once_still_leave_a_usable_catalog(self, rows):
        # Regions compose by union, so the interesting number is not any one
        # of them. Knee + shoulder + lower back -- a plausible list for an
        # older lifter -- currently hides 56% and leaves 826 exercises. If a
        # later batch pushes that past 75% the product has stopped being
        # useful to exactly the people it is for, and that is a decision to
        # make deliberately rather than to discover.
        worst = {"knee", "shoulder", "lower_back"}
        hidden = sum(
            1 for r in rows if worst & set(r.get("contraindications") or [])
        )
        assert hidden / len(rows) < 0.75, f"{hidden} of {len(rows)} hidden"
