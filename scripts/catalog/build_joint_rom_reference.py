# -*- coding: utf-8 -*-
"""Builds the joint range-of-motion reference: metric-typed, and deliberately NOT clinical.

    python scripts/catalog/build_joint_rom_reference.py            # write
    python scripts/catalog/build_joint_rom_reference.py --check    # CI: fail on drift

Output: mobile/assets/data/joint_rom_reference.json. Idempotent -- two runs
produce byte-identical bytes, which is what lets dataset_registry.py pin it.

## Why this exists, and why it is not what it first looked like

`core/DECISION_LOG.md` (2026-08-08) resolved to take exercise thresholds by
MEASUREMENT from MM-Fit, and recorded a second, softer source alongside it:
clinical amplitude norms from a poster and a blog article, to serve as
"границы правдоподобия, а не пороги упражнений" -- plausibility bounds, never
exercise thresholds. That second source was written down and then never built.
This builds it, under two corrections that came out of GPT-PM's review.

**It is not wired to rep counting, and the reason is anatomical rather than
architectural.** `measured_rep_configs.dart` drives every movement from a
three-landmark SAGITTAL angle -- squat is leftHip/leftKnee/leftAnkle, curl and
press are elbow triples. Every motion below is a TRANSVERSE-plane rotation.
They are different measurements about different axes, and the fact that both
are expressed in degrees is not a relationship between them. Constraining a
70-172 degree knee-flexion measurement by a 30-60 degree hip-rotation interval
would have produced validation that looks rigorous and means nothing. So each
row states its own metric, and a bound may only ever be applied to a
measurement of that same metric.

**It makes no clinical claim.** The provenance for these numbers is a
photograph of a poster plus a blog article. Those numbers do match the
benchmarks published in the usual clinical references, which is why they are
worth keeping at all -- but "matches something widely repeated" is not a
citation, and this project ships a fitness app, not a diagnostic instrument.
So the artifact carries `clinical_use: false`, every row carries the origin it
actually has rather than a borrowed authority, and nothing here may be
presented to a user as a medical finding. That choice also means the artifact
depends on no third-party licence: no external table is reproduced, only
values recorded with their real provenance.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / 'mobile' / 'assets' / 'data' / 'joint_rom_reference.json'

#: The origin string every row carries. One constant, because the rows share
#: one origin and repeating a paraphrase per row is how provenance drifts.
_ORIGIN = (
    'core/DECISION_LOG.md 2026-08-08: operator poster photograph plus a bodycoach '
    'article, recorded there as a SECOND source for plausibility bounds and '
    'explicitly not as exercise thresholds'
)

#: Verbatim, because a translated or paraphrased threshold is a different
#: threshold. The log gives this after the three motions without saying which
#: it attaches to, so it is recorded at document level rather than being
#: silently distributed across rows it may not describe.
_LIMITATION_NOTE_RU = 'ограничение значимо при < 20°'

ROWS = [
    {
        'id': 'hip_internal_rotation',
        'joint': 'hip',
        'motion': 'internal_rotation',
        'plane': 'transverse',
        'typicalMinDeg': 30,
        'typicalMaxDeg': 40,
    },
    {
        'id': 'hip_external_rotation',
        'joint': 'hip',
        'motion': 'external_rotation',
        'plane': 'transverse',
        'typicalMinDeg': 40,
        'typicalMaxDeg': 60,
    },
    {
        'id': 'tibial_rotation',
        'joint': 'tibia',
        'motion': 'rotation',
        'plane': 'transverse',
        'typicalMinDeg': 10,
        'typicalMaxDeg': 15,
    },
]

#: Every row gets these, and the schema test rejects a row missing any of them.
#: `measurementMethod` and `population` are as load-bearing as the numbers: a
#: passive goniometric range measured on general adults is not interchangeable
#: with an active range measured on athletes, and a row that does not say which
#: it is cannot be compared with anything.
REQUIRED_FIELDS = (
    'id', 'joint', 'motion', 'plane', 'unit', 'measurementMethod',
    'population', 'typicalMinDeg', 'typicalMaxDeg', 'provenance',
)


def build() -> dict:
    rows = []
    for r in ROWS:
        row = dict(r)
        row['unit'] = 'degree'
        row['measurementMethod'] = 'goniometry_passive'
        row['population'] = 'adult_general'
        row['provenance'] = _ORIGIN
        missing = [f for f in REQUIRED_FIELDS if f not in row]
        if missing:
            raise SystemExit(f"row {row.get('id')!r} is missing {missing}")
        if row['typicalMinDeg'] >= row['typicalMaxDeg']:
            raise SystemExit(f"row {row['id']!r} has an empty or inverted range")
        rows.append({k: row[k] for k in REQUIRED_FIELDS})
    return {
        'schema': 'joint_rom_reference/v1',
        'generated_by': 'scripts/catalog/build_joint_rom_reference.py',
        'clinical_use': False,
        'disclaimer': (
            'Non-clinical plausibility bounds. These values are not a diagnosis, not a '
            'clinical assessment, and must never be presented to a user as a medical '
            'finding. Exercise thresholds come from measurement (MM-Fit), never from here.'
        ),
        'not_rep_thresholds': (
            'Every row is a transverse-plane rotation. The rep counter measures '
            'sagittal three-landmark angles. A bound here may only ever be applied to a '
            'measurement of the SAME metric, which today means none of the rep configs.'
        ),
        'limitation_note_ru': _LIMITATION_NOTE_RU,
        'rows': rows,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--check', action='store_true',
                    help='compare against the committed file instead of writing it')
    ns = ap.parse_args(argv)

    text = json.dumps(build(), ensure_ascii=False, indent=2, sort_keys=False) + '\n'

    if ns.check:
        if not OUT.is_file():
            print(f'MISSING {OUT}', file=sys.stderr)
            return 1
        if OUT.read_text('utf-8') != text:
            print(f'DRIFT {OUT} differs from what this builder produces', file=sys.stderr)
            return 1
        print(f'OK {OUT.name}: {len(build()["rows"])} rows, matches the builder')
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding='utf-8', newline='\n')
    print(f'wrote {OUT} ({len(build()["rows"])} rows)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
