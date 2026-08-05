# -*- coding: utf-8 -*-
"""Turn the purchased library into a catalog of its own.

WHY THIS EXISTS AT ALL

The first attempt matched vendor clips onto our existing 511 titles. That put
every exercise's fate in the hands of a name comparison, and the comparison is
not up to it: `Alternating Renegade Row` and `dumbbell renegade row` are the
same movement and share one significant word. 94 of our exercises were reported
as "no vendor candidate" when a direct search of the archive finds most of them
under different phrasing.

Operator: *"мы же вроде договорились использовать только вендор ресурсы, какой
смысл сравнивать с тем что было"*. Right. This builds the vendor library as its
own list -- all 1,899 movements, complete, with no matching involved. Our 511
keep their Russian, their contraindications and their machine links; the two
lists sit side by side and the legacy one can be switched off.

WHAT EACH ENTRY GETS

    id          a slug from the vendor's own name, prefixed `ea_`
    title       the vendor's name, tidied
    video       object keys, per body, straight from the import plan
    muscles     from their metadata sheet (79% filled)
    steps/tips  likewise
    equipment   their free-text string, kept verbatim for now

Difficulty and duration are ours to invent and we do not have them, so they get
values that say so rather than a confident-looking guess: every entry is
`beginner`/10 minutes until something real replaces them. Nothing in the app
treats those as facts about the exercise -- difficulty only feeds tier sorting.

`--write` merges into the file rather than replacing it -- see `merge_rows`
for why that is not a refinement but a bug fix.

Usage:
    python scripts/catalog/build_vendor_catalog.py            # measure
    python scripts/catalog/build_vendor_catalog.py --write
    python scripts/catalog/build_vendor_catalog.py --write --allow-drop
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bundle_layout import canonical_stem, plan_import, split_gender  # noqa: E402
from match_vendor_list import norm  # noqa: E402
import vendor_paths  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
# Both of these read `D:/Downloads/...` until 2026-08-04, which is one
# directory short of where the files are. The raise that produced was read --
# by me, in two commit messages -- as "the vendor bundle is not on this
# machine", a claim about the machine rather than about a constant. See
# vendor_paths.
BUNDLE_ZIP = vendor_paths.BUNDLE_ZIP
VENDOR_META = vendor_paths.VENDOR_META

# The vendor's twelve folders, mapped to the muscle vocabulary the app already
# uses for filtering and for the muscle map. Only used when their metadata sheet
# has nothing -- a folder is a much weaker signal than a filled-in row.
GROUP_MUSCLES = {
    "Abdominals": ["core"],
    "Back": ["back"],
    "Biceps": ["biceps"],
    "Chest": ["chest"],
    "Forearms": ["forearms"],
    "Legs": ["quads"],
    "Shoulders": ["shoulders"],
    "Triceps": ["triceps"],
    # Four folders name no muscle honestly, so they get none. `full_body` and
    # `mobility` were the obvious inventions and both are wrong: neither is one
    # of the fifteen tags the app renders, so they would have shown as blank
    # chips and been invisible to the injury filter — the exact failure the
    # note on APP_MUSCLES describes, committed two functions later by me.
    #
    # An exercise with no tag still appears in every list and under its
    # equipment; it is only absent from a muscle chip, which is honest, because
    # we genuinely do not know which muscle a "Calisthenics" clip trains.
    "Calisthenics-Cardio-Plyo-Functional": [],
    "Powerlifting": [],
    "Stretching - Mobility": [],
    "Yoga": [],
}

STRETCH_GROUPS = {"Stretching - Mobility", "Yoga"}

# Fields this script emits but does not own. `build()` produces `equipmentId`
# as null so every row has the same shape, but the value belongs to the
# equipment-linking pass (`link_vendor_equipment.py:302`), and
# `contraindications` will belong to the tagging pass. Writing our own empty
# value over theirs is exactly the data loss `merge_rows` exists to stop, so on
# merge the file's value wins for these keys even though we do produce them.
#
# `poseTargetId` joined them for the same reason and with a sharper edge: this
# script never emits it at all, so without the entry below a rebuild would drop
# all 570 tags silently -- the exercises would simply stop offering the Form
# Coach, with nothing failing and nothing logged.
CURATED = {"equipmentId", "contraindications", "poseTargetId"}

# The app understands exactly fifteen muscle tags — the vocabulary already in
# `exercises.json`, read by the muscle map, the muscle chips and the injury
# filter. Anything that does not map lands here as nothing rather than as a new
# tag: an unrecognised value would show as an empty chip and, worse, would be
# invisible to `filterContraindicated`, so an exercise could slip past a user's
# injury because its muscle was spelled in a way the filter never heard of.
APP_MUSCLES = {
    "adductors", "back", "biceps", "calves", "chest", "core", "forearms",
    "glutes", "hamstrings", "lats", "lower_back", "quads", "shoulders",
    "traps", "triceps",
}

# Their vocabulary against ours. Written from the actual column values, which
# are phrased `Glutes (Gluteus Maximus, Gluteus Medius)` — the Latin sits in
# brackets and contains its own commas, which is why the brackets are stripped
# before anything is split. Splitting first produced tags like
# `gluteus mideus)` and mapped nothing at all.
MUSCLE_ALIASES = {
    "abdominals": "core", "abs": "core", "core": "core", "obliques": "core",
    "rectus abdominis": "core", "transverse abdominis": "core",
    "lower back": "lower_back", "erector spinae": "lower_back",
    "lats": "lats", "latissimus dorsi": "lats", "middle back": "lats",
    "back": "back", "upper back": "traps", "trapezius": "traps",
    "traps": "traps", "rhomboids": "back", "teres major": "back",
    "chest": "chest", "pectoralis major": "chest", "pectorals": "chest",
    "shoulders": "shoulders", "deltoids": "shoulders", "delts": "shoulders",
    "rotator cuff": "shoulders",
    "biceps": "biceps", "triceps": "triceps", "forearms": "forearms",
    "brachioradialis": "forearms", "brachialis": "biceps",
    "quadriceps": "quads", "quads": "quads",
    "hamstrings": "hamstrings",
    "glutes": "glutes", "gluteus maximus": "glutes", "gluteus medius": "glutes",
    "calves": "calves", "soleus": "calves", "gastrocnemius": "calves",
    "adductors": "adductors", "abductors": "glutes",
    # No tag of our own, and the nearest honest home for each. Hip flexors and
    # the spinal erectors both sit with the lower back for filtering purposes;
    # a "full body" movement is left untagged rather than given all fifteen.
    "hip flexors": "lower_back", "iliopsoas": "lower_back",
    "spinal erectors": "lower_back",
}


def slug(name: str) -> str:
    """`'Barbell Full Squat'` -> `'ea_barbell_full_squat'`.

    Prefixed so a vendor entry is recognisable at a glance in a log, a
    Firestore document or a bug report, and can never collide with the
    `fedb_` / `vid_` / hand-authored ids already in use.
    """
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return f"ea_{s}" or "ea_unnamed"


def tidy_title(stem: str) -> str:
    """Their filenames are cased at random -- `barbell full squat`, `AB Wheel
    Pulses`, `Dumbbell Fly`. Title-case everything so one list does not look
    like three imports."""
    small = {"to", "on", "in", "with", "and", "the", "a", "of", "or", "at"}
    words = canonical_stem(stem).split()
    out = []
    for i, w in enumerate(words):
        # Strip punctuation before testing for an acronym, or `POV)` fails
        # `isupper()` on the bracket and comes out as `Pov)`.
        core = w.strip("()[[]{}.,:-")
        if core.isupper() and 1 < len(core) <= 4:
            out.append(w)  # AB, EZ, TRX, POV
        elif i and w.lower() in small:
            out.append(w.lower())
        else:
            out.append(w[:1].upper() + w[1:].lower())
    return " ".join(out)


def load_metadata() -> dict[str, dict]:
    try:
        import openpyxl
    except ImportError:
        sys.exit("pip install openpyxl")
    wb = openpyxl.load_workbook(VENDOR_META, read_only=True)
    rows = list(wb.active.iter_rows(min_row=2, values_only=True))
    wb.close()
    out: dict[str, dict] = {}
    for row in rows:
        name = str(row[1] or "").strip()
        if not name:
            continue
        stem, _ = split_gender(name)
        key = " ".join(sorted(set(norm(canonical_stem(stem)))))
        filled = any(row[i] not in (None, "") for i in (2, 3, 4, 5, 6))
        # A filled row beats an empty one for the same movement; otherwise the
        # first wins. Their sheet has a row per gender and often fills only one.
        if key not in out or (filled and not out[key]["filled"]):
            out[key] = {
                "steps": row[2], "tips": row[3], "primary": row[4],
                "secondary": row[5], "equipment": row[6], "filled": filled,
            }
    return out


def split_steps(value) -> list[str]:
    if not value:
        return []
    text = str(value).replace("\r", "")
    parts = [p.strip() for p in text.split("\n")]
    # Their numbering is inconsistent ("1.", "1)", "Step 1:"); strip it so the
    # app's own numbered list does not read "1. 1. Stand with...".
    cleaned = [re.sub(r"^(step\s*)?\d+[\.\)\:]\s*", "", p, flags=re.I) for p in parts]
    return [c.strip(" .;\t") for c in cleaned if c.strip(" .;\t")]


def split_muscles(value) -> list[str]:
    """`'Glutes (Gluteus Maximus, Gluteus Medius), Quadriceps'` -> `['glutes',
    'quads']`.

    Brackets go first. Their Latin names live inside them and carry their own
    commas, so splitting before stripping tore `Glutes (Gluteus Maximus,
    Gluteus Medius)` into `glutes (gluteus maximus` and `gluteus mideus)` —
    two tokens, neither of which maps, which is why every generated entry came
    out with no primary muscle at all.
    """
    if not value:
        return []
    text = re.sub(r"\([^)]*\)", " ", str(value).lower())
    out: list[str] = []
    for token in re.split(r"[,/;]| and ", text):
        token = token.strip(" .")
        mapped = MUSCLE_ALIASES.get(token)
        if mapped and mapped in APP_MUSCLES and mapped not in out:
            out.append(mapped)
    return out


def build() -> list[dict]:
    with zipfile.ZipFile(BUNDLE_ZIP) as z:
        members = {i.filename: i.file_size for i in z.infolist() if not i.is_dir()}
    plan = plan_import(members)
    meta = load_metadata()

    by_stem: dict[str, dict] = {}
    for key in sorted(plan.chosen):
        _, body, group, filename = key.split("/", 3)
        stem = canonical_stem(filename.rsplit("/", 1)[-1][:-4])
        norm_key = " ".join(sorted(set(norm(stem))))
        entry = by_stem.setdefault(norm_key, {
            "stem": stem, "group": group, "video": {},
        })
        entry["video"][body] = key
        # The men's spelling wins the title when both exist, purely so the
        # choice is deterministic rather than dependent on dict order.
        if body == "men":
            entry["stem"] = stem

    out: list[dict] = []
    seen_ids: set[str] = set()
    for norm_key, e in by_stem.items():
        m = meta.get(norm_key, {})
        muscles = split_muscles(m.get("primary")) + split_muscles(m.get("secondary"))
        primary = split_muscles(m.get("primary"))
        if not muscles:
            muscles = list(GROUP_MUSCLES.get(e["group"], []))
        exercise_id = slug(e["stem"])
        if exercise_id in seen_ids:
            # Two different vendor spellings that slug the same. Keep both and
            # make the second distinct rather than silently dropping a clip.
            n = 2
            while f"{exercise_id}_{n}" in seen_ids:
                n += 1
            exercise_id = f"{exercise_id}_{n}"
        seen_ids.add(exercise_id)

        steps = split_steps(m.get("steps"))
        tips = split_steps(m.get("tips"))
        row = {
            "id": exercise_id,
            "title": tidy_title(e["stem"]),
            "equipmentId": None,
            "muscles": muscles,
            "primaryMuscles": primary,
            # Ours to invent and we do not have it. `beginner`/10 is the value
            # that says "unknown" here; difficulty only feeds tier sorting and
            # duration only feeds a label.
            "difficulty": "beginner",
            "durationMinutes": 10,
            "summary": steps[0] if steps else "",
            "steps": steps,
            "video": e["video"],
            "isStretch": e["group"] in STRETCH_GROUPS,
            "vendorGroup": e["group"],
        }
        if tips:
            row["tips"] = tips
        # An entry the sheet says nothing about is UNKNOWN, not bodyweight.
        # 496 of the 1,899 have no equipment column at all, and leaving the
        # field null made `needsEquipment` read them as needing nothing —
        # which put them in an "at home" tab that promises exactly that.
        row["equipmentLabel"] = (
            str(m["equipment"]).strip() if m.get("equipment") else "Unknown"
        )
        out.append(row)

    out.sort(key=lambda r: r["title"].lower())
    return out


VOCAB = Path(__file__).with_name("injury_regions.json")


def load_vocabulary() -> set[str]:
    """The legal `contraindications` tags.

    Projected from `InjuryRegion` in `profile_models.dart`, which is the source
    of truth; `vocabulary_test.dart` fails if the two drift. Read here rather
    than restated, because a second hand-written list of the same eight strings
    is how four Stripe price secrets went silently unbound earlier in this
    remediation.
    """
    raw = json.loads(VOCAB.read_text(encoding="utf-8"))
    return set(raw["tags"])


def invalid_tags(rows: list[dict], vocabulary: set[str]) -> list[tuple[str, str]]:
    """Every (id, tag) pair whose tag matches no region.

    A tag outside the vocabulary is worse than a missing one: `isContraindicated`
    compares it against `InjuryRegion.tag` exactly, so a typo screens nobody --
    and screens them silently, with the row looking tagged in every count.
    """
    return [
        (row["id"], tag)
        for row in rows
        for tag in row.get("contraindications") or []
        if tag not in vocabulary
    ]


def load_existing() -> list[dict]:
    if not OUT.exists():
        return []
    return json.loads(OUT.read_text(encoding="utf-8"))


def merge_rows(
    generated: list[dict], existing: list[dict]
) -> tuple[list[dict], list[str]]:
    """Fold what we just generated into what is already on disk, keyed by `id`.

    The first version of this script wrote `generated` straight over the file,
    and that is a data-loss bug rather than a stylistic one. Measured on the
    shipped catalog the day this was written: 1,887 rows carry a `poster` map
    written by `make_vendor_posters.py`, 1,384 carry an `equipmentId` written
    by `link_vendor_equipment.py`, and this generator produces neither -- it
    emits no `poster` key at all and a null `equipmentId`. So a rebuild for an
    unrelated reason, one new clip in the bundle, threw away both, and nothing
    anywhere would have gone red.

    That is the same shape as the incident this whole remediation answers:
    a catalog swap deleted the only 144 contraindication-tagged exercises in
    the product and every test stayed green. Tagging 1,887 exercises by hand
    while `--write` still behaved this way would have queued up the identical
    loss on a much larger pile of work.

    Three rules, in the order of who wins a key:

    * one the file has and we never produce  -> the file's  (`poster`)
    * one in CURATED                         -> the file's  (`equipmentId`)
    * anything else                          -> ours        (`title`, `video`)

    A row on disk keeps a field we have stopped producing (`tips`, when the
    vendor sheet loses a row). Stale text is a far smaller harm than deleted
    curated work, which is the trade this whole function is making.

    Returns the merged rows plus the ids that are on disk and no longer
    generated; the caller decides whether losing those is acceptable.
    """
    by_id = {r["id"]: r for r in existing}
    merged: list[dict] = []
    for row in generated:
        old = by_id.get(row["id"])
        if old is None:
            merged.append(row)
            continue
        combined = dict(row)
        for key, value in old.items():
            if key not in combined or key in CURATED:
                combined[key] = value
        merged.append(combined)

    generated_ids = {r["id"] for r in generated}
    return merged, [r["id"] for r in existing if r["id"] not in generated_ids]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument(
        "--allow-drop",
        action="store_true",
        help="permit --write to remove rows that are on disk but no longer "
        "generated. Without it a missing or partial bundle deletes them, "
        "along with every curated field they carry.",
    )
    args = ap.parse_args()

    existing = load_existing()
    rows, dropped = merge_rows(build(), existing)

    # Counted on the merged rows, not on `build()`'s output: this is what the
    # file will contain, and the two differ by exactly the curated fields.
    print(f"vendor exercises   {len(rows)}  (on disk now: {len(existing)})")
    print(f"  both bodies      {sum(1 for r in rows if len(r['video']) == 2)}")
    print(f"  with steps       {sum(1 for r in rows if r['steps'])}")
    print(f"  with tips        {sum(1 for r in rows if r.get('tips'))}")
    print(f"  with muscles     {sum(1 for r in rows if r['muscles'])}")
    print(f"  stretch/mobility {sum(1 for r in rows if r['isStretch'])}")
    print(f"  with equipment   {sum(1 for r in rows if r.get('equipmentLabel'))}")
    print(f"  with posters     {sum(1 for r in rows if r.get('poster'))}")
    print(f"  linked to a gym  {sum(1 for r in rows if r.get('equipmentId'))}")
    # `contraindications` is what `filterContraindicated` reads, and the one
    # coverage number the six above never reported. It stood at 0 of 1,887
    # while the app told users their injuries were being filtered for.
    print(f"  with safety tags {sum(1 for r in rows if r.get('contraindications'))}")
    # Per region, not just a total. A batch that tags 200 knees and no
    # shoulders raises the floor exactly as much as a balanced one, so the
    # total alone cannot say which injuries the catalog can actually screen
    # for -- and "screened for your injuries" is only true per injury.
    vocabulary = load_vocabulary()
    per_region = collections.Counter(
        tag for r in rows for tag in r.get("contraindications") or []
    )
    print("  by region        " + (
        ", ".join(f"{tag} {per_region.get(tag, 0)}" for tag in sorted(vocabulary))
    ))
    bad = invalid_tags(rows, vocabulary)
    if bad:
        print(f"\n{len(bad)} tags match no region and screen for nobody:")
        for exercise_id, tag in bad[:10]:
            print(f"    {exercise_id}: {tag}")
        if len(bad) > 10:
            print(f"    ... and {len(bad) - 10} more")
    groups = collections.Counter(r["vendorGroup"] for r in rows)
    print(f"  groups           {dict(sorted(groups.items()))}")

    if dropped:
        print(f"\n{len(dropped)} rows are on disk but no longer generated:")
        for exercise_id in dropped[:10]:
            print(f"    {exercise_id}")
        if len(dropped) > 10:
            print(f"    ... and {len(dropped) - 10} more")

    if args.write:
        if dropped and not args.allow_drop:
            sys.exit(
                "\nrefusing to write: this would delete the rows listed above "
                "and every curated field on them. Re-run with --allow-drop if "
                "the removal is what you meant."
            )
        if bad:
            # No --allow flag for this one, deliberately. Dropping rows can be
            # legitimate (a shrunken bundle), so that guard is overridable; a
            # tag outside the vocabulary is never what anyone meant, and the
            # override would only ever be used to get past a typo.
            sys.exit(
                "\nrefusing to write: the tags listed above match no "
                "InjuryRegion, so they would screen for nobody while counting "
                "as coverage. Fix the tags, or add the region to InjuryRegion "
                "and to injury_regions.json together."
            )
        OUT.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nwrote {OUT}  ({OUT.stat().st_size / 1e6:.2f} MB)")
    else:
        print("\nnothing written -- pass --write")


if __name__ == "__main__":
    main()
