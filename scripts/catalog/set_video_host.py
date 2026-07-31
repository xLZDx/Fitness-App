# -*- coding: utf-8 -*-
"""Point the 653 catalog video urls at a real host. One command, reversible.

    python scripts/catalog/set_video_host.py https://cdn.example.com/exercises
    python scripts/catalog/set_video_host.py --reset      # back to the placeholder

The catalog ships absolute urls on a placeholder host precisely so that
choosing a host is this, and not a rewrite of 653 rows or a regeneration of a
build chain that cannot reproduce itself (see `fix_video_urls.py` for why).

WHAT ELSE CHANGES WHEN YOU RUN THIS

Two tests are written to fail the moment a host exists, on purpose, because
both describe a state that stops being true:

  * `video_library_test.dart` -> "the host is still a placeholder"
  * `exercise_video_test.dart` -> "the whole shipped catalog is unplayable
    right now"

They are notes left for whoever sets the host. When they fail, check that
`ExerciseItem.playableVideoFor` really is returning urls and that a clip really
does play, then update the two tests to describe the new state.

The path layout is NOT touched. It mirrors the drop exactly — `<gender>/<Group>/
<file>.mp4`, percent-encoded — so uploading is a plain recursive copy of
`D:/Downloads/Video` and nothing has to agree about naming twice.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'mobile' / 'assets' / 'data' / 'exercises.json'
PLACEHOLDER = 'https://VIDEO_HOST_PLACEHOLDER/exercises'


def current_base(rows: list[dict]) -> str | None:
    for row in rows:
        for url in (row.get('video') or {}).values():
            return url.rsplit('/', 3)[0]
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('base', nargs='?',
                    help='new base url, e.g. https://cdn.example.com/exercises')
    ap.add_argument('--reset', action='store_true',
                    help='point everything back at the placeholder')
    args = ap.parse_args()

    if args.reset:
        target = PLACEHOLDER
    elif args.base:
        target = args.base.rstrip('/')
    else:
        ap.error('give a base url, or --reset')

    rows = json.loads(CATALOG.read_text('utf-8'))
    old = current_base(rows)
    if old is None:
        sys.exit('no video urls in the catalog — nothing to point anywhere')
    if old == target:
        print(f'already on {target}')
        return

    changed = 0
    for row in rows:
        video = row.get('video')
        if not video:
            continue
        for gender, url in list(video.items()):
            if not url.startswith(old + '/'):
                sys.exit(f'{row["id"]}: url is not on the current base: {url}')
            video[gender] = target + url[len(old):]
            changed += 1

    CATALOG.write_text(json.dumps(rows, ensure_ascii=False, indent=1) + '\n',
                       'utf-8')
    print(f'{old}  ->  {target}')
    print(f'urls rewritten: {changed}')
    if target != PLACEHOLDER:
        print('\nTwo tests are now expected to fail; they are notes for you:')
        print('  video_library_test  "the host is still a placeholder"')
        print('  exercise_video_test "the whole shipped catalog is unplayable"')
        print('Confirm a clip actually plays, then update both to the new state.')


if __name__ == '__main__':
    main()
