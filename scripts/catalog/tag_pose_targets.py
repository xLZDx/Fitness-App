# -*- coding: utf-8 -*-
"""Tag exercises with the movement pattern the Form Coach could judge.

WHAT A TAG MEANS

`poseTargetId: "squat"` means: this row's silhouette, seen from the side, is
the squat pattern. It does NOT mean the coach can judge it today. Whether a
pattern has hand-authored joint coordinates is a fact about the app, not about
the catalog, and it lives in `pose_target.dart` -- which is why the button is
gated on that and not on this field.

The separation is the whole point of the pass. Tagging is done once for all
1,887 rows; authoring is done once per pattern. The day a pattern's targets are
written, roughly a hundred exercises light up at the same moment with no
catalog work at all.

WHY PATTERNS AND NOT EXERCISES

A back squat, a front squat, a goblet squat, an air squat and a box squat are
one shape from the side. `poseMatchScore` removes position and overall size
before comparing, so what distinguishes them -- the load and where it sits --
is not in the signal at all. One target serves all of them.

WHAT IS DELIBERATELY NOT TAGGED

Anything a single side-on camera cannot see: seated and lying work, machines,
benches and cables that hide the hip line. The exclusions are one shared list
rather than per-pattern, because the reason is always the same. A bench press
is the clearest case and it is the operator's own example: supine, with a bench
across the hip line, and BlazePose has no spinal landmark to begin with.

DIRECTION OF ERROR

The opposite of the contraindications pass. There a false negative shows a
dangerous exercise; here a false positive merely offers a coach that scores
poorly, and the user can ignore it. So these rules do not lean toward tagging:
an untagged exercise loses a feature, a wrongly tagged one teaches the user
that the coach is unreliable, and the second costs more.

CHANGING A RULE

The counts this prints say how many rows carry each pattern. They do not say
WHICH rows changed, and a rule edit is judged on exactly that: an unexpected id
in either direction means the rule is wrong, not that the number needs
adjusting. So state the expected set first, in a file, and let `--expect` fail
if reality disagrees:

    python scripts/catalog/tag_pose_targets.py --transitions
    python scripts/catalog/tag_pose_targets.py --expect core/pose_targets/EXPECTED.tsv

`--expect` compares full (id, old, new) triples, not ids and not counts, and
exits non-zero naming what is MISSING and what is SURPLUS. Neither flag writes.

Usage:
    python scripts/catalog/tag_pose_targets.py
    python scripts/catalog/tag_pose_targets.py --write
    python scripts/catalog/tag_pose_targets.py --pattern squat
    python scripts/catalog/tag_pose_targets.py --transitions
    python scripts/catalog/tag_pose_targets.py --expect <file.tsv>
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
VOCAB = Path(__file__).with_name("pose_patterns.json")
AUDIT = ROOT / "core" / "pose_targets"

FIELD = "poseTargetId"


def load_vocab() -> tuple[list[dict], re.Pattern, re.Pattern]:
    v = json.loads(VOCAB.read_text("utf-8"))
    ex = v["excludeWhen"]
    return (
        v["patterns"],
        re.compile(ex["title"], re.I),
        re.compile(ex["equipmentLabel"], re.I),
    )


def classify(row: dict, patterns, ex_title, ex_equipment) -> tuple[str | None, str]:
    """Returns (pattern id or None, the reason).

    The reason travels into the CSV twin so a reviewer can disagree with one
    row rather than with the pass -- the same contract `tag_contraindications`
    established, and for the same reason: a tagging pass nobody can audit is a
    tagging pass nobody can correct.
    """
    title = row.get("title") or ""
    equipment = row.get("equipmentLabel") or ""

    hits = [
        p for p in patterns
        if re.search(p["matchTitle"], title, re.I)
        and not (p.get("notTitle") and re.search(p["notTitle"], title, re.I))
    ]
    if not hits:
        return None, "no pattern in the title"
    if len(hits) > 1:
        # Ambiguous by construction, e.g. "Squat to Overhead Press". Two
        # silhouettes in one movement is not something a single target can
        # score, and guessing which half the user is in is worse than saying
        # nothing.
        return None, "matches more than one pattern: " + ",".join(
            p["id"] for p in hits
        )

    if ex_title.search(title):
        return None, f"excluded by title: {ex_title.search(title).group(0)}"
    if equipment and ex_equipment.search(equipment):
        return None, f"excluded by equipment: {equipment}"

    return hits[0]["id"], "title match"


def read_expected(path: Path) -> set[tuple[str, str | None, str | None]]:
    """The sealed transition set: `id<TAB>old<TAB>new`, `-` for an absent tag.

    Any further columns are the author's own notes and are ignored -- the
    comparison is over the triple, because a set that matched on ids alone
    would accept a row moving to the WRONG new tag, and one that matched on
    counts would accept any 86 changes at all.

    A duplicate id is an error rather than a last-one-wins: the file exists to
    be exhaustive, and a repeated id means it was assembled by hand from two
    lists that disagree.
    """
    out: set[tuple[str, str | None, str | None]] = set()
    seen: set[str] = set()
    for n, line in enumerate(path.read_text("utf-8").splitlines(), 1):
        if not line.strip():
            continue
        cells = line.split("\t")
        if len(cells) < 3:
            sys.exit(f"{path}:{n}: expected id<TAB>old<TAB>new, got {line!r}")
        rid, old, new = (c.strip() for c in cells[:3])
        if rid in seen:
            sys.exit(f"{path}:{n}: duplicate id {rid!r}")
        seen.add(rid)
        out.add((rid, None if old == "-" else old, None if new == "-" else new))
    return out


def report_transitions(actual, expected, path) -> int:
    """Prints the transitions, then judges them if a sealed set was supplied.

    Returns the process exit code. Missing and surplus are named separately
    because they mean opposite things: a missing transition is a rule that did
    not fire, a surplus one is a rule that reached further than it claimed.
    """
    print(f"\ntransitions   {len(actual)}")
    for rid, old, new in sorted(actual):
        print(f"  {rid:60s} {old or '-'} -> {new or '-'}")
    if expected is None:
        return 0
    missing = sorted(expected - actual)
    surplus = sorted(actual - expected)
    print(f"\nagainst {path}")
    print(f"  expected    {len(expected)}")
    print(f"  MISSING     {len(missing)}   (sealed, but did not happen)")
    print(f"  SURPLUS     {len(surplus)}   (happened, but was not sealed)")
    for rid, old, new in missing:
        print(f"    MISSING  {rid:58s} {old or '-'} -> {new or '-'}")
    for rid, old, new in surplus:
        print(f"    SURPLUS  {rid:58s} {old or '-'} -> {new or '-'}")
    if missing or surplus:
        print("\nFAIL-EXPECT: the rules do not produce the sealed set.")
        return 1
    print("\nOK: the rules produce exactly the sealed set.")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true",
                    help="apply to the catalog; without it nothing is written")
    ap.add_argument("--pattern", help="report on one pattern only")
    ap.add_argument("--transitions", action="store_true",
                    help="list every row whose stored tag differs from the "
                         "recomputed one")
    ap.add_argument("--expect", metavar="PATH", type=Path,
                    help="compare those transitions against a sealed file and "
                         "exit non-zero on any difference")
    args = ap.parse_args()

    # "Neither flag writes anything" is a property the gate that introduced
    # them depends on, so it is enforced here rather than left to the caller.
    if args.write and (args.transitions or args.expect):
        sys.exit("--write cannot be combined with --transitions/--expect: "
                 "the comparison is against what is on disk NOW.")

    patterns, ex_title, ex_equipment = load_vocab()
    known = {p["id"] for p in patterns}
    if args.pattern and args.pattern not in known:
        sys.exit(f"unknown pattern {args.pattern!r}; known: "
                 + ", ".join(sorted(known)))

    rows = json.loads(CATALOG.read_text("utf-8"))
    tagged: list[tuple[str, str, str, str]] = []
    counts: collections.Counter = collections.Counter()
    # Captured BEFORE the loop, because the loop pops the field off rows it
    # would not tag -- so after it there is nothing left to compare against.
    stored = {row["id"]: row.get(FIELD) for row in rows}
    transitions: set[tuple[str, str | None, str | None]] = set()

    for row in rows:
        pid, reason = classify(row, patterns, ex_title, ex_equipment)
        if pid != stored[row["id"]]:
            transitions.add((row["id"], stored[row["id"]], pid))
        if pid is None:
            row.pop(FIELD, None)
            continue
        counts[pid] += 1
        tagged.append((row["id"], row["title"], pid, reason))
        if args.write:
            row[FIELD] = pid

    print(f"catalog rows      {len(rows)}")
    print(f"tagged            {sum(counts.values())} "
          f"({100 * sum(counts.values()) / len(rows):.1f}%)")
    print()
    for p in patterns:
        if args.pattern and p["id"] != args.pattern:
            continue
        print(f"  {p['id']:16s} {counts[p['id']]:5d}  {p['label']}")

    if args.transitions or args.expect:
        expected = read_expected(args.expect) if args.expect else None
        raise SystemExit(report_transitions(transitions, expected, args.expect))

    if args.write:
        # indent=2 + a trailing newline is what the catalog is already written
        # with -- verified by round-tripping the file before the first write,
        # rather than assumed. Guessing costs a diff of every one of the 1,887
        # rows, which buries the handful this pass actually changed.
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        AUDIT.mkdir(parents=True, exist_ok=True)
        out = AUDIT / "pose_target_tags.csv"
        with out.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["id", "title", "poseTargetId", "reason"])
            w.writerows(tagged)
        print(f"\nwrote {CATALOG.relative_to(ROOT)}")
        print(f"wrote {out.relative_to(ROOT)}")
    else:
        print("\ndry run -- re-run with --write to apply.")


if __name__ == "__main__":
    main()
