"""Freeze the SO1 vocabulary by DERIVING it from production, never by retyping it.

GPT-PM's MAJOR 3 on plan revision 1: the previous plan promised a generated
vocabulary and then listed no generator, and the omission is not bookkeeping.
Production resolution is semantic, not string equality -- `EquipmentAliasIndex`
normalises punctuation and whitespace, then resolves in two passes (the whole
text IS an alias; else the longest alias appearing as a whole-word phrase). A
slightly different SO1 normaliser would manufacture disagreement between the two
models where production sees none, or erase disagreement that is real. Either
way the experiment would be measuring its own normaliser.

So `normalise` and `resolve` here are a PORT of
`mobile/lib/features/equipment/data/equipment_alias_index.dart:38-72`, not a
reimplementation of the idea. That port already exists once, in TypeScript, at
`functions/src/__tests__/ai_equipment_recognition.test.ts:260-306` -- written
after GPT-PM's own G1 round-1 review caught a bare `toLowerCase().trim()`
standing in for the real algorithm. This is the third copy, and
`test_recog_so1.py` cross-checks it against both.

Sources, all read and none written:
  functions/src/ai_equipment_recognition.ts   CANONICAL_MACHINES, the prompt vocabulary
  mobile/assets/data/equipment_aliases.json   id -> [aliases], en + ru
  mobile/assets/data/equipment.json           the registry ids

Output: scripts/dev/recog_so1_vocab.json, byte-deterministic, carrying the
digests of all three sources so a later reader can tell whether the vocabulary
they hold was built from the production that shipped.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RECOGNITION_TS = REPO / "functions" / "src" / "ai_equipment_recognition.ts"
ALIASES_JSON = REPO / "mobile" / "assets" / "data" / "equipment_aliases.json"
EQUIPMENT_JSON = REPO / "mobile" / "assets" / "data" / "equipment.json"
OUT = REPO / "scripts" / "dev" / "recog_so1_vocab.json"

#: The sentinel the production prompt already offers. It is NOT a machine name
#: and must never resolve to an equipment id -- an `unknown` that quietly
#: resolved would turn an abstention into a false agreement.
UNKNOWN = "unknown"

_NON_TOKEN = re.compile(r"[^a-zа-я0-9]+")


def normalise(s: str) -> str:
    """Port of `EquipmentAliasIndex.normalise`.

    Lowercase, ё->е, every run of characters outside `[a-zа-я0-9]` collapsed to
    one space, trimmed. The ё->е fold happens BEFORE the character class,
    because 'ё' (U+0451) sits outside the 'а'-'я' (U+0430-U+044F) range and
    would otherwise be destroyed as punctuation rather than folded.
    """
    return _NON_TOKEN.sub(" ", s.lower().replace("ё", "е")).strip()


def build_alias_index(aliases: dict[str, list[str]]) -> dict[str, str]:
    """Normalised alias -> equipment id, exactly as `fromJson` builds `_exact`.

    Production lets a later id overwrite an earlier one for the same normalised
    alias; `build_registry.py` is what asserts no alias is claimed twice. This
    port keeps production's behaviour and REPORTS any collision rather than
    silently differing from it -- a collision is a finding about the registry,
    not something for this script to paper over.
    """
    index: dict[str, str] = {}
    collisions: list[tuple[str, str, str]] = []
    for equipment_id, names in aliases.items():
        for name in names:
            key = normalise(name)
            if key in index and index[key] != equipment_id:
                collisions.append((key, index[key], equipment_id))
            index[key] = equipment_id
    if collisions:
        for key, first, second in collisions:
            print(f"  ALIAS COLLISION {key!r}: {first} then {second}")
    return index


def resolve(free_text: str, index: dict[str, str]) -> str | None:
    """Port of `EquipmentAliasIndex.resolve`, passes 1 and 2.

    Pass 3 in production is "nothing -- null, never a guess", which is the
    absence of a pass rather than one. Needed in full because a canonical name
    like "hip abductor machine" is not itself a registered alias and only
    resolves through pass 2 against the shorter alias "hip abductor" -- the
    exact case GPT-PM's G1 review used to disprove an earlier claim that pass 1
    alone sufficed.
    """
    text = normalise(free_text)
    if not text:
        return None
    direct = index.get(text)
    if direct is not None:
        return direct
    best_id: str | None = None
    best_len = 0
    padded = f" {text} "
    for alias, equipment_id in index.items():
        if len(alias) <= best_len:
            continue
        if f" {alias} " in padded:
            best_id = equipment_id
            best_len = len(alias)
    return best_id


def read_canonical_machines(path: Path) -> list[str]:
    """Extract CANONICAL_MACHINES from the TypeScript source.

    Deliberately parsed out of production rather than copied into this file:
    a copy is exactly how the list in `ai_equipment_recognition.ts` and the one
    in `gemini_equipment_service.dart` drifted apart for months, which that
    file's own doc comment records.
    """
    src = path.read_text("utf-8")
    marker = "export const CANONICAL_MACHINES: readonly string[] = ["
    start = src.index(marker) + len(marker)
    end = src.index("] as const;", start)
    names = re.findall(r'"([^"]+)"', src[start:end])
    if not names:
        raise SystemExit(f"{path.name}: found the CANONICAL_MACHINES marker but no names inside it")
    if len(names) != len(set(names)):
        dupes = sorted({n for n in names if names.count(n) > 1})
        raise SystemExit(f"{path.name}: CANONICAL_MACHINES contains duplicates: {dupes}")
    return names


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build() -> dict:
    machines = read_canonical_machines(RECOGNITION_TS)
    aliases = json.loads(ALIASES_JSON.read_text("utf-8"))
    equipment_ids = [e["id"] for e in json.loads(EQUIPMENT_JSON.read_text("utf-8"))]
    index = build_alias_index(aliases)

    canonical_to_id: dict[str, str] = {}
    unresolved: list[str] = []
    for name in machines:
        resolved = resolve(name, index)
        if resolved is None:
            unresolved.append(name)
        else:
            canonical_to_id[name] = resolved
    if unresolved:
        raise SystemExit(
            "these canonical prompt names do not resolve in the registry, so a model "
            f"answering with them could not be scored at all: {unresolved}"
        )
    if resolve(UNKNOWN, index) is not None:
        raise SystemExit(
            f"the sentinel {UNKNOWN!r} resolves to an equipment id; an abstention would be "
            "scored as a named answer"
        )

    reachable = set(canonical_to_id.values())
    return {
        "_comment": (
            "Frozen SO1 vocabulary. Derived from production by "
            "scripts/dev/recog_so1_build_vocab.py -- do not hand-edit. Regenerating from the "
            "same sources reproduces these bytes exactly; if it does not, production moved and "
            "the experiment's canonicalisation is no longer the one it was pre-registered with."
        ),
        "unknown_sentinel": UNKNOWN,
        "canonical_machines": machines,
        "canonical_to_equipment_id": canonical_to_id,
        "alias_to_equipment_id": dict(sorted(index.items())),
        "registry_equipment_ids": sorted(equipment_ids),
        "registry_ids_unreachable_from_the_prompt": sorted(set(equipment_ids) - reachable),
        "sources": {
            "functions/src/ai_equipment_recognition.ts": digest(RECOGNITION_TS),
            "mobile/assets/data/equipment_aliases.json": digest(ALIASES_JSON),
            "mobile/assets/data/equipment.json": digest(EQUIPMENT_JSON),
        },
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="write scripts/dev/recog_so1_vocab.json")
    ap.add_argument("--check", action="store_true", help="rebuild and fail if the file on disk differs")
    args = ap.parse_args(argv)

    vocab = build()
    # sort_keys=False: the key order above is meaningful to a human reader and
    # is stable because it is written literally, not accumulated.
    text = json.dumps(vocab, ensure_ascii=False, indent=2, sort_keys=False) + "\n"

    print(f"{len(vocab['canonical_machines'])} canonical machine names")
    print(f"{len(vocab['alias_to_equipment_id'])} normalised aliases -> {len(set(vocab['alias_to_equipment_id'].values()))} ids")
    print(f"{len(vocab['registry_equipment_ids'])} registry ids, "
          f"{len(vocab['registry_ids_unreachable_from_the_prompt'])} unreachable from the prompt")

    if args.check:
        if not OUT.is_file():
            print(f"{OUT.relative_to(REPO)} does not exist")
            return 1
        on_disk = OUT.read_text("utf-8")
        if on_disk != text:
            print(f"{OUT.relative_to(REPO)} DIFFERS from a fresh build -- the vocabulary is not reproducible")
            return 1
        print(f"{OUT.relative_to(REPO)} is byte-identical to a fresh build")
        return 0

    if args.write:
        OUT.write_text(text, encoding="utf-8", newline="")
        print(f"wrote {OUT.relative_to(REPO)}  sha256 {digest(OUT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
