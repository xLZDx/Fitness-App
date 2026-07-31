# -*- coding: utf-8 -*-
"""Assemble `data/staging/library/<group>.json` from the authored text.

Split of responsibility:

  video_library.json    what the drop contains          (filenames, folders)
  library_source.py     what must not ship, what merges (md5, Jaccard)
  text/<group>.py       the words                       (authored by hand)
  this file             checks the words against the app's real constraints

The checks are here rather than in the Flutter suite because a violation is
cheaper to see while the group is still being written than after 344 rows have
landed in the catalog. They are deliberately the SAME rules the Dart tests
enforce, so a group that builds clean cannot fail `flutter test` on content:

  * equipmentId is null or an id that exists in equipment.json
  * every muscle tag is one the anatomy chart can already draw
  * the Russian step count equals the English one, per entry
  * every Russian string carries Cyrillic and no 4-letter Latin run
    (that run is what catches a half-translated "Lever" or a transliterated
    machine name, which reads as gibberish to a Russian speaker)
"""
from __future__ import annotations

import importlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library_source as S  # noqa: E402

OUT = S.STAGING / 'library'
GROUPS = ['abs', 'back', 'biceps', 'calves', 'cardio', 'chest', 'forearms',
          'hips', 'mix', 'shoulders', 'trapezius', 'triceps']

# The chart in `anatomy_map.dart` draws exactly these tags; anything else would
# silently never highlight (muscle_map_test.dart pins that).
VOCAB = {'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
         'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
         'traps', 'triceps'}

CYRILLIC = re.compile(r'[Ѐ-ӿ]')
LATIN_RUN = re.compile(r'[a-zA-Z]{4,}')


def equipment_ids() -> set[str]:
    raw = json.loads((S.CATALOG_DIR / 'equipment.json').read_text('utf-8'))
    return {e['id'] for e in raw}


def build(groups: list[str]) -> tuple[int, list[str]]:
    rows = {r['id']: r for r in S.load_rows()}
    catalog = S.load_catalog()
    merges = S.merge_targets(list(rows.values()), catalog)
    drops = S.dropped()
    eq_ids = equipment_ids()
    problems: list[str] = []
    written = 0

    for group in groups:
        mod = importlib.import_module(f'text.{group}')
        text = {f'vid_{k}': v for k, v in mod.ENTRIES.items()}
        want = [r for r in rows.values() if r['group'] == group]
        out = []

        unknown = set(text) - {r['id'] for r in want}
        if unknown:
            problems.append(f'{group}: text for rows not in this group: {sorted(unknown)}')

        for r in sorted(want, key=lambda x: x['id']):
            rid = r['id']
            if rid in drops:
                out.append({'id': rid, 'title': r['title'], 'drop': drops[rid],
                            'video': r['video']})
                continue
            if rid in merges:
                # The existing catalog entry keeps its id, its text and its
                # photographs; all it gains is the video. Any authored text for
                # this row would never be read, so it is not carried through.
                out.append({'id': rid, 'title': r['title'],
                            'mergeInto': merges[rid], 'video': r['video']})
                continue
            e = text.get(rid)
            if e is None:
                problems.append(f'{group}: no authored text for {rid} ({r["title"]})')
                continue

            en = e.get('en') or r['steps']
            ru_steps = e.get('rs') or []
            eq = e.get('eq')
            muscles = e.get('m') or []
            primary = e.get('p') or muscles[:1]

            if eq is not None and eq not in eq_ids:
                problems.append(f'{rid}: equipmentId {eq!r} is not in equipment.json')
            bad = set(muscles) | set(primary) - VOCAB
            bad = (set(muscles) | set(primary)) - VOCAB
            if bad:
                problems.append(f'{rid}: muscles outside the chart vocabulary: {sorted(bad)}')
            if not muscles:
                problems.append(f'{rid}: no muscles')
            # Authored text is held to 3-6 steps. Inherited public-domain text
            # is only checked for being non-empty: rewriting it to hit a step
            # count would make it no longer the source's words.
            lo = 3 if e.get('en') else 1
            if not (lo <= len(en) <= 8):
                problems.append(f'{rid}: {len(en)} English steps (want {lo}-8)')
            if len(en) != len(ru_steps):
                problems.append(f'{rid}: en={len(en)} ru={len(ru_steps)} steps')
            for s in [e.get('ru', '')] + ru_steps:
                if not CYRILLIC.search(s):
                    problems.append(f'{rid}: not Russian: {s[:40]!r}')
                run = LATIN_RUN.search(s)
                if run:
                    problems.append(f'{rid}: Latin left in Russian: {run.group()!r}')
            if any(not s.strip() for s in en + ru_steps):
                problems.append(f'{rid}: blank step')
            if not re.search(r'[A-Za-z]', e['t']) or e['t'] != e['t'].strip():
                problems.append(f'{rid}: bad English title: {e["t"]!r}')
            if CYRILLIC.search(e['t']):
                problems.append(f'{rid}: Cyrillic in the English title: {e["t"]!r}')

            out.append({
                'id': rid,
                'title': e['t'],
                'equipmentId': eq,
                'muscles': muscles,
                'primaryMuscles': primary,
                'group': group,
                'isStretch': bool(e.get('stretch', r['isStretch'])),
                'difficulty': e.get('d', 'beginner'),
                'durationMinutes': e.get('min', 6),
                'summary': en[0] if en else '',
                'steps': en,
                'ru': {'title': e['ru'], 'steps': ru_steps},
                'video': r['video'],
                'mergeInto': merges.get(rid),
            })

        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f'{group}.json').write_text(
            json.dumps(out, ensure_ascii=False, indent=1) + '\n', 'utf-8')
        written += len(out)

    return written, problems


def write_unsure() -> None:
    """The honest gap list, regenerated from the reasons themselves."""
    rows = {r['id']: r for r in S.load_rows()}
    lines = [
        'WHAT THIS FILE IS',
        '',
        'Every row of the 359-exercise video drop that could not be answered',
        'honestly. Two kinds of gap, kept apart because they cost different',
        'things: the first kind does not ship at all, the second ships with',
        'correct instructions but no machine attached.',
        '',
        'Nothing here was guessed. A wrong instruction or a plausible-looking',
        'wrong machine is worse than a missing row, because the user cannot',
        'tell it is wrong.',
        '',
        '',
        f'A. NOT SHIPPED -- the filename does not identify the movement ({len(S.UNIDENTIFIED)})',
        '',
    ]
    for rid, why in sorted(S.UNIDENTIFIED.items()):
        lines.append(f'  {rid}')
        lines.append(f'      title : {rows[rid]["title"]}')
        lines.append(f'      reason: {why}')
        lines.append('')
    lines += [
        '',
        f'B. NOT SHIPPED -- the same video file under a second name ({len(S.DUPLICATE_CLIPS)})',
        '',
        '  Proven by md5 over all 677 files in the drop, not by the name.',
        '',
    ]
    for rid, other in sorted(S.DUPLICATE_CLIPS.items()):
        lines.append(f'  {rid}')
        lines.append(f'      byte-identical to: {other}')
        lines.append('')
    lines += [
        '',
        f'C. SHIPPED, equipmentId left null -- no id exists for the implement ({len(S.EQUIPMENT_GAPS)})',
        '',
        '  These have full instructions in both languages. They are listed',
        '  because adding the implement to equipment.json is the fix, not',
        '  editing the exercise.',
        '',
    ]
    for rid, what in sorted(S.EQUIPMENT_GAPS.items()):
        lines.append(f'  {rid:<56} needs: {what}')
    lines += [
        '',
        '',
        'D. DATA-QUALITY NOTE, shipped as-is',
        '',
        '  girl/Back/Cable Bar Lateral Pulldown (reverse-grip).mp4 and',
        '  girl/Back/Cable Straight Back Seated High Row (reverse-grip).mp4 are',
        '  byte-identical, so one of the two girl clips is mislabelled at source.',
        '  The men clips for the same two names are different from each other, so',
        '  both exercises are real and both ship; only one girl demo is wrong and',
        '  there is no way to tell which.',
        '',
        '  girl/Abs/Hanging Leg Hip Raise.mp4 and',
        '  girl/Abs/Hanging Straight Leg Hip Raise.mp4 are likewise identical.',
        '',
    ]
    (OUT / 'UNSURE.txt').write_text('\n'.join(lines) + '\n', 'utf-8')


def main() -> None:
    groups = sys.argv[1:] or GROUPS
    written, problems = build(groups)
    if groups == GROUPS:
        write_unsure()
    for p in problems:
        print('PROBLEM', p)
    print(f'rows written: {written}   problems: {len(problems)}')
    if problems:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
