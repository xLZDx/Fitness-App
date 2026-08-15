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

    def test_every_legal_region_has_rules(self):
        # The other direction, and the one that was missing. `unknown_regions`
        # catches a rule key that is not a legal tag; nothing caught a legal tag
        # with no rules. That is exactly how `upper_back` shipped: added to
        # `injury_regions.json` and to the body diagram on 2026-08-12, offered
        # to users as a selectable zone, and screening nothing at all for three
        # months of gates because no rule key ever named it.
        #
        # A region with no rules cannot be tagged, so it can never be filtered,
        # and the failure is silent by construction -- the count is a truthful
        # zero and no assertion anywhere reads a zero as wrong.
        # Checked on the VALUE, not just the key. `set(RULES)` alone would pass
        # for `RULES["some_region"] = []` -- a stub left behind while rules are
        # drafted -- and `classify` would then loop over zero rules and tag zero
        # rows, which is the identical silent zero this test exists to catch.
        missing = sorted(
            r for r in tagger.load_vocabulary() if not tagger.RULES.get(r)
        )
        assert missing == [], (
            "these regions are offered to users but no rule can tag them, so "
            "they screen nothing: " + ", ".join(missing)
        )

    def test_the_guard_would_catch_a_region_stubbed_with_no_rules(
        self, monkeypatch
    ):
        # The empty-list case specifically, since it is the one a key-only
        # check misses and the one a half-finished batch actually produces.
        monkeypatch.setitem(tagger.RULES, "knee", [])
        with pytest.raises(AssertionError, match="knee"):
            self.test_every_legal_region_has_rules()


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


class TestTheMuscleOnlyRules:
    """`["*"]` rules, where the muscle list is the whole of the evidence."""

    def test_a_primary_trap_mover_is_an_upper_back_contraindication(self):
        assert fires("Some Movement Nobody Named A Rule After", "upper_back",
                     ["traps"])

    def test_a_secondary_trap_mention_alone_is_not(self):
        # The asymmetry with every word-matched rule, pinned so it cannot be
        # "tidied up" into consistency later. `Rule.known()` accepts a
        # secondary list, and routing `["*"]` rules through it reads like the
        # obvious cleanup -- it is not. It would tag "Barbell Seated Military
        # Press" and "Dumbbell Lying External Shoulder Rotation" as upper-back
        # contraindications on the strength of a secondary `traps` mention,
        # and neither loads the upper back. A word match plus thin muscle
        # evidence is a movement we recognise; thin evidence alone is not.
        # `row()`'s own `muscles` kwarg fills `primaryMuscles`, which is
        # exactly the field this test needs to be EMPTY -- the first draft
        # passed `muscles=[...]` there and the row it built had no secondary
        # list at all, so the assertion held for the wrong reason: there was
        # no evidence to admit, not evidence correctly excluded. Built by hand
        # instead, secondary-only, the way `Rule.known()` actually receives it.
        r = row("Barbell Seated Military Press")
        r["muscles"] = ["shoulders", "traps"]
        assert r["primaryMuscles"] == []
        assert tagger.classify(r, "upper_back") is None

    def test_a_star_rule_compiles_no_pattern(self):
        # `normalise("*")` is empty, so compiling one yields `\\b()(s|es)?\\b`
        # -- a pattern that matches at every word boundary. It was harmless
        # only because `classify` never reaches `match` for these rules, which
        # is a guarantee about one call site, not about the class.
        star = [
            rule
            for rules in tagger.RULES.values()
            for rule in rules
            if rule.words == ["*"]
        ]
        assert star, "the case this test pins no longer exists"
        for rule in star:
            assert rule._pattern is None, rule.name
            with pytest.raises(ValueError, match="classify"):
                rule.match(row("anything at all"))

    def test_a_regex_metacharacter_in_a_word_is_a_literal(self):
        # `normalise` strips metacharacters before `re.escape` can ever see
        # one, so this passes either way today. It fails the day a word list
        # reaches the pattern without `normalise` -- which is the only reason
        # `re.escape` is in the constructor at all.
        rule = tagger.Rule("literal", ["a+b"])
        assert rule.match(row("Machine A+B Press")) is not None
        assert rule.match(row("Machine AAB Press")) is None


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


class TestRetractingStaleTags:
    """`apply_tags` only ever adds. This is the half that removes.

    Found live, not designed up front: narrowing `upper_back`'s "rear
    deltoid" token to "rear deltoid fly" (P3-fix) stopped matching "Rear
    Deltoid Stretch", and the tag that a PREVIOUS `--write` had put on that
    row simply stayed in the catalog -- nothing had ever taken a tag away
    before. `test_the_rules_still_produce_what_the_catalog_carries` is what
    caught it, by comparing exact ID sets rather than counts.
    """

    def test_a_tag_the_current_rules_no_longer_produce_is_removed(self):
        rows = [row("Rear Deltoid Stretch", contraindications=["upper_back"])]
        changed = tagger.retract_stale_tags(rows, "upper_back", tagger.tag(
            rows, "upper_back"
        ))
        assert changed == 1
        assert "upper_back" not in rows[0]["contraindications"]

    def test_a_tag_the_current_rules_still_produce_is_left_alone(self):
        rows = [row("Cable Face Pull", contraindications=["upper_back"])]
        changed = tagger.retract_stale_tags(rows, "upper_back", tagger.tag(
            rows, "upper_back"
        ))
        assert changed == 0
        assert rows[0]["contraindications"] == ["upper_back"]

    def test_it_never_touches_another_regions_tag(self):
        rows = [row("Rear Deltoid Stretch",
                     contraindications=["neck", "upper_back"])]
        tagger.retract_stale_tags(rows, "upper_back", tagger.tag(
            rows, "upper_back"
        ))
        assert rows[0]["contraindications"] == ["neck"]

    def test_an_emptied_row_is_left_without_the_key_style_list(self):
        # Not the same guarantee `test_an_untagged_row_is_left_without_the_key`
        # pins -- this row DID carry the key, and it keeps carrying it, empty,
        # once the last tag is gone. That is `apply_tags`'s own choice
        # (`current.append` always leaves the key even from `[]`), reused here
        # rather than special-cased.
        rows = [row("Rear Deltoid Stretch", contraindications=["upper_back"])]
        tagger.retract_stale_tags(rows, "upper_back", tagger.tag(
            rows, "upper_back"
        ))
        assert rows[0]["contraindications"] == []


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

    def test_the_rules_still_produce_what_the_catalog_carries(self, rows):
        # The outcome check, and the only one of the three guards in this file
        # that a rule going inert cannot walk past. `unknown_regions` compares
        # names. `test_every_legal_region_has_rules` compares a list length --
        # replacing `RULES["upper_back"]` with a single rule matching nothing
        # leaves it green, because one is not zero. Both are structural, and a
        # ruleset is not a structure, it is a result.
        #
        # This one re-derives every region from the live rules against the
        # shipped catalog and demands the committed artifact back, exactly.
        # A rule silently stops matching -> red. Someone hand-edits a tag into
        # the JSON -> red. A word list gains a token and nobody regenerates ->
        # red.
        #
        # Compared by the exact set of ROW IDS, not by count. A count is what
        # the first draft of this test compared, and a count cannot see one
        # row swapped for another: drop a real match and pick up an unrelated
        # false one and the total holds even though the rules no longer
        # reproduce the artifact for a single row of it. `test_the_batches_
        # shipped_so_far` below pins the same numbers from the artifact's
        # side and would stay green through all of this, because it never
        # runs a rule.
        for region in tagger.load_vocabulary():
            committed_ids = {
                r["id"] for r in rows if region in (r.get("contraindications") or [])
            }
            live_ids = {entry["id"] for entry in tagger.tag(rows, region)}
            assert live_ids == committed_ids, (
                f"{region}: the rules no longer reproduce the shipped tags -- "
                f"missing {sorted(committed_ids - live_ids)[:5]}, "
                f"extra {sorted(live_ids - committed_ids)[:5]}. Regenerate with "
                "`python scripts/catalog/tag_contraindications.py --region "
                f"{region} --write` and update both ratchets, or find out what "
                "stopped matching"
            )
        assert all(
            any(region in (r.get("contraindications") or []) for r in rows)
            for region in tagger.load_vocabulary()
        ), "a region tags nothing at all"

    def test_an_inert_ruleset_turns_the_outcome_check_red(
        self, rows, monkeypatch
    ):
        # The mutation, kept rather than performed once and described in a
        # commit message. Swap the whole `upper_back` ruleset for one rule that
        # matches nothing: the list is still non-empty, so
        # `test_every_legal_region_has_rules` stays green, and the shipped
        # artifact is untouched, so `test_the_batches_shipped_so_far` stays
        # green too. Only the outcome check notices.
        monkeypatch.setitem(
            tagger.RULES,
            "upper_back",
            [tagger.Rule("inert", ["zzzz nonexistent movement"])],
        )
        assert tagger.RULES["upper_back"], "the mutation must stay non-empty"
        with pytest.raises(AssertionError, match="no longer reproduce"):
            self.test_the_rules_still_produce_what_the_catalog_carries(rows)

    def test_the_batches_shipped_so_far(self, rows):
        # Mirrors the Dart ratchet in safety_coverage_test.dart. Two sides,
        # because the Python writer and the Dart reader can disagree and the
        # disagreement is silent by construction.
        counts = tagger.coverage(rows, tagger.load_vocabulary())
        assert counts == {
            "neck": 117,
            # 0 -> 264 -> 265 (P3, then the Codex round-2 fix). The region
            # joined the vocabulary on 2026-08-12 and stayed at zero because
            # `RULES` had no key for it -- the one guard in this file ran the
            # other way round (rule keys that are not legal tags), so a legal
            # tag with no rules was invisible to it. That gap is now closed by
            # `test_every_legal_region_has_rules`. The second move added a
            # "bar behind your neck" phrase (+2: `Bent Over Twist`, `Cable
            # Assisted Inverse Leg Curl`) and narrowed "rear deltoid" to "rear
            # deltoid fly" so it stopped catching a stretch (-1:
            # `Rear Deltoid Stretch`, retracted by `retract_stale_tags` rather
            # than left stale in the catalog).
            "upper_back": 265,
            # 486 -> 487 (full-catalog content audit, 2026-08-15). No rule
            # changed. `Dumbbell Face Down Lying Shoulder Pres` had shipped
            # with that typo in its title, so the `shoulder_overhead` rule
            # never matched its "shoulder press" phrase and the row was never
            # screened for a shoulder injury. Correcting the spelling as part
            # of the copy audit made the existing rule match it, and
            # `--region shoulder --write` tagged it. A tag gained by fixing a
            # typo is worth noting: the rules can only be as good as the text
            # they read, and a misspelt title fails open.
            # 487 -> 489 (Gate E, 2026-08-15). New `shoulder_loaded_arm_balance`
            # rule, +2: `Crow Pose`, `Wild Thing Pose`. Both are `advanced` and
            # both were carrying NO tags in any region -- an arm balance holds
            # bodyweight on a supporting shoulder, which no existing rule stood
            # for: `shoulder_overhead` is the pressing mechanism and its words
            # do not appear in either title. Kept as its own rule rather than
            # folded into `shoulder_overhead` so a reviewer can drop these two
            # rows without touching the 487 the pressing rules carry.
            "shoulder": 489,
            "elbow": 371,
            # 188 -> 190 (Gate E, 2026-08-15). Same two rows, same reason:
            # "crow" and "wild thing" added to `wrist_weight_bearing`, whose
            # mechanism (bodyweight through an extended wrist) already covered
            # handstand, plank and bear crawl and simply had no word that
            # reached these two titles.
            "wrist": 190,
            # 312 -> 313 (Gate E, 2026-08-15). "wild thing" added to
            # `lumbar_extension`: the pose lifts the hips and opens the front of
            # the body from a side plank, which is spinal extension under
            # bodyweight -- the same mechanism as cobra, entered from the side.
            # Crow is deliberately NOT here: it rounds rather than extends.
            "lower_back": 313,
            "hip": 404,
            "knee": 362,
            "ankle": 229,
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

    def test_every_injury_at_once_still_leaves_something(self, rows):
        # The floor of the product. Someone reporting all eight regions sees
        # 452 exercises -- 76% hidden. Recorded rather than asserted loosely:
        # the number is high, it is the honest consequence of tagging every
        # region, and the alternative (tag less) means showing an injured user
        # something that hurts. If a later pass takes this past 85% the answer
        # is not to loosen the threshold.
        hidden = sum(1 for r in rows if r.get("contraindications"))
        assert hidden / len(rows) < 0.85, f"{hidden} of {len(rows)} hidden"
        assert len(rows) - hidden > 300, "too little left to train with"
