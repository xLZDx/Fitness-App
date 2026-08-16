# Exercise catalog — description coverage and defect accounting

**Date:** 2026-08-15 (local Europe/Chisinau) / 2026-08-15 UTC
**Scope:** `mobile/assets/data/exercises_vendor.json` (1887 EN rows) and
`mobile/assets/data/exercises_vendor.ru.json` (1887 RU entries), measured at the tree
staged for the Gate E remediation commit.

This answers one question: **how many exercises still have no description, and how many
have a wrong one.** The second half of that question does not have a single honest number,
and this document says exactly why rather than inventing one.

---

## 1. Missing description — exact, machine-measured

| Field | EN | RU |
|---|---|---|
| `title` | 1887 / 1887 | 1887 / 1887 |
| `summary` | 1887 / 1887 | 1887 / 1887 |
| `steps` | 1887 / 1887 | 1887 / 1887 |
| **`purpose` ("why this matters") absent** | **1484 of 1887 (78.6%)** | same 1484 |
| Rows with a single step instead of a breakdown | 1 (`ea_major_groups_muscle_body`) | — |
| Rows with only 3 steps | 124 | — |
| Rows with no contraindication tag in any region | 360 | — |
| `visual_status = NOT_VERIFIED` — nobody compared the artwork against the text | **1484** | — |

The 1484 figure appearing twice is not a coincidence. Exactly 403 rows carry a `purpose`,
and exactly 403 carry `visual_status = PASS` (399 `PASS` + 3 `ACCEPTED WITH NAMING CAVEAT`
+ 1 `TITLE/POSTER ACCEPTED…`). **403 rows are the authored, proofread part of the catalog;
the other 1484 are raw vendor rows** where nobody wrote a "why" and nobody checked that the
picture matches the words.

---

## 2. Wrong description — confirmed by card-by-card review

Detectors scanned all 1887 rows and flagged **519 distinct cards** across **609 findings**.
Of those, **199 cards** were re-verified card by card in Gate E:

| Gate E verdict | Cards |
|---|---|
| `FALSE_POSITIVE` | 107 |
| `DEDUP_CANDIDATE` (a duplicate card, not wrong text) | 59 |
| `LEGITIMATE_VARIANT` | 24 |
| `PERFORMANCE_CLAIM` | 16 |
| `REAL_DEFECT` | 8 |
| `METADATA_DEFECT` | 3 |
| `CONTENT_DEFECT` | 2 |
| `STYLE_HYPERBOLE` | 2 |
| `SAFETY-MEDICAL_CAUSAL_CLAIM` | 1 |
| `DATA_QUALITY_QUARANTINE` | 1 |
| `FIXED` | 1 |

That resolved to **33 genuine action items**: 29 applied, 3 closed as the untouched half of
a rewritten pair, **1 left open** (`ea_major_groups_muscle_body`). A further **4 defects**
were found opportunistically in text this gate never targeted and were deliberately not
fixed, because each needs its own decision.

**Known-wrong cards still open: 5.**

- `ea_major_groups_muscle_body` — a single step, generic standing cue, no real exercise
  behind it. Quarantine-or-delete decision.
- `ea_cable_wrist_extension` — asserts a flexor/extensor strength parity that does not
  exist, plus an unhedged causal medical claim.
- `ea_puppy_pose` — "the lower back is not involved" is backwards for this pose.
- `ea_sissy_squat_bodyweight` — implies any knee adapts eventually.
- `ea_criss_cross_bow_tie_pose` — the RU title describes a seated crossed-**legs** hip
  opener; the exercise is a shoulder stretch with the arms crossed behind the back, and the
  card's own RU steps say so.

---

## 3. Measurable signals that a description does not belong to its card

These need no judgement call — they are structural facts about the data.

| Signal | Cards |
|---|---|
| Byte-identical `steps` shared by different exercises (EN) | 83 across 38 clusters |
| Same, RU | 71 across 33 clusters |
| Identical `summary` shared by different exercises (EN) | 355 across 140 clusters — **224 of them never flagged by any detector** |
| RU `summary != steps[0]`, while EN holds that invariant on all 1887 | 127 |
| `equipmentLabel` is the literal string `"None"` while `equipmentId` names a real machine | 78 |

**Important caveat, without which the first row is misleading.** Identical steps do not
prove a wrong description. The largest cluster is `Barbell Deadlift` / `Barbell Deadlift
(front POV)` / `Barbell Deadlift (side POV)` / `Barbell Deadlift 360 Degrees` — one
exercise shot from four angles, where the text is correct and the **cards** are redundant.
Gate E already separated this population into 59 `DEDUP_CANDIDATE` and 24
`LEGITIMATE_VARIANT`. Read the 83 as "redundant or wrong", never as "wrong".

The `summary` row is the more alarming one: **224 of the 355 cards sharing a summary with
another card were never flagged by any detector**, so no gate has ever looked at them.

---

## 4. Coverage — the number that matters most

- **1368 of 1887 cards (72.5%) were never flagged by a detector and were never read card by
  card.** How many of them carry a wrong description is **unknown**, and no defensible
  estimate exists.
- **1128 of those 1368** additionally have no `purpose` at all.
- Of the 519 flagged cards, **320 were dismissed at gates A/B/C** and never re-verified.
  Those dismissals are precisely the classifications proven unreliable: the SPINE_CUE pass
  in this same audit produced **29 false positives out of 29**, every one of them matching
  `<body part> + "straight back"` (the direction a limb travels) as though it were a
  spinal-posture cue.

Extrapolating the Gate E hit rate onto the unread 1368 would be unsound in both directions.
The 519 were selected *because* detectors matched them, so they are not a random sample; and
the detectors that selected them are the same ones with a demonstrated ~50% false-positive
rate. This document therefore reports the unread population as unknown rather than
estimated.

---

## 5. Reproducing these numbers

```bash
cd mobile
python3 - <<'PY'
import json, collections
en = json.load(open('assets/data/exercises_vendor.json', encoding='utf-8'))
ru = json.load(open('assets/data/exercises_vendor.ru.json', encoding='utf-8'))

print('no purpose (EN):', sum(1 for e in en if not (e.get('purpose') or '').strip()))
print('no contraindications:', sum(1 for e in en if not e.get('contraindications')))
print('EN summary != steps[0]:', sum(1 for e in en if e['summary'] != e['steps'][0]))
print('RU summary != steps[0]:', sum(1 for v in ru.values() if v['summary'] != v['steps'][0]))
print('equipmentLabel "None" with a real equipmentId:',
      sum(1 for e in en
          if str(e.get('equipmentLabel')).strip().lower() == 'none' and e.get('equipmentId')))

g = collections.defaultdict(list)
for e in en:
    g[tuple(e['steps'])].append(e['id'])
dupe = [v for v in g.values() if len(v) > 1]
print('identical-steps clusters:', len(dupe), '| cards:', sum(len(v) for v in dupe))
PY
```

The Gate E verdict counts come from
`core/audit/full_catalog_1887_2026-08-15/SPTR_FULL_CATALOG_1887_GATE_E_RECLASSIFIED_2026-08-15.csv`
(224 findings over 199 distinct cards, column `gate_e_label`). The 519/609 detector totals come
from `core/audit/full_catalog_1887_2026-08-15/SPTR_FULL_CATALOG_1887_FINAL_ISSUES_2026-08-15.csv`,
and the per-card `visual_status` / `has_purpose` / `final_priority` columns from
`core/audit/full_catalog_1887_2026-08-15/SPTR_FULL_CATALOG_1887_FINAL_VERIFIED_2026-08-15.csv`
(all 1887 rows).

**Those files used to live only in the operator's `Downloads` directory** — a persistence risk of
the same class this project already hit once, the 2026-08-04 loss of 131 unpersisted findings. Gate
G6 (2026-08-16) imported the whole delivered package into `core/audit/full_catalog_1887_2026-08-15/`
byte-for-byte, with a `MANIFEST.csv` recording a SHA-256 and a row count for each. Run
`python tools/evidence/validate_csv_evidence.py` to prove the bytes have not moved since.

---

## 6. What this does NOT claim

- It does not claim the 1368 unread cards are fine. It claims nobody has looked.
- It does not claim the 33 Gate E action items are the complete defect set, even within the
  199 cards reviewed — they are what survived a re-verification that itself corrected an
  earlier pass which had been 100% wrong on one detector.
- It does not treat `DEDUP_CANDIDATE` or `LEGITIMATE_VARIANT` as wrong descriptions. Those
  are catalog-structure problems (too many cards for one movement), tracked separately.
