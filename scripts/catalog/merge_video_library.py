# -*- coding: utf-8 -*-
"""Merge the authored video library into the shipped catalog.

MERGE, NOT REPLACE. The catalog already holds 218 exercises illustrated by
photographs, and about 150 of them have no video in this drop. They keep their
stills and gain nothing; the `video` field is optional and only appears on rows
that have one. Deleting them to make the catalog "uniform" would delete the only
demo those exercises have.

WHAT HAPPENS TO EACH OF THE 359 VIDEO ROWS

  16 are dropped     10 are the same file twice (md5-proven), 6 have a name
                     that does not say what the movement is. Both lists, with
                     reasons, are in data/staging/library/UNSURE.txt.
  72 are merged      the catalog already ships that exercise. The EXISTING id
                     is kept -- a saved programme points at ids, so minting a
                     new one would silently break it -- and the row only
                     contributes its `video` object. Its authored text is not
                     used and never overwrites the existing entry.
 271 are added       new exercises, with English and Russian text and a video.

Result: 489 exercises, of which 343 carry a video.

IDS ARE STABLE. Existing ids are never rewritten; new ids keep the `vid_`
prefix `build_video_library.py` assigned, which also makes it obvious in a diff
where a row came from.

THE HOST IS ONE STRING. `VIDEO_BASE` is a placeholder on purpose: the hosting
decision (Firebase Storage now, Cloudflare R2 when egress starts to matter) is
not baked into 700 rows, so moving hosts is an edit here and a re-run, not a
migration.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library_source as S  # noqa: E402
from build_library import GROUPS  # noqa: E402

LIBRARY = S.STAGING / 'library'
EXERCISES = S.CATALOG_DIR / 'exercises.json'
EXERCISES_RU = S.CATALOG_DIR / 'exercises.ru.json'

# Single point of truth for where the clips are served from. Mirrors the
# constant in build_video_library.py; changing the host means changing it in
# both and re-running, which is two edits and no data migration.
VIDEO_BASE = 'https://VIDEO_HOST_PLACEHOLDER/exercises'

# The order the app reads: everything the existing catalog carries, plus the
# optional video. Keys are written in this order so a diff of the shipped file
# stays readable.
FIELDS = ['id', 'title', 'equipmentId', 'muscles', 'primaryMuscles',
          'difficulty', 'durationMinutes', 'summary', 'steps', 'frames',
          'imageUrls', 'contraindications']


def load_library() -> list[dict]:
    rows = []
    for group in GROUPS:
        rows += json.loads((LIBRARY / f'{group}.json').read_text('utf-8'))
    return rows


def main() -> None:
    base = json.loads(EXERCISES.read_text('utf-8'))
    base_ru = json.loads(EXERCISES_RU.read_text('utf-8'))
    rows = load_library()

    # Re-runnable: undo a previous run before doing this one. Otherwise the
    # script only works against a pristine catalog, which makes "fix a typo in
    # one Russian step and rebuild" a git operation instead of a re-run.
    # Only what this script adds is removed -- `vid_` rows and the `video` key.
    # `videoUrl`, `frames` and `imageUrls` belong to the older catalog and are
    # left alone.
    previously_added = [e for e in base if e['id'].startswith('vid_')]
    for e in previously_added:
        base_ru.pop(e['id'], None)
    base = [e for e in base if not e['id'].startswith('vid_')]
    for e in base:
        e.pop('video', None)
    if previously_added:
        print(f'(re-run: removed {len(previously_added)} rows from the '
              f'previous merge)')

    by_id = {e['id']: e for e in base}

    dropped = [r for r in rows if r.get('drop')]
    merged = [r for r in rows if r.get('mergeInto')]
    added = [r for r in rows if not r.get('drop') and not r.get('mergeInto')]

    # 1. Existing entries that the drop demonstrates: attach the video, change
    #    nothing else. Their id, text, translation and photographs stay put.
    attached = 0
    for r in merged:
        target = by_id.get(r['mergeInto'])
        if target is None:
            raise SystemExit(f'{r["id"]} merges into unknown id {r["mergeInto"]}')
        if 'video' in target:
            # Two video rows matched the same catalog entry. Keep the first;
            # the second is the same movement under another name.
            continue
        target['video'] = r['video']
        attached += 1

    # 2. New exercises.
    for r in added:
        if r['id'] in by_id:
            raise SystemExit(f'id collision: {r["id"]}')
        entry = {
            'id': r['id'],
            'title': r['title'],
            'equipmentId': r['equipmentId'],
            'muscles': r['muscles'],
            'primaryMuscles': r['primaryMuscles'],
            'difficulty': r['difficulty'],
            'durationMinutes': r['durationMinutes'],
            'summary': r['steps'][0],
            'steps': r['steps'],
            'frames': [],
            'imageUrls': [],
            'contraindications': [],
            'video': r['video'],
            'isStretch': r['isStretch'],
        }
        base.append(entry)
        base_ru[r['id']] = {'title': r['ru']['title'], 'steps': r['ru']['steps']}

    # 3. Checks that would otherwise only fail in the Flutter suite.
    equipment = {e['id'] for e in
                 json.loads((S.CATALOG_DIR / 'equipment.json').read_text('utf-8'))}
    titles: dict[str, str] = {}
    for e in base:
        eq = e.get('equipmentId')
        if eq is not None and eq not in equipment:
            raise SystemExit(f'{e["id"]} points at missing equipment {eq}')
        key = e['title'].lower()
        if key in titles:
            raise SystemExit(f'duplicate title {e["title"]!r}: {titles[key]} / {e["id"]}')
        titles[key] = e['id']
        if e['id'] not in base_ru:
            raise SystemExit(f'{e["id"]} has no Russian translation')
        # Compared after dropping blanks, the same way `ExerciseItem.parseSteps`
        # does at runtime -- one shipped upstream entry carries an empty step
        # and the translation legitimately does not.
        en = [s for s in e['steps'] if s.strip()]
        ru = [s for s in base_ru[e['id']]['steps'] if s.strip()]
        if len(en) != len(ru):
            raise SystemExit(f'{e["id"]} step counts differ between languages')
        if not en:
            raise SystemExit(f'{e["id"]} has no steps')
        for url in e.get('video', {}).values():
            if not url.startswith(VIDEO_BASE + '/'):
                raise SystemExit(f'{e["id"]} video url is not on the base host: {url}')

    ordered = []
    for e in base:
        row = {k: e[k] for k in FIELDS if k in e}
        if e.get('isStretch'):
            row['isStretch'] = True
        if 'video' in e:
            row['video'] = e['video']
        ordered.append(row)

    EXERCISES.write_text(
        json.dumps(ordered, ensure_ascii=False, indent=1) + '\n', 'utf-8')
    EXERCISES_RU.write_text(
        json.dumps(base_ru, ensure_ascii=False, indent=1, sort_keys=True) + '\n',
        'utf-8')

    with_video = sum(1 for e in ordered if 'video' in e)
    both = sum(1 for e in ordered if len(e.get('video', {})) == 2)
    print(f'video rows read      : {len(rows)}')
    print(f'  dropped            : {len(dropped)}')
    print(f'  merged into existing: {len(merged)} (video attached to {attached})')
    print(f'  added as new       : {len(added)}')
    print(f'catalog now          : {len(ordered)}')
    print(f'  with a video       : {with_video} ({both} have both genders, '
          f'{with_video - both} have one)')
    print(f'  stills only        : {len(ordered) - with_video}')
    print(f'  stretching entries : {sum(1 for e in ordered if e.get("isStretch"))}')
    print(f'-> {EXERCISES}')
    print(f'-> {EXERCISES_RU}')


if __name__ == '__main__':
    main()
