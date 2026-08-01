# -*- coding: utf-8 -*-
"""Mark the mobility work the importer missed.

`isStretch` arrived with the video library and was set only on rows whose
source folder was literally `stretching/`. Three Pilates movements and one
older free-exercise-db entry are the same kind of thing and were left unset,
so a filter reading the flag would quietly hide them.

Widened HERE rather than in the UI on purpose. A filter predicate that reads
`isStretch || id.contains('pilates')` puts a list of exercise names inside a
widget, where nobody looks when the catalog next changes. One field, one
meaning, and the rows that changed are visible in the diff.

Idempotent: re-running marks nothing, because the rows are already marked.
"""
from __future__ import annotations

import json
from pathlib import Path

CATALOG = (Path(__file__).resolve().parents[2] / 'mobile' / 'assets' / 'data'
           / 'exercises.json')

# Substrings that identify mobility work by name. Deliberately narrow — this
# runs once, and a loose rule here would sweep in every exercise whose title
# happens to mention a stretch of the movement.
MARKERS = ('pilates', '_stretch', 'stretch_')


def main() -> None:
    rows = json.loads(CATALOG.read_text(encoding='utf-8'))
    changed = []
    for row in rows:
        if row.get('isStretch'):
            continue
        i = row['id'].lower()
        if any(m in i for m in MARKERS):
            row['isStretch'] = True
            changed.append(f'{row["id"]}  —  {row["title"]}')

    if changed:
        CATALOG.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + '\n',
            encoding='utf-8')

    print(f'newly marked: {len(changed)}')
    for c in changed:
        print(f'  {c}')
    print(f'total isStretch: {len([r for r in rows if r.get("isStretch")])}')


if __name__ == '__main__':
    main()
