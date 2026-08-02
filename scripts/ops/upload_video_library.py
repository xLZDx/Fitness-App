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

import argparse
import concurrent.futures
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from firebase_api import access_token, api  # noqa: E402

BUCKET = 'traidingbot-b4061-videos-eu'
DROP = Path('D:/Downloads/Video')
PREFIX = 'exercises'

# The licensed library. Its tree is already laid out under the object keys it
# will be served from -- see `scripts/catalog/bundle_layout.py` -- so it needs
# no gender-root discovery, unlike the drop, which arrives inside dated
# wrapper directories.
LICENSED_BUCKET = 'traidingbot-b4061-videos-private'
LICENSED_TREE = Path('D:/bundle/720')


def gender_roots(drop: Path) -> dict[str, Path]:
    roots = {}
    for gender in ('girl', 'men'):
        found = [p for p in drop.rglob(gender) if p.is_dir()]
        if not found:
            sys.exit(f'no {gender}/ under {drop}')
        roots[gender] = found[0]
    return roots


def existing(token: str, bucket: str = BUCKET) -> dict[str, int]:
    """Object name -> size, for everything already in the bucket."""
    out: dict[str, int] = {}
    page = None
    while True:
        url = (f'https://storage.googleapis.com/storage/v1/b/{bucket}/o'
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


def upload(local: Path, name: str, token: str, bucket: str) -> tuple[str, str]:
    url = ('https://storage.googleapis.com/upload/storage/v1/b/'
           f'{bucket}/o?uploadType=media&name={urllib.parse.quote(name, safe="")}')
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
    ap = argparse.ArgumentParser()
    ap.add_argument('--licensed', action='store_true',
                    help='upload the purchased library to the private bucket')
    args = ap.parse_args()

    bucket = LICENSED_BUCKET if args.licensed else BUCKET
    token = access_token()

    wanted: dict[str, Path] = {}
    if args.licensed:
        if not LICENSED_TREE.is_dir():
            sys.exit(f'no transcoded library at {LICENSED_TREE}')
        for p in sorted(LICENSED_TREE.rglob('*.mp4')):
            key = p.relative_to(LICENSED_TREE).as_posix()
            # Anything not yet a finished clip. A `.partial.mp4` is an encode in
            # flight and a `_scratch/` entry is a source copy about to be
            # deleted; uploading either publishes a truncated video, and both
            # can vanish between the glob and the read.
            if key.endswith('.partial.mp4') or key.startswith('_'):
                continue
            # The path under the tree IS the object key; that is the point of
            # laying it out this way. Rebuilding the key from parts here would
            # be a second implementation of the naming policy, free to drift.
            wanted[key] = p
    else:
        for gender, root in gender_roots(DROP).items():
            for p in sorted(root.rglob('*.mp4')):
                wanted[f'{PREFIX}/{gender}/{p.parent.name}/{p.name}'] = p
    print(f'bucket: {bucket}')
    print(f'local files: {len(wanted)}')

    have = existing(token, bucket)
    todo = {}
    for name, path in wanted.items():
        try:
            size = path.stat().st_size
        except OSError:
            # Raced with a still-running transcode. Not fatal: the next run
            # picks it up, and crashing here would abandon 2,000 good uploads.
            continue
        if have.get(name) != size:
            todo[name] = path
    print(f'already uploaded and the right size: {len(wanted) - len(todo)}')
    print(f'to upload: {len(todo)}')
    if not todo:
        print('nothing to do')
        return

    done = failed = 0
    errors: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(upload, p, n, token, bucket)
                   for n, p in todo.items()]
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
