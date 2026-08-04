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
        self._pattern = re.compile(
            r"\b(" + "|".join(normalise(w) for w in words) + r")(s|es)?\b"
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
            "wrist_loaded_grip",
            ["wrist curl", "reverse curl", "farmer", "grip", "hang",
             "dead hang", "front rack", "clean", "snatch"],
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
    "neck": [
        Rule(
            "neck_flexion_load",
            ["sit-up", "sit up", "crunch", "v-up", "v up", "neck",
             "jackknife"],
        ),
        Rule(
            "neck_inversion",
            ["headstand", "handstand", "shoulder stand", "plough", "plow",
             "bridge", "wheel", "candlestick"],
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
        changed = apply_tags(rows, region, tagged)
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nwrote {changed} rows into {CATALOG.relative_to(ROOT)}")
        counts = coverage(rows, vocabulary)
        print("coverage now: " + ", ".join(
            f"{name} {counts[name]}" for name in vocabulary
        ))
    else:
        print("\nnothing written -- pass --write")


if __name__ == "__main__":
    main()
