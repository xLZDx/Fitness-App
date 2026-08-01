# -*- coding: utf-8 -*-
"""Cut a still from the first moment of every clip, and bundle it in the APK.

WHY A BUNDLED POSTER AND NOT A HOSTED ONE

The operator, watching a screen recording of the catalog: *"видео загружается
за секунды, но мы договаривались что превью картинка будет сразу а видео
подтягивать потом, но этого нет если нет интернета то даже изначальной
картинки не будет"*.

Both halves of that are real, and they have different causes. The video block
showed a spinner because it had nothing else to show: the 343 exercises that
carry a clip have empty `frames` and empty `imageUrls`, so there was no still
in the catalog to put up first. And the 106 exercises that DO have stills hold
them as `imageUrls` — network images — so with no connection those render as
"demo unavailable" rather than as a picture.

Hosting posters next to the videos would fix the first and not the second. So
they ship inside the app instead. That is affordable here in a way it usually
is not: these clips are 3D renders on a flat white background, which JPEG
compresses to about 4 KB at 400 px. All 677 come to roughly 4 MB against a
90 MB APK — a 4% cost to make the first frame instant, free, and available
with the phone in aeroplane mode.

WHY 0.5 SECONDS IN

Frame zero of these renders is often the model standing still before the
movement starts, and on a few it is a blank white flash. Half a second in is
past that on every clip sampled and still the start of the repetition, which
is the frame the poster should show — the position the user is about to see
the video move away from.
"""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'mobile' / 'assets' / 'data' / 'exercises.json'
POSTERS = ROOT / 'mobile' / 'assets' / 'posters'
DROP = Path('D:/Downloads/Video')

WIDTH = 400
QUALITY = 5  # ffmpeg -q:v, 2 best .. 31 worst


def gender_roots() -> dict[str, Path]:
    """Locate `girl/` and `men/` the same way the upload does.

    Located rather than assumed: the drop unzips into dated wrapper
    directories, and hard-coding one would break the next time a library
    arrives.
    """
    roots = {}
    for gender in ('girl', 'men'):
        found = [p for p in DROP.rglob(gender) if p.is_dir()]
        if not found:
            sys.exit(f'no {gender}/ under {DROP}')
        roots[gender] = found[0]
    return roots


def local_for(url: str, roots: dict[str, Path]) -> Path | None:
    """The file on disk that [url] was uploaded from.

    The catalog stores percent-encoded urls; the drop has the raw names, most
    of which contain spaces and some of which contain brackets. Decoding is
    the whole job, and getting it wrong is silent — a missing poster, not an
    error — so the caller counts what came back None.
    """
    path = urllib.parse.urlparse(url).path
    parts = [urllib.parse.unquote(p) for p in path.split('/') if p]
    # .../exercises/<gender>/<Group>/<file>.mp4
    if 'exercises' not in parts:
        return None
    i = parts.index('exercises')
    rest = parts[i + 1:]
    if len(rest) != 3:
        return None
    gender, group, name = rest
    root = roots.get(gender)
    if root is None:
        return None
    candidate = root / group / name
    return candidate if candidate.exists() else None


def main() -> None:
    rows = json.loads(CATALOG.read_text(encoding='utf-8'))
    roots = gender_roots()

    made = skipped = missing = 0
    for row in rows:
        video = row.get('video') or {}
        if not video:
            continue
        poster: dict[str, str] = {}
        for gender, url in sorted(video.items()):
            src = local_for(url, roots)
            if src is None:
                missing += 1
                continue
            rel = f'assets/posters/{gender}/{row["id"]}.jpg'
            dst = ROOT / 'mobile' / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                poster[gender] = rel
                skipped += 1
                continue
            r = subprocess.run(
                ['ffmpeg', '-v', 'error', '-ss', '0.5', '-i', str(src),
                 '-frames:v', '1', '-vf', f'scale={WIDTH}:-2',
                 '-q:v', str(QUALITY), str(dst), '-y'],
                capture_output=True, text=True)
            if r.returncode != 0 or not dst.exists():
                missing += 1
                print(f'  FAILED {row["id"]}/{gender}: {r.stderr.strip()[:120]}')
                continue
            poster[gender] = rel
            made += 1
        if poster:
            row['poster'] = poster

    CATALOG.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    total = sum(f.stat().st_size for f in POSTERS.rglob('*.jpg'))
    with_poster = len([r for r in rows if r.get('poster')])
    print(f'\ncut {made}, already present {skipped}, could not locate {missing}')
    print(f'{with_poster} exercises now carry a poster')
    print(f'{len(list(POSTERS.rglob("*.jpg")))} files, {total / 1048576:.2f} MB')


if __name__ == '__main__':
    main()
