# -*- coding: utf-8 -*-
"""Turn the 677-file video drop into a catalog the app can read.

Operator, 2026-07-31: make these videos the backbone, one consistent library,
stretching included.

WHY THIS IS A NEW LIBRARY AND NOT AN IMPORT INTO THE OLD ONE

The existing catalog is 218 exercises illustrated by STILLS, and its whole
schema is shaped by that: `steps` is mandatory because a photograph cannot show
a movement, so the words have to. These 677 files are a different kind of asset
-- 359 exercises, each demonstrated twice, once by a woman and once by a man --
and a video does not need a paragraph to explain it.

Measured before writing any of this:
  * 359 unique exercises; 69 already in the catalog, 290 new.
  * Only 55 of our own 218 have a video here, so this is not a set of
    duplicates. It is mostly different material.
  * 64 of the new ones are stretching and mobility -- a category
    `import_free_exercise_db.py` filters out entirely, so we could not have had
    them.
  * 168 of the 359 (47%) map onto a Free Exercise DB entry, whose instructions
    are public domain and can be attached. The other 191 ship with the video
    and no invented text.

EQUIPMENT AND MUSCLES COME FROM THE FILENAME AND THE FOLDER, and nowhere else.
Both are stated by the source: the folder IS the muscle group, and the first
word of the name is nearly always the implement. Guessing beyond that -- which
is what the old importer's substring matcher did, and why "Dumbbell Bench Press"
landed on the barbell station -- is how a catalog fills with confident errors.
Anything that does not resolve is left null rather than assigned to a plausible
neighbour.
"""
from __future__ import annotations

import json
import re
import unicodedata
from urllib.parse import quote
from collections import defaultdict
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent))
import vendor_paths  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
VIDEO_ROOT = vendor_paths.DROP_DIR
CATALOG_DIR = ROOT / 'mobile' / 'assets' / 'data'
UPSTREAM = Path('D:/Temp/claude/free_exercise_db.json')
OUT = ROOT / 'data' / 'staging'

# Where the videos will be served from. A placeholder on purpose: the hosting
# decision (Firebase Storage now, Cloudflare R2 when egress starts to matter)
# must not be baked into 700 rows. Moving hosts is then one constant, not a
# migration.
VIDEO_BASE = 'https://VIDEO_HOST_PLACEHOLDER/exercises'

# Folder name -> our muscle vocabulary. The folders differ in case between the
# two gender trees ('Abs' vs 'abs'), which is why everything is lowercased
# before lookup.
GROUP_TO_MUSCLES = {
    'abs': ['core'],
    'back': ['back', 'lats'],
    'biceps': ['biceps'],
    'calves': ['calves'],
    'cardio': ['quads', 'core'],
    'chest': ['chest'],
    'forearms': ['forearms'],
    'hips': ['glutes', 'quads', 'hamstrings'],
    'shoulders': ['shoulders'],
    'trapezius': ['traps'],
    'triceps': ['triceps'],
    # Women-only folder: pilates, stability ball, planks. Core-dominant.
    'mix': ['core'],
}

# First-token implement -> registry id. Only unambiguous ones; a name that does
# not start with an implement is bodyweight or unknown, and is left null.
IMPLEMENT_TO_EQUIPMENT = {
    'band': 'resistance_bands',
    'barbell': 'barbell',
    'cable': 'cable_crossover',
    'dumbbell': 'dumbbell',
    'ez': 'ez_curl_bar',
    'kettlebell': 'kettlebell',
    'lever': None,          # "Lever" is this source's word for "machine", and
                            # WHICH machine is not recoverable from the name.
    'sled': 'leg_press',
    'smith': 'smith_machine',
    'weighted': None,
}

STOP = {'the', 'a', 'an', 'with', 'and', 'on', 'to', 'of', 'or'}


def slug(name: str) -> str:
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = re.sub(r'[^a-zA-Z0-9]+', '_', s).strip('_').lower()
    return f'vid_{s}'


def bag(name: str) -> frozenset:
    s = re.sub(r'\(.*?\)', ' ', name.lower().replace('.mp4', ''))
    s = re.sub(r'[^a-z0-9]+', ' ', s)
    return frozenset(
        w[:-1] if len(w) > 3 and w.endswith('s') and not w.endswith('ss') else w
        for w in s.split() if w and w not in STOP)


def jaccard(a: frozenset, b: frozenset) -> float:
    return len(a & b) / len(a | b) if (a | b) else 0.0


def scan() -> dict[str, dict]:
    """name -> {groups, genders}. One entry per exercise, not per file."""
    found: dict[str, dict] = {}
    for gender in ('girl', 'men'):
        base = next(p for p in VIDEO_ROOT.rglob(gender) if p.is_dir())
        for f in sorted(base.rglob('*.mp4')):
            entry = found.setdefault(f.stem, {'groups': set(), 'genders': {}})
            entry['groups'].add(f.parent.name.lower())
            # Path relative to the gender root, so the host layout mirrors the
            # drop exactly and re-uploading is a plain directory copy.
            #
            # Percent-encoded per segment, because almost every file in this
            # drop is named like "Decline Dumbbell Bench Press (45 degree).mp4"
            # -- spaces, brackets and apostrophes. A raw space is not legal in a
            # URL at all, so the un-encoded form is not "ugly", it is broken,
            # and it would have stayed invisible until the day the real host
            # went live. `safe=''` so the slashes we add stay slashes and the
            # ones inside a name (there are none, but) would not.
            path = '/'.join(
                quote(part, safe='')
                for part in (gender, f.parent.name, f.name))
            entry['genders'][gender] = path
    return found


def main() -> None:
    found = scan()
    upstream = json.loads(UPSTREAM.read_text('utf-8'))
    fe = [(bag(e['name']), e) for e in upstream]

    rows, with_text, no_text = [], 0, 0
    for name, meta in sorted(found.items()):
        group = sorted(meta['groups'])[0]
        muscles = GROUP_TO_MUSCLES.get(group)
        if muscles is None:
            raise SystemExit(f'unmapped folder {group!r} for {name!r}')

        head = re.split(r'[^A-Za-z]', name.strip())[0].lower()
        equipment = IMPLEMENT_TO_EQUIPMENT.get(head)

        w = bag(name)
        best, src = 0.0, None
        for fw, e in fe:
            s = jaccard(w, fw)
            if s > best:
                best, src = s, e
        # 0.6 is where the match stops being a coincidence -- measured over the
        # whole set before this script was written. Below it the instructions
        # would describe a different exercise, which is worse than none.
        steps = src['instructions'] if (best >= 0.6 and src) else []
        if steps:
            with_text += 1
        else:
            no_text += 1

        rows.append({
            'id': slug(name),
            'title': name.strip(),
            'equipmentId': equipment,
            'muscles': muscles,
            'primaryMuscles': muscles[:1],
            'group': group,
            'isStretch': name.lower().startswith('stretching'),
            'difficulty': 'beginner',
            'durationMinutes': 6,
            'summary': steps[0] if steps else '',
            'steps': steps,
            'sourceName': src['name'] if steps else None,
            'video': {
                g: f'{VIDEO_BASE}/{path}' for g, path in meta['genders'].items()
            },
            'frames': [],
            'imageUrls': [],
            'contraindications': [],
        })

    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / 'video_library.json'
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1) + '\n', 'utf-8')

    both = sum(1 for r in rows if len(r['video']) == 2)
    print(f'exercises            : {len(rows)}')
    print(f'  both genders       : {both}')
    print(f'  one gender only    : {len(rows) - both}')
    print(f'  stretching/mobility: {sum(1 for r in rows if r["isStretch"])}')
    print(f'  with public-domain steps: {with_text}')
    print(f'  video only, no steps    : {no_text}')
    eq = defaultdict(int)
    for r in rows:
        eq[r['equipmentId']] += 1
    print('\nequipment resolved from the implement in the name:')
    for k, v in sorted(eq.items(), key=lambda kv: -kv[1]):
        print(f'  {str(k):20s} {v:3d}')
    print(f'\n-> {out}')


if __name__ == '__main__':
    main()
