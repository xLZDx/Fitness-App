# -*- coding: utf-8 -*-
"""Tag exercises with the injury regions they load.

WHAT A TAG MEANS

`contraindications: ["knee"]` means: someone who told us their knee is injured
should not be shown this exercise. It is read by `isContraindicated`
(`exercise_filter.dart`), which compares it against `InjuryRegion.tag` exactly.
The legal set is `injury_regions.json`, projected from the Dart enum.

WHAT THIS IS, AND WHAT IT IS NOT

Deterministic rules over the vendor's own metadata: the movement name, the
muscles they list as primary, the equipment label, and the instruction steps.
Every tag carries the rule that produced it and the token it matched, written
to a CSV twin, so a reviewer can disagree with a specific row rather than with
the pass as a whole.

It is NOT a clinical review. Nobody with a licence has looked at these, and the
app must not say otherwise -- see `safetyReviewedByRules` in the ARB, which is
the disclosure that replaces S0a's banner rather than removing it.

DIRECTION OF ERROR

A false positive hides a safe exercise; a false negative shows a dangerous one.
Those are not symmetric, so the rules lean toward tagging. They do not lean all
the way: an injured user who is shown almost nothing has been failed too, and
by the product that claims to be for them specifically. The hide-rate per
region is printed on every run and belongs in the batch's commit message.

Usage:
    python scripts/catalog/tag_contraindications.py --region knee
    python scripts/catalog/tag_contraindications.py --region knee --write
    python scripts/catalog/tag_contraindications.py --report
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import vendor_paths  # noqa: E402  (imported for the shared ROOT convention)

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
VOCAB = Path(__file__).with_name("injury_regions.json")
AUDIT_DIR = ROOT / "core" / "contraindications"


def load_vocabulary() -> list[str]:
    return json.loads(VOCAB.read_text(encoding="utf-8"))["tags"]


def normalise(text: str) -> str:
    """Lowercase, and every non-alphanumeric run becomes one space.

    Applied to the rule's words and to the text alike, so `push-up` and
    `push up` are the same phrase however the vendor spelled it.

    This is not cosmetic. The first version matched raw text with `\\b`
    boundaries and produced a whole class of false negatives that a spot-check
    of the audit trail caught immediately: `\\bsquat\\b` misses "Barbell Front
    Squats", and `\\bleg curl\\b` misses "LEG Curl_single Leg", because an
    underscore is a word character to `\\b` and so the word never ends. Four of
    the twelve untagged Legs rows sampled were knee-loading movements missed
    for spelling alone, and a missed contraindication is the direction of error
    that hurts someone.
    """
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


class Rule:
    """One reason an exercise loads a region.

    `words` are matched as whole words against the movement's name and steps.
    `muscles`, when given, must intersect the vendor's `primaryMuscles` -- that
    is what stops "leg press" logic from firing on "shoulder press" because
    both contain "press".
    """

    def __init__(
        self,
        name: str,
        words: list[str],
        muscles: list[str] | None = None,
        fields: tuple[str, ...] = ("title",),
    ) -> None:
        self.name = name
        self.words = words
        self.muscles = set(muscles or [])
        self.fields = fields
        # No pattern for a `["*"]` rule, and that is a guard rather than an
        # optimisation. `normalise("*")` is the empty string, so the first
        # draft compiled `\b()(s|es)?\b` for those rules -- a nonsensical
        # pattern that was harmless only because `classify` intercepts `["*"]`
        # before it can reach `match`. Any future caller reaching for
        # `rule.match(row)` directly would have got that empty alternation
        # instead of the muscle check `classify` performs, silently and with a
        # different answer. `None` turns that into a `TypeError` at the first
        # call.
        #
        # `re.escape` is a no-op today -- `normalise` has already reduced every
        # word to `[a-z0-9 ]` before it runs, so no metacharacter can survive
        # to reach it. It is here for the word list that eventually skips
        # `normalise`, not for this one.
        self._pattern = (
            None
            if words == ["*"]
            else re.compile(
                r"\b("
                + "|".join(re.escape(normalise(w)) for w in words)
                + r")(s|es)?\b"
            )
        )

    def known(self, row: dict) -> set[str]:
        """The muscles we know about, or every muscle when we know none.

        The vendor's sheet is ~79% filled: 451 of 1,887 rows carry no
        `primaryMuscles` at all and 182 carry neither list. A muscle gate reads
        those as "does not intersect" and silently refuses to fire, so a
        muscle-gated rule could never tag any of them -- under-tagging, which
        is the direction of error that hurts someone.

        Unknown is not the same as excluded. When the vendor tells us nothing,
        the gate stands down and the word match decides alone; `muscles` is
        used as the fallback before giving up entirely, because a secondary
        list is still evidence. Caught by a spot-check of the shoulder batch:
        "Cable Face Pull with Rope" and "Kettlebell Rear Delt Row" match
        `shoulder_abduction`'s words exactly and were being dropped for having
        no muscle metadata.
        """
        primary = set(row.get("primaryMuscles") or [])
        if primary:
            return primary
        secondary = set(row.get("muscles") or [])
        if secondary:
            return secondary
        return set(self.muscles)

    def match(self, row: dict) -> str | None:
        if self._pattern is None:
            raise ValueError(
                f"{self.name} is a ['*'] rule: its muscle list is the whole "
                "test and there is no word to match. Call classify(), which "
                "knows the difference."
            )
        if self.muscles and not self.muscles.intersection(self.known(row)):
            return None
        for field in self.fields:
            value = row.get(field)
            text = " ".join(value) if isinstance(value, list) else (value or "")
            found = self._pattern.search(normalise(text))
            if found:
                return found.group(0)
        return None


# Rules are grouped by the region they tag. Each names the mechanism it stands
# for, because "knee_deep_flexion" is reviewable and "knee_rule_3" is not.
RULES: dict[str, list[Rule]] = {
    "knee": [
        Rule(
            "knee_loaded_flexion",
            ["squat", "lunge", "step-up", "step up", "leg press", "hack",
             "sissy", "pistol", "split squat", "wall sit", "bulgarian"],
        ),
        Rule("knee_isolation", ["leg extension", "leg curl", "knee extension"]),
        Rule(
            "knee_impact",
            # Gerunds are spelled out. The `(s|es)?` suffix cannot reach
            # "running" from "run" -- the n doubles -- and the catalog ships
            # "Running", "Jogging" and "Treadmill Running" with quads,
            # hamstrings and calves as primary muscles.
            ["jump", "jumping", "hop", "bound", "skater", "burpee", "sprint",
             "sprinting", "run", "running", "jog", "jogging", "plyo",
             "box jump", "tuck jump", "jack", "stair", "shuttle"],
        ),
        Rule(
            "knee_kneeling",
            ["kneeling", "kneel"],
        ),
        Rule(
            "knee_quad_dominant",
            ["squat", "lunge", "press", "extension", "step"],
            muscles=["quads"],
        ),
    ],
    "lower_back": [
        Rule(
            "lumbar_hinge",
            ["deadlift", "good morning", "hinge", "romanian", "rdl",
             "swing", "clean", "snatch", "high pull"],
        ),
        Rule(
            "lumbar_axial_load",
            ["back squat", "front squat", "overhead squat", "zercher",
             "barbell squat", "farmer", "yoke", "shrug"],
        ),
        Rule(
            "lumbar_spinal_flexion",
            ["sit-up", "sit up", "crunch", "v-up", "v up", "toe touch",
             "jackknife", "roll-up", "roll up"],
        ),
        Rule(
            "lumbar_extension",
            ["hyperextension", "back extension", "superman", "cobra",
             "bird dog", "good morning"],
        ),
        Rule(
            "lumbar_bent_over",
            ["bent-over", "bent over", "pendlay", "t-bar", "t bar"],
        ),
        Rule("lumbar_primary", ["*"], muscles=["lower_back"], fields=("title",)),
    ],
    "shoulder": [
        Rule(
            "shoulder_overhead",
            ["overhead", "military", "shoulder press", "push press", "jerk",
             "handstand", "snatch", "arnold", "pike"],
        ),
        Rule(
            "shoulder_abduction",
            # "external rotation" and "internal rotation" are deliberately
            # absent: rotator-cuff work is what a shoulder injury is usually
            # prescribed, and hiding it would take away the one thing that
            # helps.
            ["lateral raise", "front raise", "upright row", "raise", "fly",
             "flye", "reverse fly", "rear delt", "face pull"],
            muscles=["shoulders", "traps", "chest"],
        ),
        Rule(
            "shoulder_pressing",
            ["bench press", "push-up", "push up", "dip", "chest press",
             "incline press", "decline press", "press"],
            muscles=["chest", "shoulders", "triceps"],
        ),
        Rule(
            "shoulder_overhead_pull",
            ["pull-up", "pull up", "chin-up", "chin up", "lat pulldown",
             "pulldown", "pullover"],
        ),
    ],
    "hip": [
        Rule(
            "hip_deep_flexion",
            ["squat", "lunge", "step-up", "step up", "leg press", "pistol",
             "bulgarian", "split squat", "sumo"],
        ),
        Rule(
            "hip_extension_load",
            ["hip thrust", "glute bridge", "bridge", "deadlift", "romanian",
             "hip extension", "good morning"],
        ),
        Rule(
            # "Dumbbell Kickback" is triceps (primaryMuscles ["triceps"]).
            # Ungated, this hid five triceps isolations from hip-injured users.
            "hip_glute_kickback",
            ["kickback", "kick back", "donkey kick"],
            muscles=["glutes", "hamstrings"],
        ),
        Rule(
            "hip_abduction",
            ["abduction", "adduction", "clamshell", "fire hydrant",
             "side-lying", "side lying", "monster walk", "banded walk"],
        ),
        Rule(
            "hip_open_stretch",
            ["pigeon", "butterfly", "frog", "straddle", "lizard", "splits",
             "happy baby", "figure four", "90/90"],
        ),
        Rule("hip_glute_dominant", ["thrust", "bridge", "kick", "raise", "swing"],
             muscles=["glutes"]),
    ],
    "ankle": [
        Rule(
            "ankle_impact",
            ["jump", "jumping", "hop", "bound", "skater", "burpee", "sprint",
             "sprinting", "run", "running", "jog", "jogging", "plyo",
             "box jump", "tuck jump", "jack", "stair", "shuttle"],
        ),
        Rule(
            "ankle_plantarflexion",
            ["calf raise", "calf", "toe raise", "heel raise", "tibialis",
             "donkey calf"],
        ),
        Rule(
            "ankle_deep_dorsiflexion",
            ["deep squat", "pistol", "sissy", "ass to grass", "squat"],
            muscles=["quads", "glutes", "calves"],
        ),
    ],
    "wrist": [
        Rule(
            "wrist_weight_bearing",
            ["push-up", "push up", "plank", "handstand", "burpee",
             "mountain climber", "bear crawl", "dip", "crab", "downward dog",
             "table top", "tabletop"],
        ),
        Rule(
            # Bare "grip" is gone. It matched 124 of this rule's 177 rows and
            # almost none of them were about the wrist: "Normal Grip", "Close
            # Grip", "Reverse Grip", "Suspension Trainer with Grips" -- a grip
            # VARIATION, which every barbell movement has. Tagging them made a
            # wrist injury hide 16.5% of the catalog for no reason a reviewer
            # could defend.
            "wrist_loaded_grip",
            ["wrist curl", "reverse curl", "farmer", "hang", "dead hang",
             "front rack", "clean", "snatch", "grip strength", "fat grip",
             "towel grip"],
        ),
        Rule("wrist_forearm_primary", ["curl", "extension", "rotation", "twist"],
             muscles=["forearms"]),
    ],
    "elbow": [
        Rule(
            "elbow_flexion_load",
            ["chin-up", "chin up", "pull-up", "pull up"],
        ),
        Rule(
            # Gated on the muscles that make it an ARM curl. Ungated, this
            # tagged "Alternating Hamstring Curl" (primaryMuscles
            # ["hamstrings"]) as an elbow contraindication -- a leg machine
            # hidden from someone with a sore elbow.
            "elbow_curl_load",
            ["curl", "hammer", "preacher", "concentration"],
            muscles=["biceps", "forearms"],
        ),
        Rule(
            "elbow_extension_load",
            ["triceps", "tricep", "skull", "kickback", "pushdown",
             "close-grip", "close grip", "dip", "overhead extension",
             "french press"],
        ),
        Rule(
            "elbow_locked_support",
            ["push-up", "push up", "plank", "handstand", "bear crawl",
             "table top", "tabletop"],
        ),
    ],
    # P3. The ninth region, and the last to get rules -- it shipped with zero
    # tags while the other eight carried 117..816, which made it the one zone
    # on the body diagram that could be selected and then screened nothing.
    #
    # Thoracic spine and scapula, which is a different question from `neck`
    # (an overhead press is a neck question, a bent-over row is a thoracic
    # one -- `profile_models.dart` makes the same distinction and refuses to
    # merge the two). Where they genuinely overlap -- a loaded shrug is both
    # -- both rules fire, which is correct: the tags are independent and a
    # user reports one region or the other, not a winner between them.
    "upper_back": [
        Rule(
            # FIRST on purpose, ahead of `thoracic_horizontal_pull`. All nine
            # "Upright Row" rows contain the generic word "row", so with the
            # pull rule first they were tagged correctly but recorded in the
            # audit trail as horizontal pulling. The tag was right and the
            # stated reason was wrong, which is the one thing a per-row audit
            # trail exists to prevent.
            #
            # UNGATED, unlike its neck twin, and the first draft's gate is why
            # this comment exists. Gated on `muscles=["traps","back"]` it
            # silently dropped 9 of the catalog's 25 shrugs -- every one with
            # an empty `primaryMuscles` and the generic secondary
            # `muscles: ["shoulders"]`, which `known()` hands to the gate as
            # real evidence that then fails to intersect. The same "Silverback
            # Shrug" movement fired for its barbell and cable variants and not
            # for its dumbbell and kettlebell ones, decided by nothing but
            # which body-region word the vendor happened to type.
            #
            # The gate was never earning anything here: unlike "press" or
            # "curl", none of these words names a second movement in another
            # part of the body. A shrug is a shrug.
            "thoracic_trap_load",
            ["shrug", "upright row", "farmer", "farmers walk", "rack pull"],
        ),
        Rule(
            # The core of it. Horizontal pulling is scapular retraction under
            # load, which is exactly what a rhomboid or mid-trap strain will
            # not tolerate.
            "thoracic_horizontal_pull",
            # "band pull" is deliberately absent. It was in the first draft and
            # the dry run caught it doing the opposite of what this ruleset
            # says: it matched "Band Pull Up" (primaryMuscles `lats`) — a
            # pull-up, which the `thoracic_trap_primary` note below explicitly
            # rules out — while the pull-apart it was meant for is already
            # caught by "pull apart" on its own.
            #
            # "rear deltoid fly", "rowing" and "scapula retraction" are spelled
            # out next to their shorter cousins because `\b(word)(s|es)?\b`
            # will not reach them: "rear delt" stops at a boundary "rear
            # deltoid" does not have, "row" cannot reach "rowing" (the same
            # doubled-letter problem `knee_impact` documents for
            # "run"/"running"), and "scap retraction" is not the spelling the
            # catalog uses. Six unambiguous rows were missed for spelling
            # alone -- three "Gym Rowing Machine", two "Rear Deltoid Fly", one
            # "Theraband Scapula Retraction".
            #
            # "rear deltoid fly", not the bare "rear deltoid" the first draft
            # used. Bare, it also caught "Rear Deltoid Stretch" -- a passive
            # cross-body hold, filed under a rule named for scapular retraction
            # under load, which is not what a stretch does and not what the
            # audit trail is supposed to claim about it. Both real rows this
            # token exists for carry "Fly" in their own titles
            # ("Rear Deltoid Fly Cable Resistance Band", "Bent Over Rear
            # Deltoid Fly Resistance Band"); the stretch does not.
            ["row", "rowing", "face pull", "rear delt", "rear deltoid fly",
             "reverse fly", "reverse flye", "pull apart", "scapular",
             "scap retraction", "scapula retraction", "seal row", "pendlay"],
        ),
        Rule(
            # A bar resting across the upper traps and rear delts, or a load
            # held with the thoracic spine braced against it.
            "thoracic_axial_load",
            ["back squat", "front squat", "overhead squat", "zercher",
             "good morning", "yoke", "safety bar"],
        ),
        Rule(
            # Read from the STEPS, not the title, and that is the whole point.
            #
            # `thoracic_axial_load` above lists movement names, and a list of
            # names only covers the names somebody thought of. It missed
            # "Barbell Low Bar Squat", "Barbell Box Squat" and "Barbell Split
            # Squat" — every one of them a bar resting across the upper back,
            # which is the exact mechanism that rule's own comment claims to
            # cover. Naming more squats would have moved the boundary without
            # removing it.
            #
            # The vendor writes the mechanism down in the instructions: the bar
            # goes "across your upper back", "on your traps", "behind your
            # neck". That sentence is the evidence, and it is the same for a
            # squat, a lunge, a step-up and a good morning, whatever the row is
            # called. Placed AFTER the horizontal-pull rule so that a row whose
            # steps say "squeeze your upper back" is still recorded as pulling.
            # The phrases carry their preposition, and that is load-bearing. A
            # bare "upper back" token was the first draft and it tagged sit-ups
            # ("lift your upper back off the floor"), a hip thrust ("with your
            # upper back on the bench") and Puppy Pose — all of them mentioning
            # the region while putting no load on it. Measured across the
            # catalog's own instruction text: "across your upper back" appears
            # 45 times and is always a bar or an equivalent object resting on
            # the region; "lift/lower/with your upper back" is always
            # positioning. The preposition is what separates the two, so it
            # stays in the token.
            #
            # Named for the common case, not the only one. A rolled foam
            # cylinder ("Foam Roller Back": "a foam roller across your upper
            # back") and a weight plate held there by a partner
            # ("Assisted Weighted Push Up") are the same mechanism as a
            # barbell — a load in contact with the exact tissue — and match on
            # the same "across/on your upper back" phrase. "Dragonfly" is the
            # same mechanism turned around: instead of an object resting on
            # the back, the whole body's weight rests on it. None of the three
            # is a first-draft leftover; each was read against its own `steps`
            # before this rule shipped and each is a real load on the region,
            # not a mention of it.
            #
            # "bar behind your neck" / "bar behind the neck" is a second
            # phrase, not a rephrasing of the first: the load stays in one
            # place while something ELSE moves around it, rather than the
            # spine moving under a fixed load. "Bent Over Twist" (a straight
            # bar held behind the neck through a torso rotation, the same
            # bar-as-brace mechanism as the already-tagged "Barbell Seated
            # Twist") and "Cable Assisted Inverse Leg Curl" (a cable bar held
            # behind the neck through a hip hinge) were missed for exactly this
            # reason -- their "across/on" phrases never fire because nothing is
            # described as resting ACROSS anything; the bar is held, not rested.
            "thoracic_bar_on_back",
            ["across your upper back", "across the upper back",
             "on your upper back", "on the upper back",
             "on your traps", "on the traps",
             "across your shoulders", "across the shoulders",
             "bar behind your neck", "bar behind the neck"],
            fields=("steps",),
        ),
        Rule(
            # Loaded thoracic extension. The lumbar-dominant ones
            # (hyperextension, superman) stay with `lower_back`; what is
            # listed here arches specifically through the mid-back.
            "thoracic_extension",
            ["cobra", "upward dog", "upward facing dog", "camel", "wheel pose",
             "backbend", "bow pose", "sphinx", "thread the needle"],
        ),
        Rule(
            # The muscle constraint IS the rule, same shape the `["*"]` form
            # exists for: the vendor naming traps as the primary mover is
            # direct evidence the movement loads this region, whatever it is
            # called.
            #
            # `lats` is not a reason on its own -- 118 rows carry it and most
            # are pulldowns and pull-ups, whose scapular load is real but whose
            # blanket removal would leave an upper-back user with almost no
            # back work at all. That is the "does not lean all the way" line in
            # this file's own header.
            #
            # It is NOT an exclusion, and the first draft of this comment said
            # it was, which was a promise the code does not keep: the test is
            # "does traps appear", not "does traps appear and lats not". One
            # row carries both -- `ea_cable_underhand_pulldown_wide_grips`,
            # `primaryMuscles: ["lats", "traps"]` -- and it is tagged, on the
            # strength of the traps. That is the intended reading; the wrong
            # half was the word "excluded".
            "thoracic_trap_primary",
            ["*"],
            muscles=["traps"],
        ),
    ],
    "neck": [
        Rule(
            "neck_flexion_load",
            ["sit-up", "sit up", "crunch", "v-up", "v up", "neck",
             "jackknife"],
        ),
        Rule(
            # "bridge" and "wheel" removed: 47 of this rule's 50 rows were
            # glute bridges and ab-wheel rollouts, where the neck rests on the
            # floor or stays neutral. The yoga poses they were meant to catch
            # are named explicitly instead.
            "neck_inversion",
            ["headstand", "handstand", "shoulder stand", "plough", "plow",
             "candlestick", "wheel pose", "bridge pose", "backbend"],
        ),
        Rule(
            "neck_trap_load",
            ["shrug", "upright row", "farmer", "yoke"],
            muscles=["traps", "shoulders"],
        ),
    ],
}


def unknown_regions() -> list[str]:
    """Rule keys that are not legal tags.

    `--region` offers `RULES` keys and `apply_tags` writes them verbatim, while
    every reader -- `isContraindicated`, `safetyCoverageByRegion`, the coverage
    report -- silently drops a tag it does not recognise. A renamed key would
    therefore ship into the catalog, filter nobody, and show up in no count and
    no test. This is the guard that was missing.
    """
    legal = set(load_vocabulary())
    return sorted(set(RULES) - legal)


def classify(row: dict, region: str) -> tuple[str, str] | None:
    """The first rule that fires for [region], and the token it matched.

    First-match rather than all-matches on purpose: the audit trail wants one
    reason per row that a human can agree or disagree with, and a row listing
    four overlapping reasons is harder to review, not easier.
    """
    for rule in RULES[region]:
        # `["*"]` means "the muscle constraint IS the rule" -- there is no word
        # to match, the vendor's own primaryMuscles is the whole evidence.
        #
        # `primaryMuscles` directly, NOT `Rule.known()`, and the asymmetry with
        # every word-matched rule is deliberate. `known()` exists to stop a
        # muscle gate from vetoing a word that already matched; it falls back
        # to the rule's own muscle set when the vendor filled in nothing, which
        # always intersects. For a `["*"]` rule there is no word to have
        # matched, so that same fallback would tag all 182 metadata-less rows
        # for every `["*"]` rule in the file. Even the milder half -- accepting
        # the secondary `muscles` list -- was measured before being rejected:
        # it adds 4 rows here ("Barbell Seated Military Press", "Dumbbell Lying
        # External Shoulder Rotation", "Barbell Pause Incline Bench Press",
        # "Backward Forward Turn to Side Neck Stretch") and 4 to
        # `lumbar_primary` (two glute bridges, a Russian twist, a hip stretch).
        # Three of those four presses and rotations name `traps` as a
        # secondary mover and load the upper back with nothing.
        #
        # A word match plus thin muscle evidence is a movement we recognise.
        # Thin muscle evidence alone is not evidence.
        if rule.words == ["*"]:
            if rule.muscles.intersection(row.get("primaryMuscles") or []):
                return rule.name, ",".join(sorted(rule.muscles))
            continue
        found = rule.match(row)
        if found:
            return rule.name, found
    return None


def tag(rows: list[dict], region: str) -> list[dict]:
    """Rows this pass would tag, with the evidence for each."""
    out = []
    for row in rows:
        verdict = classify(row, region)
        if verdict is None:
            continue
        rule, token = verdict
        out.append(
            {
                "id": row["id"],
                "title": row["title"],
                "region": region,
                "rule": rule,
                "matched": token,
                "primaryMuscles": ",".join(row.get("primaryMuscles") or []),
                "vendorGroup": row.get("vendorGroup", ""),
                "already": region in (row.get("contraindications") or []),
            }
        )
    return out


def write_audit(region: str, tagged: list[dict]) -> Path:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    path = AUDIT_DIR / f"{region}.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "id",
                "title",
                "region",
                "rule",
                "matched",
                "primaryMuscles",
                "vendorGroup",
                "already",
            ],
        )
        writer.writeheader()
        writer.writerows(tagged)
    return path


def apply_tags(rows: list[dict], region: str, tagged: list[dict]) -> int:
    """Add [region] to each tagged row. Returns how many rows changed.

    Additive and idempotent: a row already carrying the tag is left alone, and
    tags for other regions are never touched, so batches compose in any order.
    """
    wanted = {entry["id"] for entry in tagged}
    changed = 0
    for row in rows:
        if row["id"] not in wanted:
            continue
        current = list(row.get("contraindications") or [])
        if region in current:
            continue
        current.append(region)
        row["contraindications"] = sorted(current)
        changed += 1
    return changed


def retract_stale_tags(rows: list[dict], region: str, tagged: list[dict]) -> int:
    """Remove [region] from rows the current rules no longer classify there.

    `apply_tags` only ever adds, and that asymmetry is what let a real bug
    through: narrowing a word list to remove a false positive (`rear
    deltoid` -> `rear deltoid fly`, so `Rear Deltoid Stretch` stopped
    matching) silently left the OLD tag sitting in the catalog from a
    previous `--write`, because nothing had ever removed a tag before. The
    outcome test (`test_the_rules_still_produce_what_the_catalog_carries`)
    is what caught it — a mismatch between what the rules produce now and
    what the file carries, on the exact row this function exists to fix.

    Also additive in spirit, in that it never touches a tag this call's
    RULES did not put there: only a row carrying [region] that [tagged] does
    not name is touched, and only [region] is removed from it, so a batch
    for one region still cannot disturb another region's tags.
    """
    wanted = {entry["id"] for entry in tagged}
    changed = 0
    for row in rows:
        current = row.get("contraindications") or []
        if region not in current or row["id"] in wanted:
            continue
        row["contraindications"] = sorted(t for t in current if t != region)
        changed += 1
    return changed


def coverage(rows: list[dict], vocabulary: list[str]) -> dict[str, int]:
    counts = {tag_name: 0 for tag_name in vocabulary}
    for row in rows:
        for tag_name in row.get("contraindications") or []:
            if tag_name in counts:
                counts[tag_name] += 1
    return counts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", choices=sorted(RULES))
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--report", action="store_true", help="coverage only")
    args = ap.parse_args()

    rows = json.loads(CATALOG.read_text(encoding="utf-8"))
    vocabulary = load_vocabulary()
    stray = unknown_regions()
    if stray:
        raise SystemExit(
            "these rule keys are not in injury_regions.json and would be "
            "written as tags nothing can read: " + ", ".join(stray)
        )

    if args.report or not args.region:
        counts = coverage(rows, vocabulary)
        total = len(rows)
        tagged_rows = sum(1 for r in rows if r.get("contraindications"))
        print(f"catalog {total} rows, {tagged_rows} carry at least one tag")
        for name in vocabulary:
            hidden = counts[name]
            print(f"  {name:11s} {hidden:5d}  hides {hidden / total:5.1%}")
        return

    region = args.region
    tagged = tag(rows, region)
    fresh = [entry for entry in tagged if not entry["already"]]
    audit = write_audit(region, tagged)

    print(f"region {region}")
    print(f"  matches      {len(tagged)} of {len(rows)}  "
          f"({len(tagged) / len(rows):.1%} hidden for this injury)")
    print(f"  new this run {len(fresh)}")
    print(f"  audit        {audit.relative_to(ROOT)}")
    by_rule: dict[str, int] = {}
    for entry in tagged:
        by_rule[entry["rule"]] = by_rule.get(entry["rule"], 0) + 1
    for rule, count in sorted(by_rule.items(), key=lambda kv: -kv[1]):
        print(f"    {rule:28s} {count}")

    if args.write:
        added = apply_tags(rows, region, tagged)
        retracted = retract_stale_tags(rows, region, tagged)
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nwrote {added} rows into {CATALOG.relative_to(ROOT)}"
              + (f", retracted {retracted} stale" if retracted else ""))
        counts = coverage(rows, vocabulary)
        print("coverage now: " + ", ".join(
            f"{name} {counts[name]}" for name in vocabulary
        ))
    else:
        print("\nnothing written -- pass --write")


if __name__ == "__main__":
    main()
