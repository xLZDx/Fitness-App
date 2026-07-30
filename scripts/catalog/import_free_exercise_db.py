# -*- coding: utf-8 -*-
"""S0 (defect round 4, 2026-07-30): pull real curated exercises from the
upstream Free Exercise DB (Unlicense/public domain, already our vendored
source — see build_registry.py) for the 32 registry machines that shipped
with ZERO curated exercises after Round 3 (operator screenshot: Elliptical
-> "No curated exercises yet for this machine").

Upstream is 873 exercises; our catalog used only 72. This script resolves
each upstream exercise's NAME (and generic "equipment" type field) onto our
48-id registry via the same alias index recognition uses, so a real
gym-standard exercise lands on the exact machine page it belongs to instead
of relying on an AI-generated fallback for machines that already have a
real, public-domain-licensed answer.

Capped at 6 new exercises per id (matches the existing per-machine "6
recommended exercises" pattern already in the app) to keep the RU
translation workload finite and reviewable in one pass, rather than
importing all 873 unfiltered.

Output: data/staging/free_exercise_db_import_en.json -- the EN-only staging
file this script produces. A human (me, next step) translates it into
exercises.ru.json entries; nothing here writes exercises.json directly,
because the Russian text needs real translation, not a template.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = Path('D:/Temp/claude/free_exercise_db.json')
CATALOG_DIR = ROOT / 'mobile' / 'assets' / 'data'
STAGING = ROOT / 'data' / 'staging'
CAP_PER_ID = 6

# Phrase-order / synonym overrides the substring-alias matcher cannot catch
# (e.g. "Machine Bicep Curl" vs our alias "bicep curl machine" -- same
# words, different order). Each verified by reading the exercise name
# against the registry description, not guessed.
NAME_OVERRIDE = {
    'Machine Bicep Curl': 'bicep_curl_machine',
    'Machine Preacher Curls': 'preacher_curl_bench',
    'Machine Triceps Extension': 'tricep_extension_machine',
    'Machine Shoulder (Military) Press': 'shoulder_press_machine',
    'Thigh Abductor': 'hip_abductor_adductor',
    'Thigh Adductor': 'hip_abductor_adductor',
    'Bicycling, Stationary': 'exercise_bike',
    'Step Mill': 'stair_climber',
    'Leg Extensions': 'leg_extension',
    'Lying Leg Curls': 'leg_curl',
    'Calf Press': 'calf_raise_machine',
    'Standing Calf Raises': 'calf_raise_machine',
    'Glute Ham Raise': 'back_extension',
    'Narrow Stance Hack Squats': 'hack_squat_machine',
    'Reverse Machine Flyes': 'pec_deck',
    'Lying Machine Squat': 'hack_squat_machine',
    'Rowing, Stationary': 'rowing_machine',
    # Ambiguous / not a real machine match -- explicitly excluded.
    'Calf-Machine Shoulder Shrug': None,
    'Chair Squat': None,
}

INCLUDE_CATEGORIES = {
    'strength', 'plyometrics', 'powerlifting', 'olympic weightlifting',
}


def build_alias_lookup() -> dict[str, str]:
    aliases = json.loads(
        (CATALOG_DIR / 'equipment_aliases.json').read_text('utf-8'))
    exact = {}
    for eid, names in aliases.items():
        for a in names:
            exact[a] = eid
    return exact


def resolve(exercise: dict, exact: dict[str, str]) -> str | None:
    name = exercise['name']
    if name in NAME_OVERRIDE:
        return NAME_OVERRIDE[name]
    text = name.lower()
    if text in exact:
        return exact[text]
    best_id, best_len = None, 0
    padded = f' {text} '
    for alias, eid in exact.items():
        if len(alias) <= best_len:
            continue
        if f' {alias} ' in padded:
            best_id, best_len = eid, len(alias)
    if best_id:
        return best_id
    if exercise.get('equipment') == 'body only':
        return '__bodyweight__'
    return None


def main() -> None:
    upstream = json.loads(UPSTREAM.read_text('utf-8'))
    existing = json.loads((CATALOG_DIR / 'exercises.json').read_text('utf-8'))
    existing_names = {e['title'].lower() for e in existing}
    exact = build_alias_lookup()

    by_id: dict[str, list[dict]] = {}
    for e in upstream:
        if e['name'].lower() in existing_names:
            continue
        if e.get('category') not in INCLUDE_CATEGORIES:
            continue
        eid = resolve(e, exact)
        if eid is None:
            continue
        by_id.setdefault(eid, []).append(e)

    staged = []
    for eid in sorted(by_id):
        for e in sorted(by_id[eid], key=lambda x: x['name'])[:CAP_PER_ID]:
            staged.append({
                'source_id': e['id'],
                'name': e['name'],
                'equipmentId': None if eid == '__bodyweight__' else eid,
                'level': e.get('level', 'beginner'),
                'primaryMuscles': e.get('primaryMuscles', []),
                'secondaryMuscles': e.get('secondaryMuscles', []),
                'instructions': e.get('instructions', []),
                'images': [
                    f'https://raw.githubusercontent.com/yuhonas/'
                    f'free-exercise-db/main/exercises/{img}'
                    for img in e.get('images', [])
                ],
            })

    STAGING.mkdir(parents=True, exist_ok=True)
    out = STAGING / 'free_exercise_db_import_en.json'
    out.write_text(
        json.dumps(staged, ensure_ascii=False, indent=1) + '\n', 'utf-8')
    print(f'staged {len(staged)} exercises -> {out}')
    from collections import Counter
    print(Counter(s['equipmentId'] for s in staged).most_common())


if __name__ == '__main__':
    main()
