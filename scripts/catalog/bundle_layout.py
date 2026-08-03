# -*- coding: utf-8 -*-
"""Where each clip in the purchased bundle belongs, and under what name.

This is naming policy, kept apart from the encoder so it can be tested without
running ffmpeg over forty gigabytes. Three properties of the delivered archive
force every rule here, and all three were found by listing it rather than by
reading the vendor's documentation.

**The gender suffix is inconsistently cased.** 551 clips end `_Female` and 211
end `_female`; one ends `_Male`. A case-sensitive match -- the obvious way to
write it -- would have filed 211 women's clips as men's, silently, which is the
one outcome the operator explicitly asked to avoid.

**297 stems carry stray spaces.** `superman .mp4`, `box jump  .mp4`. Windows
strips trailing spaces from filenames, so these cannot be stored under their
delivered names at all; and a trailing space in a cloud object key is legal,
invisible, and permanent. They are canonicalised on the way in and the original
is kept in a mapping file.

**15 names collide once canonicalised.** Frames were pulled from all of them
and stacked in pairs (`core/bundle/duplicate_pairs_*.png`): every pair is the
same movement rendered twice, an older character set against a newer one. In 13
of 17 the newer render is the larger file, so the rule is keep the larger and
record what was dropped. One pair, `calf raise on hack squat machine`, shows two
visibly different machines and is flagged rather than resolved.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# Case-insensitive, and anchored to the end of the stem so an exercise that
# merely contains the word -- "female" appears in no current name, but the
# archive is not ours to constrain -- is not caught by accident.
#
# The lookahead allows a version marker to sit after the gender, because one
# delivered clip does exactly that: `...Inverted Row on floor_female_1.mp4`.
# A rule anchored hard to the end filed it under men, which is the failure the
# case-insensitivity above exists to prevent, arriving through a second door.
# The marker is kept in the stem so the pair `..._1` / `..._female_1` still
# resolves to one exercise with two renders rather than colliding with a
# differently-versioned clip.
#
# The separator is `[_ ]` because thirteen files write it with a SPACE --
# `Jump Rope Basic Jump Female.mp4`. That is a third door into the same failure:
# all thirteen were filed as men's clips AND carried the word "Female" in the
# title the user reads. Three variations on one convention, each found only by
# looking at the delivered names rather than trusting the documented one.
_GENDER = re.compile(r"[_ ](female|male)(?=(?:_\d+)?\s*$)", re.IGNORECASE)

# The one pair whose two files are genuinely different machines, not two renders
# of one exercise. Kept by name so the resolver reports it instead of silently
# discarding one.
AMBIGUOUS = {"calf raise on hack squat machine"}


def canonical_stem(stem: str) -> str:
    """Strip the ends, collapse the middle. Case is left alone.

    `'box jump  '` -> `'box jump'`, `'Dead  Bug'` -> `'Dead Bug'`.
    """
    return " ".join(stem.split())


def split_gender(stem: str) -> tuple[str, str]:
    """Returns (stem without the suffix, 'girl' or 'men').

    Unsuffixed clips are the male renders -- that is the vendor's convention,
    confirmed by 1,815 of 2,578 having no suffix at all while a matching
    `_Female` exists for many of them.
    """
    match = _GENDER.search(stem)
    if not match:
        return canonical_stem(stem), "men"
    body = "girl" if match.group(1).lower() == "female" else "men"
    without = stem[: match.start()] + stem[match.end() :]
    return canonical_stem(without), body


def object_path(member: str) -> str:
    """Archive member -> the object key it will be uploaded under.

    `'Legs/Plate Squat Hold_Female.mp4'` -> `'exercises/girl/Legs/Plate Squat Hold.mp4'`

    The shape matches the library already being served and the allow-list the
    signing function enforces, so an imported clip is reachable by exactly the
    same code path as an existing one.
    """
    group, _, base = member.rpartition("/")
    stem = base[:-4] if base.lower().endswith(".mp4") else base
    stem, body = split_gender(stem)
    group = canonical_stem(group) or "Misc"
    return f"exercises/{body}/{group}/{stem}.mp4"


@dataclass
class ImportPlan:
    """What to encode, what to skip, and what to tell someone about."""

    # object key -> the archive member chosen for it
    chosen: dict[str, str] = field(default_factory=dict)
    # object key -> members that lost, largest first
    discarded: dict[str, list[str]] = field(default_factory=dict)
    # object keys whose collision is NOT two renders of one exercise
    ambiguous: list[str] = field(default_factory=list)

    @property
    def total_discarded(self) -> int:
        return sum(len(v) for v in self.discarded.values())


def plan_import(members: dict[str, int]) -> ImportPlan:
    """Decide the whole import from a {member: size in bytes} listing.

    Collisions are settled by size, largest wins. Ties are settled by the name
    itself so two runs over the same archive always produce the same library --
    an import that shuffles under you is not reproducible, and "which of these
    two identical-length files did we ship?" is not a question anyone should
    have to answer later.
    """
    plan = ImportPlan()

    # Grouped case-INSENSITIVELY. `Dead Bug.mp4` and `dead bug .mp4` are one
    # exercise rendered twice, not two exercises, and object keys are
    # case-sensitive -- so grouping on the exact key would ship both and leave
    # the catalog with two candidates for one movement. 15 pairs in the
    # delivered archive land here.
    by_key: dict[str, list[tuple[int, str, str]]] = {}
    for member, size in members.items():
        if not member.lower().endswith(".mp4"):
            continue
        key = object_path(member)
        by_key.setdefault(key.casefold(), []).append((size, member, key))

    for _, candidates in sorted(by_key.items()):
        candidates.sort(key=lambda c: (-c[0], c[1]))
        _, winner, key = candidates[0]
        plan.chosen[key] = winner
        if len(candidates) > 1:
            plan.discarded[key] = [member for _, member, _ in candidates[1:]]
            stem = key.rsplit("/", 1)[-1][:-4].casefold()
            if stem in AMBIGUOUS:
                plan.ambiguous.append(key)
    return plan
