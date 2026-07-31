# -*- coding: utf-8 -*-
"""Percent-encode the video URLs already shipped in `exercises.json`.

WHY THIS IS A SEPARATE SCRIPT AND NOT A RE-RUN OF THE GENERATOR

`merge_video_library.py` calls `library_source.merge_targets(rows, catalog)`,
and `catalog` is `exercises.json` as it is ON DISK. After the first merge that
file already contains the 293 rows the merge itself added, so a second run
compares the video drop against its own output: rows match ids that only exist
because of the previous run, and the run fails part-way with the catalog
already stripped. Measured, not assumed -- a re-run on 2026-07-31 removed 293
rows and then died on `vid_45_degree_bycicle_twisting_crunch merges into
unknown id`, and the catalog had to be restored from a copy.

So the shipped JSON is the source of truth, and a correction to it is a
transform of that file rather than a rebuild. This one is idempotent: unquote
before quote, so running it twice does not turn '%20' into '%2520'.

THE BUG IT FIXES

637 of 653 URLs contained a raw space, and 75 contained brackets or an
apostrophe, because the drop names files like
"Decline Dumbbell Bench Press (45 degree).mp4". A space is not legal in a URL.
Nothing noticed because every URL points at VIDEO_HOST_PLACEHOLDER and the app
does not yet read the field -- it would have surfaced on the day the real host
went live, as a library of videos that all fail to load.

`build_video_library.py` now encodes at the point the URL is built, so a clean
generation is already correct; this exists for the catalog that shipped before
that fix.
"""
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit, urlunsplit

CATALOG = Path(__file__).resolve().parents[2] / 'mobile' / 'assets' / 'data' \
    / 'exercises.json'


def encode(url: str) -> str:
    parts = urlsplit(url)
    path = '/'.join(
        quote(unquote(seg), safe='') for seg in parts.path.split('/'))
    return urlunsplit((parts.scheme, parts.netloc, path, parts.query,
                       parts.fragment))


def main() -> None:
    rows = json.loads(CATALOG.read_text('utf-8'))
    changed = 0
    for row in rows:
        video = row.get('video')
        if not video:
            continue
        for gender, url in list(video.items()):
            fixed = encode(url)
            if fixed != url:
                video[gender] = fixed
                changed += 1

    CATALOG.write_text(
        json.dumps(rows, ensure_ascii=False, indent=1) + '\n', 'utf-8')
    print(f'urls rewritten: {changed}')


if __name__ == '__main__':
    main()
