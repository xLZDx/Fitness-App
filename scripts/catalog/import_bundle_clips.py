# -*- coding: utf-8 -*-
"""Point the catalog at the licensed clips, and fill in what the vendor knows.

WHAT THIS DOES

For every exercise in `exercises.json`, find the clip in the purchased bundle
that demonstrates it -- separately for the women's and the men's render -- and
rewrite `video` to the object keys those clips will be served under. Then fill
any field the catalog is missing from the vendor's metadata sheet.

WHY THE VIDEO FIELD CHANGES SHAPE

Today `video` holds absolute public URLs. Licensed clips cannot be reached that
way: the vendor's permission is conditional on users not receiving "permanent
downloadable links", so those entries become object keys that the app exchanges
for a short-lived signed URL at play time. Both shapes coexist during the
migration and `ClipUrlResolver.isDirect` is the whole seam -- see
`mobile/lib/features/equipment/data/clip_url_resolver.dart`.

WHAT IT WILL NOT DO

**It never overwrites text the catalog already has.** The existing steps and
summaries came from a curated source and read well; the vendor's are terser and
only 69% present. A merge that preferred the newer source would quietly
downgrade 343 good entries to win 168. Empty fields only.

**It never invents a match.** Four passes, most confident first, each recorded
per row so the result can be audited instead of believed:

    exact     normalised words identical -- the only pass applied by default
    subset    every significant word of ours appears in theirs
    rejected  a subset match that named different equipment or movement
    fuzzy     word overlap above a threshold

Only `exact` is applied. That is a deliberate retreat from an earlier version
of this script, which applied `subset` too and reached 243 exercises instead of
142. Reading what it had actually matched is why:

    Wide-Grip Push-Up      -> triceps push down cable ezbar wide grip
    Cable Shoulder Press   -> resistance band cable lateral raise press
    Barbell Squat          -> barbell front squat
    Box Squat              -> box pistol squat

Every one satisfies "every significant word of ours appears in theirs". None is
the same exercise. The equipment and movement guards below catch the first two;
nothing catches "front" or "pistol", because practically every qualifier in
this domain distinguishes one exercise from another. A heuristic over names
cannot tell exercise identity, and a wrong demonstration teaches a wrong
movement -- which is worse than no demonstration, not better.

So subset candidates go to `core/bundle_import_report.csv` with their extra
words spelled out, for an eye that knows the difference. They are strong
candidates and most are probably right; `--include-subset` applies them in one
command once someone has looked. The clips are all uploaded either way, so
approving them later is a catalog edit, not a re-import.

Usage:
    python scripts/catalog/import_bundle_clips.py                    # measure
    python scripts/catalog/import_bundle_clips.py --write            # exact only
    python scripts/catalog/import_bundle_clips.py --write --include-subset
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bundle_layout import canonical_stem, plan_import  # noqa: E402
from match_vendor_list import norm  # noqa: E402
import vendor_paths  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises.json"
BUNDLE_ZIP = vendor_paths.BUNDLE_ZIP
VENDOR_META = vendor_paths.VENDOR_META
REPORT = ROOT / "core" / "bundle_import_report.csv"

# Below this, a fuzzy candidate is not even worth showing.
FUZZY_FLOOR = 0.60

# Words that name a piece of equipment. If the vendor's name carries one our
# title does not, it is a different exercise however well the rest overlaps.
#
# This exists because the subset pass shipped `Wide-Grip Push-Up` ->
# `triceps push down cable ezbar wide grip` and `Cable Shoulder Press` ->
# `resistance band cable lateral raise press`. Both satisfy "every significant
# word of ours appears in theirs" and both are the wrong demonstration. A
# bodyweight push-up is not a cable pushdown.
APPARATUS = {
    "band", "resistance", "machine", "cable", "dumbbell", "barbell",
    "kettlebell", "smith", "suspension", "trainer", "grips", "ball", "ezbar",
    "plate", "sled", "chair", "bench", "box", "rope", "landmine", "trx",
    "hammer", "pulley", "wheel", "roller", "step", "stability", "bosu",
}

# Words that name the movement itself. The vendor introducing one we did not
# ask for changes what the clip shows: `raise` where we said `press` is a
# lateral raise standing in for a shoulder press.
MOVEMENT = {
    "press", "pull", "push", "raise", "curl", "extension", "row", "squat",
    "lunge", "fly", "dip", "crunch", "kickback", "pulldown", "pushdown",
    "thrust", "bridge", "deadlift", "pullover", "shrug", "twist", "plank",
    "jump", "hold", "walk", "swing", "clean", "snatch", "jerk",
}

# Words that name a VARIANT of a movement. A front squat is not a back squat
# and a pistol squat is neither; each is its own exercise with its own load,
# balance and risk.
#
# This list is why `subset` is applied at all. Without it the guard let through
# `Barbell Squat -> barbell front squat` and `Box Squat -> box pistol squat`,
# which is what made exact-only look like the only safe option. With it, the
# rule is simply: the vendor may reorder our words and add nothing that names
# equipment, a movement, or a variant.
VARIANT = {
    "front", "back", "pistol", "sumo", "half", "quarter", "single", "one",
    "iso", "deficit", "tempo", "slow", "fast", "paused", "pulse", "pulses",
    "reverse", "incline", "decline", "wide", "close", "narrow", "neutral",
    "seated", "standing", "kneeling", "lying", "bent", "alternate", "assisted",
    "negative", "explosive", "isometric", "eccentric", "weighted", "banded",
    "upper", "lower", "high", "low", "chest", "leg", "arm", "overhead",
    "behind", "cross", "side", "lateral", "rear", "hip", "knee",
}


def disqualifying(ours: set[str], theirs: set[str]) -> str | None:
    """Why [theirs] cannot demonstrate [ours], or None if it can.

    Only ever consulted for a SUBSET match, where every word of ours already
    appears in theirs -- so the question is never "do they overlap" but "does
    what they added change the exercise".
    """
    added = theirs - ours
    equipment = added & APPARATUS
    if equipment:
        return f"adds equipment {sorted(equipment)}"
    movement = added & MOVEMENT
    if movement:
        return f"adds movement {sorted(movement)}"
    variant = added & VARIANT
    if variant:
        return f"adds variant {sorted(variant)}"
    return None


def load_plan() -> dict[str, dict[str, str]]:
    """{normalised stem: {'girl': key, 'men': key}} for every clip we will host."""
    import zipfile

    with zipfile.ZipFile(BUNDLE_ZIP) as z:
        members = {i.filename: i.file_size for i in z.infolist() if not i.is_dir()}
    plan = plan_import(members)

    by_stem: dict[str, dict[str, str]] = collections.defaultdict(dict)
    for key in plan.chosen:
        _, body, _group, filename = key.split("/", 3)
        stem = canonical_stem(filename.rsplit("/", 1)[-1][:-4])
        by_stem[" ".join(sorted(set(norm(stem))))][body] = key
    return dict(by_stem)


def load_metadata() -> dict[str, dict]:
    """{normalised stem: vendor fields}. Rows with nothing in them are skipped."""
    try:
        import openpyxl
    except ImportError:
        sys.exit("pip install openpyxl")
    workbook = openpyxl.load_workbook(VENDOR_META, read_only=True)
    rows = list(workbook.active.iter_rows(min_row=2, values_only=True))
    workbook.close()

    out: dict[str, dict] = {}
    for row in rows:
        name = str(row[1] or "").strip()
        if not name:
            continue
        fields = {
            "steps": row[2],
            "tips": row[3],
            "primaryMuscles": row[4],
            "muscles": row[5],
            "equipment": row[6],
        }
        if not any(v for v in fields.values()):
            continue
        # Gender is stripped: the metadata describes the movement, not the
        # model, and the women's row is frequently the only one filled in.
        from bundle_layout import split_gender

        stem, _ = split_gender(name)
        key = " ".join(sorted(set(norm(stem))))
        # First filled row wins; a later duplicate does not overwrite it.
        out.setdefault(key, fields)
    return out


def match(
    title: str, plan: dict[str, dict[str, str]]
) -> tuple[str, str, float, str]:
    """(pass, plan key, score, note). Pass is exact/subset/rejected/fuzzy/none.

    `rejected` is a subset match that named different equipment or a different
    movement. It carries its reason so the report says why rather than just
    dropping it.
    """
    ours = set(norm(title))
    if not ours:
        return "none", "", 0.0, ""

    key = " ".join(sorted(ours))
    if key in plan:
        return "exact", key, 1.0, ""

    best_subset, best_fuzzy, best_score = None, None, 0.0
    rejected: tuple[str, str] | None = None
    for candidate in plan:
        theirs = set(candidate.split())
        if not theirs:
            continue
        if ours <= theirs:
            reason = disqualifying(ours, theirs)
            if reason:
                # Remembered, not discarded: a title whose ONLY subset
                # candidates are disqualified should say so in the report.
                if rejected is None:
                    rejected = (candidate, reason)
                continue
            # Fewest extra qualifiers wins: "Leg Press" should prefer
            # "Leg Press" over "Leg Press Machine Single Leg Slow Tempo".
            if best_subset is None or len(theirs) < len(set(best_subset.split())):
                best_subset = candidate
            continue
        score = len(ours & theirs) / len(ours | theirs)
        if score > best_score:
            best_score, best_fuzzy = score, candidate
    if best_subset:
        return "subset", best_subset, 1.0, ""
    if rejected:
        return "rejected", rejected[0], 1.0, rejected[1]
    if best_score >= FUZZY_FLOOR:
        return "fuzzy", best_fuzzy or "", best_score, ""
    return "none", best_fuzzy or "", best_score, ""


def split_text(value) -> list[str]:
    """The vendor writes steps as one blob with newlines or numbered lines."""
    if not value:
        return []
    parts = [p.strip(" .;\t") for p in str(value).replace("\r", "").split("\n")]
    return [p for p in parts if p]


def split_list(value) -> list[str]:
    if not value:
        return []
    return [p.strip().lower() for p in str(value).replace("/", ",").split(",") if p.strip()]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="apply to exercises.json")
    ap.add_argument(
        "--include-subset",
        action="store_true",
        help="also apply subset matches -- only after reading the report",
    )
    args = ap.parse_args()
    applied = ("exact", "subset") if args.include_subset else ("exact",)

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    plan = load_plan()
    meta = load_metadata()
    print(f"{len(catalog)} catalog exercises, {len(plan)} bundle clips, "
          f"{len(meta)} metadata rows")

    passes = collections.Counter()
    filled = collections.Counter()
    rows_out = []
    gap_before = sum(1 for e in catalog if not e.get("video"))

    for entry in catalog:
        # Captured BEFORE anything is written. Reading it at the end of the
        # loop asked the mutated entry whether it used to have a clip, so the
        # --write run cheerfully reported "previously silent: 0" while the
        # measure-only run said 49. Same code, two answers, and the wrong one
        # only appeared in the run that mattered.
        had_video_before = bool(entry.get("video"))
        how, key, score, note = match(entry["title"], plan)
        passes[how] += 1
        clips = plan.get(key, {}) if how in applied else {}

        if clips:
            video = dict(entry.get("video") or {})
            for body in ("girl", "men"):
                if body in clips:
                    video[body] = clips[body]
            # Deliberately NOT copying the men's key into `girl` when the
            # women's render is missing. The app already falls back --
            # `ExerciseItem.playableVideoFor`, preference then men then
            # whichever exists -- and the operator has accepted seeing it (the
            # two models differ only by hair and a top). Duplicating the key
            # here would make the catalog claim a women's clip that does not
            # exist, corrupting any later coverage count and cutting a second
            # identical poster into the APK.
            if video:
                if args.write:
                    entry["video"] = video
                filled["video"] += 1

        fields = meta.get(key) if how in applied else None
        if fields:
            for target, raw, splitter in (
                ("steps", fields["steps"], split_text),
                ("tips", fields["tips"], split_text),
                ("primaryMuscles", fields["primaryMuscles"], split_list),
                ("muscles", fields["muscles"], split_list),
            ):
                if entry.get(target):
                    continue  # never overwrite curated text
                value = splitter(raw)
                if value:
                    if args.write:
                        entry[target] = value
                    filled[target] += 1

        rows_out.append({
            "id": entry["id"],
            "title": entry["title"],
            "pass": how,
            "score": f"{score:.2f}",
            "why_not": note,
            "vendor_match": key,
            "girl": clips.get("girl", ""),
            "men": clips.get("men", ""),
            "had_video_before": had_video_before,
        })

    print("\nmatch quality")
    for name in ("exact", "subset", "rejected", "fuzzy", "none"):
        n = passes[name]
        print(f"  {name:<9} {n:>4}  {n / len(catalog) * 100:.0f}%")
    print("  (only exact and subset are applied; rejected and fuzzy are")
    print("   reported so a human can look, never guessed at)")

    print("\nwould fill" if not args.write else "\nfilled")
    for field, n in filled.most_common():
        print(f"  {field:<15} {n:>4}")

    # Counted carefully, because the obvious arithmetic lies. "Exercises with
    # no licensed clip" is NOT the gap: 343 entries already play a clip from
    # the public library and keep doing so. The gap is entries with neither.
    licensed = sum(1 for r in rows_out if r["girl"] or r["men"])
    gap_after = sum(
        1 for r in rows_out if not (r["girl"] or r["men"]) and not r["had_video_before"]
    )
    newly_filled = sum(
        1 for r in rows_out if (r["girl"] or r["men"]) and not r["had_video_before"]
    )
    print(f"\nexercises now pointing at a licensed clip: {licensed}/{len(catalog)}")
    print(f"of which were previously silent:           {newly_filled}")
    print(f"exercises with no clip at all: {gap_before} -> {gap_after}")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows_out[0]))
        writer.writeheader()
        writer.writerows(rows_out)
    print(f"\nwrote {REPORT}")

    if args.write:
        # Same shape make_posters.py writes, so the two tools do not fight over
        # formatting and every diff is the content that actually changed.
        CATALOG.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {CATALOG}")
    else:
        print("nothing written -- pass --write to apply")


if __name__ == "__main__":
    main()
