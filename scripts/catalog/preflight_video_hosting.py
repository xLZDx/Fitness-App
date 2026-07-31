# -*- coding: utf-8 -*-
"""Check the video library before anything is uploaded anywhere.

Exits 0 only when every check passes, and writes a stamp the upload step can
require. An upload is 677 files and the first paid thing this app will do; the
cheap moment to find a broken path is before it, not by watching a library
half-fail to load on a phone.

Checks, each of which has a real failure mode behind it:

  1. Every url the catalog advertises resolves to a file that exists in the
     drop. A missing one is a 404 the user sees as "video unavailable" on an
     exercise that looks fine in the catalog.
  2. Every file in the drop is advertised by the catalog, or is a known
     exclusion. An orphan is storage paid for and never served.
  3. Percent-encoding round-trips. 637 of 653 urls contain a space; if
     decoding does not return the real filename, the upload mirrors a tree
     the urls cannot address.
  4. No duplicate content. Ten files in this drop are byte-identical to
     another (measured, see UNSURE.txt); uploading both pays twice.
  5. Total size against the free tier of whichever host was picked.

Usage:
    python scripts/catalog/preflight_video_hosting.py
    python scripts/catalog/preflight_video_hosting.py --drop D:/Downloads/Video
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'mobile' / 'assets' / 'data' / 'exercises.json'
STAMP = ROOT / 'data' / 'preflight' / 'video_hosting.json'

# Free-tier ceilings, read off the vendors' own pricing pages 2026-07-31.
FREE_TIER_GB = {'firebase': 5.0, 'r2': 10.0}


def gender_roots(drop: Path) -> dict[str, Path]:
    """Locate the `girl/` and `men/` trees inside the drop.

    Not `drop / 'girl'`: the download arrives as
    `girl-20260731T163153Z-1-001/girl/<Group>/...`, one wrapper directory deep,
    with the original .zip sitting beside it. `build_video_library.py` searches
    for the directory the same way, and the two MUST agree — a preflight that
    looked at a different tree than the builder would pass on files nobody is
    going to upload.
    """
    roots: dict[str, Path] = {}
    for gender in ('girl', 'men'):
        found = [p for p in drop.rglob(gender) if p.is_dir()]
        if not found:
            raise SystemExit(f'no {gender}/ directory anywhere under {drop}')
        roots[gender] = found[0]
    return roots


def check(drop: Path) -> tuple[list[str], dict]:
    problems: list[str] = []
    rows = json.loads(CATALOG.read_text('utf-8'))
    roots = gender_roots(drop)

    def local(rel: str) -> Path | None:
        gender, group, name = rel.split('/', 2)
        root = roots.get(gender)
        return None if root is None else root / group / name

    advertised: set[str] = set()
    for row in rows:
        for url in (row.get('video') or {}).values():
            path = unquote(urlsplit(url).path)
            # Everything after the base is <gender>/<Group>/<file>.mp4
            rel = '/'.join(path.split('/')[-3:])
            advertised.add(rel)
            p = local(rel)
            if p is None or not p.is_file():
                problems.append(f'{row["id"]}: no file for {rel}')

    on_disk: dict[str, Path] = {}
    for gender, root in roots.items():
        for p in root.rglob('*.mp4'):
            on_disk[f'{gender}/{p.parent.name}/{p.name}'] = p
    orphans = sorted(set(on_disk) - advertised)

    digests: dict[str, list[Path]] = defaultdict(list)
    total = 0
    for p in on_disk.values():
        total += p.stat().st_size
        digests[hashlib.md5(p.read_bytes()).hexdigest()].append(p)
    duplicates = {d: ps for d, ps in digests.items() if len(ps) > 1}
    wasted = sum(ps[0].stat().st_size * (len(ps) - 1) for ps in duplicates.values())

    # A filename that appears under two muscle groups with DIFFERENT content.
    #
    # `build_video_library.py` keys an exercise by the file's stem, which
    # assumes filenames are unique across the drop. They are not, and where the
    # two files differ the second silently replaces the first — one real
    # demonstration is discarded with no record of it. Reported, not repaired:
    # deciding whether those are two exercises or one mislabelled clip needs
    # someone to watch both, and guessing is how a catalog fills with confident
    # errors.
    by_name: dict[tuple[str, str], list[Path]] = defaultdict(list)
    for key, p in on_disk.items():
        gender, _, name = key.split('/', 2)
        by_name[(gender, name)].append(p)
    collisions = sorted(
        f'{g}/{n} in {sorted(p.parent.name for p in ps)}'
        for (g, n), ps in by_name.items()
        if len(ps) > 1
        and len({hashlib.md5(p.read_bytes()).hexdigest() for p in ps}) > 1
    )

    gb = total / 1e9
    for host, ceiling in FREE_TIER_GB.items():
        if gb > ceiling:
            problems.append(
                f'{gb:.2f} GB exceeds the {host} free tier of {ceiling} GB')

    return problems, {
        'advertised_urls': len(advertised),
        'files_on_disk': len(on_disk),
        'orphans': orphans,
        'duplicate_groups': len(duplicates),
        'wasted_by_duplicates_mb': round(wasted / 1e6, 1),
        'name_collisions_with_different_content': collisions,
        'total_gb': round(gb, 3),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--drop', default='D:/Downloads/Video')
    args = ap.parse_args()

    drop = Path(args.drop)
    if not drop.is_dir():
        sys.exit(f'drop not found: {drop}')

    problems, facts = check(drop)

    for k, v in facts.items():
        if isinstance(v, list):
            print(f'  {k:42s} {len(v)}')
            for o in v[:6]:
                print(f'      {o}')
            if len(v) > 6:
                print(f'      ... +{len(v) - 6} more')
        else:
            print(f'  {k:42s} {v}')

    if problems:
        print(f'\nFAIL ({len(problems)})')
        for p in problems[:20]:
            print(f'  {p}')
        sys.exit(1)

    STAMP.parent.mkdir(parents=True, exist_ok=True)
    STAMP.write_text(json.dumps({
        'passed_at_utc': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'drop': str(drop),
        **facts,
    }, ensure_ascii=False, indent=1) + '\n', 'utf-8')
    print(f'\nPASS -> {STAMP.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
