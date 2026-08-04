# -*- coding: utf-8 -*-
"""Cross-reference the exercises we have no clip for against a vendor's list.

WHAT THIS IS FOR

Exercise Animatic offered to check our gap against their library before we buy.
Their exercise list is a single-column spreadsheet of 2,579 filenames; ours is
the 168 catalog rows carrying no `video`. Matching by hand is how you end up
paying for a bundle that misses the machines.

HOW IT MATCHES, AND WHY IT IS DELIBERATELY BLUNT

Three passes, most confident first, and every row is labelled with which pass
caught it so the answer can be audited rather than believed:

  exact   - normalised strings are identical
  subset  - every significant word of ours appears in theirs (a vendor name
            with extra qualifiers still demonstrates our movement)
  fuzzy   - Jaccard overlap of significant words at or above a threshold

Normalisation lowercases, strips punctuation, expands the abbreviations the two
sources disagree on (`db`/`dumbbell`, `bb`/`barbell`), and drops filler words.
It does NOT stem: `curl` and `curls` are handled by an explicit plural rule,
because a stemmer would also collapse `press` and `pressing` onto words that
mean different exercises here.

The fuzzy pass is reported SEPARATELY and never counted as covered. Its whole
job is to produce a short list a human can eyeball, not to inflate the number.
A vendor deciding what to sell and a buyer deciding what to pay should not be
reading the same optimistic count.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import vendor_paths  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'mobile' / 'assets' / 'data' / 'exercises.json'
VENDOR = vendor_paths.EXERCISE_LIST
# The richer workbook: names PLUS instructions, tips, muscles and equipment.
# Only ~1,500 of its 2,579 rows carry that metadata — the vendor says it is
# still being filled in by hand — so it supplements the name list rather than
# replacing it.
VENDOR_META = vendor_paths.VENDOR_META
REPORT_ALL = ROOT / 'core' / 'vendor_coverage_all_511.csv'
REPORT_GAP = ROOT / 'core' / 'vendor_coverage_gap_168.csv'

SYNONYMS = {
    'db': 'dumbbell', 'dbs': 'dumbbell', 'dumbbells': 'dumbbell',
    'bb': 'barbell', 'barbells': 'barbell',
    'kb': 'kettlebell', 'kettlebells': 'kettlebell',
    'ez': 'ezbar', 'abs': 'ab', 'abdominal': 'ab', 'abdominals': 'ab',
    'oblique': 'obliques', 'glute': 'glutes', 'hamstring': 'hamstrings',
    'legs': 'leg', 'arms': 'arm', 'knees': 'knee', 'shoulders': 'shoulder',
    'machines': 'machine', 'cables': 'cable', 'bands': 'band',
    'pullup': 'pull up', 'pullups': 'pull up', 'chinup': 'chin up',
    'pushup': 'push up', 'pushups': 'push up', 'situp': 'sit up',
    'situps': 'sit up', 'stepup': 'step up', 'lunges': 'lunge',
    'curls': 'curl', 'raises': 'raise', 'rows': 'row', 'squats': 'squat',
    'presses': 'press', 'extensions': 'extension', 'crunches': 'crunch',
    'twists': 'twist', 'stretches': 'stretch', 'flyes': 'fly', 'flys': 'fly',
    'deadlifts': 'deadlift', 'dips': 'dip', 'thrusts': 'thrust',
    # Equipment, where the two sources spell the same machine differently.
    'pulldown': 'pull down', 'plyo': 'plyometric', 'plyometric': 'box',
    'adjustable': 'bench', 'plates': 'plate', 'erg': 'ergometer',
    'abductor': 'abduction', 'adductor': 'adduction', 'ropes': 'rope',
    'recumbent': 'bike', 'stair': 'stairs',
}

# Words that carry no discriminating power between two exercise names.
FILLER = {
    'the', 'a', 'an', 'with', 'and', 'to', 'on', 'in', 'of', 'for', 'at',
    'or', 'your', 'you', 'up', 'out', 'degree', 'degrees', 'version',
    'variation', 'exercise', 'gym', 'fitness',
}


def norm(name: str) -> list[str]:
    s = name.lower()
    s = re.sub(r'\bfedb[_\s]+', ' ', s)      # our own import prefix
    s = re.sub(r'\bvid[_\s]+', ' ', s)
    s = re.sub(r'[_\-/]+', ' ', s)
    s = re.sub(r'[^a-z0-9 ]+', ' ', s)
    words: list[str] = []
    for w in s.split():
        w = SYNONYMS.get(w, w)
        words.extend(w.split())
    return [w for w in words if w and w not in FILLER]


def load_vendor() -> dict[str, set[str]]:
    """Vendor name -> its significant words. Gender suffixes stripped."""
    try:
        import openpyxl
    except ImportError:
        sys.exit('pip install openpyxl')
    ws = openpyxl.load_workbook(VENDOR, read_only=True)['Sheet1']
    out: dict[str, set[str]] = {}
    for (value,) in ws.iter_rows(min_row=2, values_only=True):
        if not value:
            continue
        base = re.sub(r'[_\s]+(male|female)\s*$', '', str(value), flags=re.I)
        out.setdefault(base.strip(), set()).update(norm(base))
    return out


def main() -> None:
    rows = json.loads(CATALOG.read_text(encoding='utf-8'))
    only_gap = '--gap' in sys.argv
    gap = [r for r in rows if not r.get('video')] if only_gap else rows
    report = REPORT_GAP if only_gap else REPORT_ALL
    vendor = load_vendor()
    vendor_exact = {' '.join(sorted(w)): n for n, w in vendor.items()}

    results = []
    for row in gap:
        ours = set(norm(row['title']))
        if not ours:
            results.append((row, 'none', '', 0.0))
            continue

        key = ' '.join(sorted(ours))
        if key in vendor_exact:
            results.append((row, 'exact', vendor_exact[key], 1.0))
            continue

        best_sub, best_fuzzy, best_score = None, None, 0.0
        for name, theirs in vendor.items():
            if not theirs:
                continue
            if ours <= theirs and best_sub is None:
                best_sub = name
            # Containment, not Jaccard. The question is "does the vendor have
            # something that demonstrates OUR exercise", so what matters is how
            # much of OUR name they cover — not how much extra detail their
            # filename carries. Jaccard punished exactly the right answers:
            # "Elliptical Trainer" vs "Gym Elliptical Machine Fast Speed"
            # scored 0.20 and was reported as no match.
            score = len(ours & theirs) / len(ours)
            if score > best_score:
                best_score, best_fuzzy = score, name

        if best_sub is not None:
            results.append((row, 'subset', best_sub, 1.0))
        elif best_score >= 0.66:
            results.append((row, 'likely', best_fuzzy, best_score))
        elif best_score >= 0.50:
            results.append((row, 'maybe', best_fuzzy, best_score))
        else:
            results.append((row, 'none', best_fuzzy or '', best_score))

    counts = {k: sum(1 for _, m, _, _ in results if m == k)
              for k in ('exact', 'subset', 'likely', 'maybe', 'none')}
    covered = counts['exact'] + counts['subset']

    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open('w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f)
        w.writerow(['id', 'our_title', 'equipmentId', 'muscles',
                    'match_kind', 'vendor_name', 'score'])
        for row, kind, name, score in sorted(
                results, key=lambda r: (r[1], r[0]['title'])):
            w.writerow([row['id'], row['title'], row.get('equipmentId') or '',
                        '|'.join(row.get('muscles', [])), kind, name,
                        f'{score:.2f}'])

    print(f'our gap:            {len(gap)}')
    print(f'vendor movements:   {len(vendor)}')
    print()
    print(f'  exact match:      {counts["exact"]}')
    print(f'  our name is a subset of theirs: {counts["subset"]}')
    print(f'  --> confidently covered: {covered} '
          f'({covered / len(gap) * 100:.0f}%)')
    print()
    print(f'  likely, worth eyeballing (>=0.66): {counts["likely"]}')
    print(f'  maybe (0.50-0.66):                 {counts["maybe"]}')
    print(f'  no plausible match:                {counts["none"]}')
    print(f'\nwritten: {report}')

    print('\nnot found at all — the part worth arguing about:')
    for row, kind, name, score in results:
        if kind == 'none':
            eq = row.get('equipmentId') or 'bodyweight'
            print(f'  {row["title"]}  [{eq}]  closest: {name or "-"} '
                  f'({score:.2f})')


if __name__ == '__main__':
    if '--equipment' not in sys.argv:
        main()

def equipment_report() -> None:
    """Which of our equipment the vendor's library appears not to cover.

    Reported as an UPPER BOUND on what will still be missing, never as a
    finding. It compares vocabularies, and two catalogs describing the same
    machine in different words look like a gap when they are not — the first
    run of this said `pullup_bar` was absent while the vendor's own equipment
    column reads "Pull Up Bar" fifteen times.

    Which is also the reason the vendor's offer to cross-reference the list
    themselves is still the answer. This is for deciding what to ask them
    about, not for deciding whether to buy.
    """
    try:
        import openpyxl
    except ImportError:
        sys.exit('pip install openpyxl')
    import collections

    ws = openpyxl.load_workbook(VENDOR_META, read_only=True)['Sheet1']
    vend = [r for r in ws.iter_rows(min_row=2, values_only=True) if r[1]]

    def words(*fields: object) -> set[str]:
        out: set[str] = set()
        for f in fields:
            out.update(norm(str(f or '')))
        return out

    vend_words = [words(r[6], r[1]) for r in vend]

    rows = json.loads(CATALOG.read_text(encoding='utf-8'))
    gap = [r for r in rows if not r.get('video')]
    by_eq = collections.Counter(
        r.get('equipmentId') or 'bodyweight' for r in gap)

    absent = []
    print(f'{"our equipment":28} {"gap":>4}  vendor rows naming all its words')
    print('-' * 68)
    for eq, n in by_eq.most_common():
        ours = set(norm(eq))
        if not ours:
            continue
        hits = sum(1 for w in vend_words if ours <= w)
        if hits == 0:
            absent.append((eq, n))
        print(f'{eq:28} {n:>4}  {hits:>5}'
              f'{"   <-- nothing found" if hits == 0 else ""}')
    print('-' * 68)
    print()
    print(f'UPPER BOUND on what stays missing: {len(absent)} kinds of '
          f'equipment, {sum(n for _, n in absent)} of {len(gap)} exercises')
    for eq, n in absent:
        print(f'  {eq:28} {n}')
    print()
    print('metadata completeness in the vendor workbook:')
    for i, name in enumerate(
            ('Categories', 'Exercise', 'Instructions', 'Tips',
             'Primary muscles', 'Secondary muscles', 'Equipment')):
        filled = sum(1 for r in vend if r[i] not in (None, '', 'None'))
        print(f'  {name:20} {filled:>5} of {len(vend)} '
              f'({filled / len(vend) * 100:.0f}%)')


if '--equipment' in sys.argv:
    equipment_report()
