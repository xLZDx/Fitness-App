# -*- coding: utf-8 -*-
"""Upload the exercise clips, mirroring the drop's directory tree.

The object name has to be exactly what the catalog advertises:
`exercises/<gender>/<Group>/<file>.mp4`. The catalog's urls are that path
percent-encoded, so the two only agree if the upload reproduces the tree
character for character — which is why the gender roots are located the same
way `build_video_library.py` locates them, rather than assumed.

Re-runnable. Every object is checked by size before it is sent, so a second run
after a failure moves only what is missing instead of re-uploading 0.69 GB.

Content-Type matters more than it looks: an object served as
`application/octet-stream` makes some players download the whole file before
the first frame, and makes others refuse it. Every file here is video/mp4.
"""
from __future__ import annotations

import concurrent.futures
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from firebase_api import access_token, api  # noqa: E402

BUCKET = 'traidingbot-b4061-exercise-videos'
DROP = Path('D:/Downloads/Video')
PREFIX = 'exercises'


def gender_roots(drop: Path) -> dict[str, Path]:
    roots = {}
    for gender in ('girl', 'men'):
        found = [p for p in drop.rglob(gender) if p.is_dir()]
        if not found:
            sys.exit(f'no {gender}/ under {drop}')
        roots[gender] = found[0]
    return roots


def existing(token: str) -> dict[str, int]:
    """Object name -> size, for everything already in the bucket."""
    out: dict[str, int] = {}
    page = None
    while True:
        url = (f'https://storage.googleapis.com/storage/v1/b/{BUCKET}/o'
               f'?prefix={PREFIX}/&fields=items(name,size),nextPageToken'
               '&maxResults=1000')
        if page:
            url += f'&pageToken={page}'
        r = api(url, token)
        if '_httpError' in r:
            sys.exit(f'list failed {r["_httpError"]}: {r["_body"]}')
        for item in r.get('items', []) or []:
            out[item['name']] = int(item['size'])
        page = r.get('nextPageToken')
        if not page:
            return out


def upload(local: Path, name: str, token: str) -> tuple[str, str]:
    url = ('https://storage.googleapis.com/upload/storage/v1/b/'
           f'{BUCKET}/o?uploadType=media&name={urllib.parse.quote(name, safe="")}')
    req = urllib.request.Request(url, data=local.read_bytes(), method='POST')
    req.add_header('Authorization', f'Bearer {token}')
    req.add_header('Content-Type', 'video/mp4')
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            r.read()
        return name, ''
    except Exception as e:  # noqa: BLE001 - reported, not swallowed
        return name, str(e)[:160]


def main() -> None:
    token = access_token()
    roots = gender_roots(DROP)

    wanted: dict[str, Path] = {}
    for gender, root in roots.items():
        for p in sorted(root.rglob('*.mp4')):
            wanted[f'{PREFIX}/{gender}/{p.parent.name}/{p.name}'] = p
    print(f'local files: {len(wanted)}')

    have = existing(token)
    todo = {n: p for n, p in wanted.items()
            if have.get(n) != p.stat().st_size}
    print(f'already uploaded and the right size: {len(wanted) - len(todo)}')
    print(f'to upload: {len(todo)}')
    if not todo:
        print('nothing to do')
        return

    done = failed = 0
    errors: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(upload, p, n, token) for n, p in todo.items()]
        for f in concurrent.futures.as_completed(futures):
            name, err = f.result()
            if err:
                failed += 1
                errors.append(f'{name}: {err}')
            else:
                done += 1
            if (done + failed) % 50 == 0:
                print(f'  {done + failed}/{len(todo)}  ok={done} failed={failed}')

    print(f'\nuploaded {done}, failed {failed}')
    for e in errors[:10]:
        print(f'  {e}')
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
