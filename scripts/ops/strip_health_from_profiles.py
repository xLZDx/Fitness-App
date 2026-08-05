# -*- coding: utf-8 -*-
"""H1b, server half -- delete the health block from every stored profile.

WHY THIS EXISTS

H1a stopped the app writing health answers to `users/{uid}/profile/main`, and
the client-side migration in `DeviceHealthProfileRepository._resolve` moves an
existing block down to the device the next time its owner opens the app.

That covers everyone who comes back. It covers nobody who does not. An account
whose owner never launches the app again keeps its medications, surgeries and
reported injuries in Firestore forever, and "we do not store health data" is
false for as long as one of them is there -- which is the difference between a
true Data safety declaration and a false one.

This script closes that gap in one pass. It is the piece that lets H1c change
the Privacy Policy honestly.

WHAT IT TOUCHES

For each `profile` document anywhere under `users/`, it deletes these fields
and nothing else:

    health              -- conditions, allergies, medications, injuries,
                           physical limitations, recent surgeries, blood
                           pressure, free-text concerns
    lifestyle.smoking
    lifestyle.alcohol

Height, weight, goals, level, equipment and motivation are left alone. They are
Play "Fitness info", not "Health info"; removing them would remove no row from
the form and would cost the profile summary its device-to-device sync.

The fields are DELETED, not blanked -- a Firestore PATCH naming a field in
`updateMask` and omitting it from the body removes it. A blanked map would
leave an empty shell that reads, to anyone auditing later, like a field the app
still maintains.

DATA HYGIENE

Values are never printed. Not to stdout, not to a log. The whole point of the
exercise is that these answers stop being visible to the operator, and a script
that dumps them into a terminal buffer on the way out defeats it. Output is
counts and document paths only.

USAGE

    python scripts/ops/strip_health_from_profiles.py                       # dry run
    python scripts/ops/strip_health_from_profiles.py --apply               # writes
    python scripts/ops/strip_health_from_profiles.py --project legacy-shared

Dry run is the default because this deletes production user data. Run it first,
read the count, and only then pass --apply.

`--project legacy-shared` is where the work actually is: the app lived in
`traidingbot-b4061` before it got its own project, and 14 profiles are still
there. That project also holds an unrelated system's data -- this script only
ever touches documents in a `profile` collection under `users/`, and only ever
the three field paths below, but aim it deliberately.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from firebase_api import access_token, api  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]

# The fields to remove, as Firestore field paths.
TARGET_PATHS = ('health', 'lifestyle.smoking', 'lifestyle.alcohol')


def project_id(alias: str) -> str:
    """Resolve a .firebaserc alias rather than hard-coding a project.

    `firebase_api.PROJECT` is still `traidingbot-b4061`, and hard-coding here
    would eventually point a destructive script at the wrong database. The file
    that already decides where `firebase deploy` writes is the one honest
    source.

    Two aliases matter, and the second is the reason this takes an argument at
    all. Measured 2026-08-05: `default` (fitness-app-korostelev) holds ZERO
    profile documents, while `legacy-shared` (traidingbot-b4061, where this app
    lived before it got its own project) holds 14, every one of them carrying
    the full health block plus smoking and alcohol.

    Those 14 are unreachable by the client-side migration -- the app points at
    the new project now, so it will never read them again. A script is the only
    thing that can clear them, and it has to be aimed deliberately.
    """
    rc = json.loads((REPO_ROOT / '.firebaserc').read_text('utf-8'))
    projects = rc['projects']
    if alias not in projects:
        sys.exit(f'unknown alias {alias!r}; .firebaserc has: '
                 + ', '.join(sorted(projects)))
    return projects[alias]


def documents_root(project: str) -> str:
    return (f'https://firestore.googleapis.com/v1/projects/{project}'
            '/databases/(default)/documents')


def find_profiles(project: str, token: str) -> list[dict]:
    """Every `profile` document under any parent, via a collection-group query.

    A plain list of `users` would miss accounts whose parent document does not
    exist -- Firestore happily holds `users/{uid}/profile/main` with no
    `users/{uid}` document above it, and this app creates exactly that shape.
    Those are precisely the documents a migration must not skip.
    """
    out: list[dict] = []
    page_token = None
    while True:
        body = {
            'structuredQuery': {
                'from': [{'collectionId': 'profile', 'allDescendants': True}],
            }
        }
        url = f'{documents_root(project)}:runQuery'
        if page_token:
            body['structuredQuery']['startAt'] = page_token
        res = api(url, token, method='POST', payload=body)
        if isinstance(res, dict) and '_httpError' in res:
            sys.exit(f'query failed HTTP {res["_httpError"]}: {res["_body"]}')
        rows = [r['document'] for r in res if isinstance(r, dict) and 'document' in r]
        out.extend(rows)
        # runQuery returns the whole result set for a query this small; there
        # is no continuation token in the REST shape. Looping once is correct
        # and the break is explicit so a future reader does not assume paging
        # was forgotten.
        break
    return out


def has_target_fields(doc: dict) -> bool:
    """True when the document still carries anything this script removes.

    Presence, not truthiness: a `health` map that exists but is empty is still
    a field the app should no longer be maintaining, and leaving it behind
    would make the next audit ambiguous.
    """
    fields = doc.get('fields', {})
    if 'health' in fields:
        return True
    lifestyle = fields.get('lifestyle', {}).get('mapValue', {}).get('fields', {})
    return 'smoking' in lifestyle or 'alcohol' in lifestyle


def strip(project: str, token: str, name: str) -> str | None:
    """Delete the target fields from one document. Returns an error, or None."""
    mask = '&'.join(f'updateMask.fieldPaths={p}' for p in TARGET_PATHS)
    url = f'https://firestore.googleapis.com/v1/{name}?{mask}'
    res = api(url, token, method='PATCH', payload={'fields': {}})
    if isinstance(res, dict) and '_httpError' in res:
        return f'HTTP {res["_httpError"]}: {res["_body"][:200]}'
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--apply', action='store_true',
                    help='actually delete; without it nothing is written')
    ap.add_argument('--project', default='default',
                    help='.firebaserc alias to target: default (the app\'s own '
                         'project) or legacy-shared (where 14 pre-move '
                         'profiles still sit). Defaults to the safe one.')
    args = ap.parse_args()

    project = project_id(args.project)
    token = access_token()
    print(f'project: {project}')
    print(f'mode:    {"APPLY -- will delete" if args.apply else "dry run"}')
    print()

    docs = find_profiles(project, token)
    stale = [d for d in docs if has_target_fields(d)]

    print(f'profile documents found:        {len(docs)}')
    print(f'still carrying health fields:   {len(stale)}')

    if not stale:
        print('\nnothing to do -- no stored profile carries the health block.')
        return

    if not args.apply:
        print('\nwould delete ' + ', '.join(TARGET_PATHS) + ' from:')
        for d in stale:
            print('  ' + d['name'].split('/documents/')[-1])
        print('\nre-run with --apply to perform the deletion.')
        return

    failed = 0
    for d in stale:
        err = strip(project, token, d['name'])
        path = d['name'].split('/documents/')[-1]
        if err:
            failed += 1
            print(f'  FAILED {path}  {err}')
        else:
            print(f'  cleared {path}')

    print(f'\ncleared {len(stale) - failed} of {len(stale)}; {failed} failed.')
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
