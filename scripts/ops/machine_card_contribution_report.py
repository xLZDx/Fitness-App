# -*- coding: utf-8 -*-
"""Gate H / MRD-07 -- which unrecognised machine do we film next.

WHY THIS EXISTS

`MachineCard` (`mobile/lib/features/visual_equipment/data/machine_card.dart`)
already does the hard part: every time someone photographs equipment the
catalog has no page for, the app records it and folds repeat sightings of the
same machine into one row with a running count
(`machine_card_repository.dart`'s `MachineCardMerge`). That repository's own
doc comment says the point plainly: "`MachineCard.timesSeen` across users is
the only honest answer to 'which missing clip do we film first'."

Nothing reads that data back. Gate H's own reconnaissance (see
`core/product/GATE_H_CONTRIBUTION_MEASUREMENT_D0_NOTE_2026-08-19.md`) found
the collection-group read the repository's doc comment describes as possible
had never actually been built -- no script, no Cloud Function, no admin page.
This script is that read. Nothing more.

WHAT THIS DELIBERATELY DOES NOT DO

No write path, no scheduled job, no dashboard, no notification. Those all
need a decision this repo has no evidence for -- who looks at the numbers,
how often, and what to do when a card's content ships (nothing in the app
today ever moves a card out of `preparing`; see the D0 note). This script
answers the one question the data can honestly answer today: across every
user, what have people pointed a camera at that this app still has nothing
to say about, ranked by how often. What to do with that ranking is an
operator call, not a code change.

DATA HYGIENE

The report is an aggregate table: a machine name, a total sighting count, how
many distinct users contributed to it, first/last-seen dates. It never prints
a document path, a `uid`, or anything else that would tie a sighting to the
person who took it -- the whole per-user identity only exists here long
enough to be counted into "distinct users", then discarded. Same rule
`strip_health_from_profiles.py` follows for a different reason: this tool's
job is a shape of the data, not a look at who is behind it.

USAGE

    python scripts/ops/machine_card_contribution_report.py
    python scripts/ops/machine_card_contribution_report.py --project legacy-shared
    python scripts/ops/machine_card_contribution_report.py --top 10
    python scripts/ops/machine_card_contribution_report.py --include-resolved

Read-only. There is no `--apply` because there is nothing this script writes.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from firebase_api import access_token, api  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]


def project_id(alias: str) -> str:
    """Resolve a `.firebaserc` alias -- same lookup `strip_health_from_profiles.py`
    uses, for the same reason: the file that already decides where `firebase
    deploy` writes is the one honest source, and a hard-coded project id has
    gone stale here before (`firebase_api.py`'s own doc comment)."""
    rc = json.loads((REPO_ROOT / '.firebaserc').read_text('utf-8'))
    projects = rc['projects']
    if alias not in projects:
        sys.exit(f'unknown alias {alias!r}; .firebaserc has: '
                 + ', '.join(sorted(projects)))
    return projects[alias]


def documents_root(project: str) -> str:
    return (f'https://firestore.googleapis.com/v1/projects/{project}'
            '/databases/(default)/documents')


def find_machine_card_docs(project: str, token: str) -> list[dict]:
    """Every `machine_cards` document under any user, via a collection-group
    query -- the exact mechanism `firestore_machine_cards.dart`'s own doc
    comment describes as possible, run for the first time.

    `select` limits the fields Firestore returns to the ones this report
    actually reads. `recognisedAs`/`confidence` (the model's raw guess) and
    `uses` (free-text exercise names) never cross the wire at all, rather
    than arriving and being discarded after decode (security review,
    least-fetch discipline)."""
    body = {
        'structuredQuery': {
            'from': [{'collectionId': 'machine_cards', 'allDescendants': True}],
            'select': {'fields': [
                {'fieldPath': p} for p in
                ('id', 'name', 'timesSeen', 'status', 'firstSeenAt', 'lastSeenAt')
            ]},
        }
    }
    url = f'{documents_root(project)}:runQuery'
    res = api(url, token, method='POST', payload=body)
    if isinstance(res, dict) and '_httpError' in res:
        sys.exit(f'query failed HTTP {res["_httpError"]}: {res["_body"]}')
    return [r['document'] for r in res if isinstance(r, dict) and 'document' in r]


def _decode_value(v: dict):
    """Decode one Firestore REST `Value` into a plain Python value. Handles
    the shapes `MachineCard.toJson()` writes plus `timestampValue` -- the
    shape its own repository's read side (`firestore_machine_cards.dart`'s
    `machineCardFromFirestore`) documents as a real possibility for
    `firstSeenAt`/`lastSeenAt`: "what a console edit or a server-side write
    produces" -- not the full REST value union (python-reviewer finding)."""
    if 'stringValue' in v:
        return v['stringValue']
    if 'integerValue' in v:
        return int(v['integerValue'])
    if 'doubleValue' in v:
        return float(v['doubleValue'])
    if 'booleanValue' in v:
        return bool(v['booleanValue'])
    if 'timestampValue' in v:
        # Firestore REST timestamps are already RFC3339/ISO-8601 strings
        # (e.g. "2026-08-01T00:00:00.123456Z") -- the same shape the app's
        # own writes use, so no conversion is needed to compare them.
        return v['timestampValue']
    if 'nullValue' in v:
        return None
    if 'arrayValue' in v:
        return [_decode_value(x) for x in v['arrayValue'].get('values', [])]
    if 'mapValue' in v:
        return {k: _decode_value(x) for k, x in v['mapValue'].get('fields', {}).items()}
    return None


def parse_card_doc(doc: dict) -> dict | None:
    """A document's `fields` plus the uid its path carries, as a plain dict.
    Returns None for a document missing the fields this report needs -- a
    partially-written or hand-edited row is skipped, not guessed at.

    The uid is extracted ONLY to be counted into a per-card distinct-user
    set by the caller; nothing downstream of `aggregate()` ever sees it
    again, and this function itself never prints it. `users/{uid}/machine_cards/{id}`
    is the fixed shape `firestore_machine_cards.dart` writes.
    """
    fields = {k: _decode_value(v) for k, v in doc.get('fields', {}).items()}
    card_id = fields.get('id')
    name = fields.get('name')
    times_seen = fields.get('timesSeen')
    if not isinstance(card_id, str) or not card_id:
        return None
    if not isinstance(name, str) or not name:
        return None
    # `bool` is a subclass of `int` in Python -- without excluding it here, a
    # hand-edited document storing `timesSeen` as a Firestore boolean would
    # silently pass validation and contribute a phantom sighting instead of
    # being skipped as malformed (python-reviewer finding).
    if not isinstance(times_seen, int) or isinstance(times_seen, bool):
        return None
    path_parts = doc.get('name', '').split('/documents/')[-1].split('/')
    uid = path_parts[1] if len(path_parts) > 1 and path_parts[0] == 'users' else None
    if uid is None:
        return None
    return {
        'id': card_id,
        'name': name,
        'timesSeen': times_seen,
        'status': fields.get('status') or 'preparing',
        'firstSeenAt': fields.get('firstSeenAt'),
        'lastSeenAt': fields.get('lastSeenAt'),
        'uid': uid,
    }


@dataclass
class ContributionRow:
    """One machine, aggregated across every user who has photographed it."""
    id: str
    name: str
    total_sightings: int = 0
    distinct_users: set[str] = field(default_factory=set, repr=False)
    statuses: set[str] = field(default_factory=set, repr=False)
    first_seen_at: str | None = None
    last_seen_at: str | None = None

    @property
    def distinct_user_count(self) -> int:
        return len(self.distinct_users)

    @property
    def is_still_unresolved(self) -> bool:
        """True unless every recorded sighting agrees the card has moved past
        `preparing`. Storage is per-user (`users/{uid}/machine_cards/{id}`),
        so two different users' copies of "the same machine" (by id) are two
        separate documents that could in principle disagree -- excluding a
        machine from the report needs a positive signal that content now
        exists, not merely the absence of one specific `preparing` row.
        Nothing in the shipped app ever writes a status other than
        `preparing` today (Gate H's own reconnaissance), so in practice this
        is always true; the check stays honest for the day that changes
        rather than assuming it never will."""
        return 'preparing' in self.statuses


def _earlier(a: str | None, b: str | None) -> str | None:
    """Whichever of two optional ISO timestamp strings comes first. A string
    that fails to parse is treated as incomparable and loses to any string
    that does parse, rather than crashing or silently winning by accident."""
    da, db = _parse_iso(a), _parse_iso(b)
    if da is None:
        return b if db is not None else (a or b)
    if db is None:
        return a
    return a if da <= db else b


def _later(a: str | None, b: str | None) -> str | None:
    da, db = _parse_iso(a), _parse_iso(b)
    if da is None:
        return b if db is not None else (a or b)
    if db is None:
        return a
    return a if da >= db else b


def _parse_iso(s: str | None) -> datetime | None:
    """An ISO-8601 timestamp string as a comparable [datetime], or None.

    `aggregate()` used to compare these as raw strings. That is only safe
    when every string has the same fixed fractional-second width, which
    Dart's `toIso8601String()` does not guarantee: it prints milliseconds
    (3 digits) but appends microseconds (3 more) only when they are
    nonzero, so "...500Z" and "...500001Z" -- the same millisecond, a
    microsecond apart -- can compare backwards as plain strings (`'Z' >
    '0'` at the first divergent character). Parsing into a real [datetime]
    before comparing makes the ordering correct regardless of how many
    fractional digits either string carries (python-reviewer finding).
    """
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except ValueError:
        return None


def aggregate(cards: list[dict]) -> list[ContributionRow]:
    """Folds every user's sighting rows into one row per machine id, newest
    evidence first within a tie -- pure function, no I/O, so this is what
    `test_machine_card_contribution_report.py` actually exercises.

    Sightings for the same [ContributionRow.id] never collapse to fewer than
    the distinct users behind them: two people's `timesSeen` sum, but a
    user's own repeat scans (already deduped client-side by
    `MachineCardMerge`, `machine_card_repository.dart`) only ever contribute
    once to `distinct_users` regardless of how high their own count runs, so
    one very enthusiastic photographer cannot make a machine look more
    widely-wanted than it is.
    """
    rows: dict[str, ContributionRow] = {}
    for c in cards:
        row = rows.get(c['id'])
        if row is None:
            row = ContributionRow(id=c['id'], name=c['name'])
            rows[c['id']] = row
        row.total_sightings += c['timesSeen']
        row.distinct_users.add(c['uid'])
        row.statuses.add(c['status'])
        # Compared as parsed datetimes (see _parse_iso/_earlier/_later),
        # stored as the original string.
        row.first_seen_at = _earlier(row.first_seen_at, c['firstSeenAt'])
        row.last_seen_at = _later(row.last_seen_at, c['lastSeenAt'])
    return sorted(
        rows.values(),
        key=lambda r: (-r.total_sightings, -r.distinct_user_count, r.name),
    )


_NAME_WIDTH = 32


def _display_name(name: str) -> str:
    """Truncated for the fixed-width table, with a visible marker when it
    was cut -- otherwise two machines whose names agree for the first 32
    characters (plausible for verbose vision-model-generated descriptions)
    would print as identical rows with no signal they're actually different
    (python-reviewer finding). A trailing `~` is not part of the real name;
    `aggregate()` itself always keys on the untruncated id, never this
    string, so display truncation never affects the ranking."""
    if len(name) <= _NAME_WIDTH:
        return name
    return name[:_NAME_WIDTH - 1] + '~'


def render(rows: list[ContributionRow], top: int) -> str:
    lines = [
        f'{"machine":<32} {"sightings":>9} {"users":>6} {"first seen":<12} {"last seen":<12}',
        '-' * 75,
    ]
    for row in rows[:top]:
        lines.append(
            f'{_display_name(row.name):<32} {row.total_sightings:>9} {row.distinct_user_count:>6} '
            f'{(row.first_seen_at or "")[:10]:<12} {(row.last_seen_at or "")[:10]:<12}'
        )
    return '\n'.join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', default='default',
                    help='.firebaserc alias to read from. Defaults to the '
                         "app's own project.")
    ap.add_argument('--top', type=int, default=25,
                    help='how many rows to print, most-photographed first '
                         '(default 25)')
    ap.add_argument('--include-resolved', action='store_true',
                    help='also list machines whose every sighting on record '
                         'is already inCatalog/declined -- excluded by '
                         'default since those no longer need filming')
    args = ap.parse_args()

    project = project_id(args.project)
    token = access_token()
    print(f'project: {project}')
    print()

    docs = find_machine_card_docs(project, token)
    parsed = [c for c in (parse_card_doc(d) for d in docs) if c is not None]
    skipped = len(docs) - len(parsed)
    rows = aggregate(parsed)
    if not args.include_resolved:
        rows = [r for r in rows if r.is_still_unresolved]

    print(f'machine_cards documents found:  {len(docs)}')
    if skipped:
        print(f'skipped (missing required fields): {skipped}')
    print(f'distinct unrecognised machines:  {len(rows)}')
    print()

    if not rows:
        print('nothing to report -- no unresolved machine cards found.')
        return

    print(render(rows, args.top))
    if len(rows) > args.top:
        print(f'\n... and {len(rows) - args.top} more (--top to see more).')


if __name__ == '__main__':
    main()
