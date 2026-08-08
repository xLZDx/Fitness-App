# -*- coding: utf-8 -*-
"""Talk to Google's APIs using the credentials the Firebase CLI already holds.

WHY THIS EXISTS

Uploading the exercise library needs an authenticated call to Cloud Storage,
and there are three ways to get one:

  * `gcloud auth login` — opens a browser and waits for a human to click.
  * a downloaded service-account key — a long-lived secret sitting on disk,
    for a job that does not need one.
  * the refresh token the Firebase CLI already stored when the operator logged
    in. Same account, same scopes, already granted, nothing new to keep safe.

This is the third. It is what `firebase-tools` itself does on every command.

THE TOKEN IS NEVER PRINTED. Not to stdout, not into an argv, not into a log.
Callers get it as a return value and pass it in a header. That rule is the
whole reason this is a module and not four lines inlined into each script.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG = Path.home() / '.config' / 'configstore' / 'firebase-tools.json'

# The Firebase CLI's own OAuth client. Public constants, compiled into every
# copy of the open-source tool — not a secret, and not the operator's.
CLIENT_ID = ('563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6'
             '.apps.googleusercontent.com')
CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi'
TOKEN_URL = 'https://oauth2.googleapis.com/token'


def access_token() -> str:
    """A fresh access token. Never log the return value."""
    if not CONFIG.is_file():
        sys.exit(f'no Firebase CLI credentials at {CONFIG} — run `firebase login`')
    refresh = json.loads(CONFIG.read_text('utf-8'))['tokens']['refresh_token']
    body = urllib.parse.urlencode({
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=body)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)['access_token']


def api(url: str, token: str, method: str = 'GET', payload: dict | None = None,
        raw: bytes | None = None, content_type: str | None = None):
    """One JSON call. Returns the parsed body, or the HTTP error's body."""
    data = raw if raw is not None else (
        json.dumps(payload).encode() if payload is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', f'Bearer {token}')
    if content_type:
        req.add_header('Content-Type', content_type)
    elif payload is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read().decode('utf-8', 'replace')
            return json.loads(text) if text.strip() else {}
    except urllib.error.HTTPError as e:
        return {'_httpError': e.code,
                '_body': e.read().decode('utf-8', 'replace')[:600]}


def _default_project() -> str:
    """The project `firebase deploy` targets, read from the same file it reads.

    This was the literal string `'traidingbot-b4061'` until 2026-08-08, and
    every ops script imports it. The repo moved to `fitness-app-korostelev`;
    `.firebaserc` was updated, the CLI followed it, and these scripts did not.
    `verify_clip_signing.py` was calling functions in a project that has none,
    and scored 6/9 while doing it -- its rejection checks read HTTP 404 as
    "refused", which a wrong hostname produces for free. A stale project
    constant does not fail loudly; it passes quietly.

    Reading `.firebaserc` means the scripts and the CLI cannot disagree again.
    `FIREBASE_PROJECT` overrides for a one-off against another project, and a
    missing/unparsable file is fatal rather than defaulted -- guessing which
    project to mutate is precisely the mistake this replaces.
    """
    env = os.environ.get('FIREBASE_PROJECT') or os.environ.get('GCLOUD_PROJECT')
    if env:
        return env
    rc = Path(__file__).resolve().parents[2] / '.firebaserc'
    if not rc.is_file():
        sys.exit(f'no .firebaserc at {rc} -- set FIREBASE_PROJECT explicitly')
    try:
        return json.loads(rc.read_text('utf-8'))['projects']['default']
    except (ValueError, KeyError) as e:
        sys.exit(f'{rc} has no projects.default ({e}) -- set FIREBASE_PROJECT')


PROJECT = _default_project()

# The project the app was built in before the move. Named so that a script
# which genuinely means the old one says so, instead of relying on [PROJECT]
# happening to still point there.
LEGACY_PROJECT = 'traidingbot-b4061'


def main() -> None:
    t = access_token()
    print('project')
    info = api(f'https://firebase.googleapis.com/v1beta1/projects/{PROJECT}', t)
    for k in ('projectId', 'state', 'resources'):
        if k in info:
            print(f'  {k}: {info[k]}')
    if '_httpError' in info:
        print(f'  ERROR {info["_httpError"]}: {info["_body"][:200]}')

    print('\nstorage buckets known to Firebase')
    b = api(f'https://firebasestorage.googleapis.com/v1beta/projects/{PROJECT}'
            '/buckets', t)
    if '_httpError' in b:
        print(f'  ERROR {b["_httpError"]}: {b["_body"][:300]}')
    else:
        for bucket in b.get('buckets', []) or []:
            print(f'  {bucket.get("name")}')
        if not b.get('buckets'):
            print('  (none)')

    print('\nGCS buckets in the project')
    g = api('https://storage.googleapis.com/storage/v1/b'
            f'?project={PROJECT}&fields=items(name,location,storageClass)', t)
    if '_httpError' in g:
        print(f'  ERROR {g["_httpError"]}: {g["_body"][:300]}')
    else:
        for bucket in g.get('items', []) or []:
            print(f'  {bucket["name"]}  {bucket.get("location")}  '
                  f'{bucket.get("storageClass")}')
        if not g.get('items'):
            print('  (none)')


if __name__ == '__main__':
    main()
