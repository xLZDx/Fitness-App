# Catalog — full picture, 2026-08-03

Written in answer to: *"покажи полную картину того что есть сейчас, сколько
покрыто упражнений, пропустили мы что то из нового каталога или он полностью
залился"*.

CSV twin: `core/CATALOG_STATE_2026-08-03.csv`.
Review list: `core/CLIPLESS_FOR_REVIEW.csv`.

---

## What ships

| catalog | entries | play a clip | source |
|---|---|---|---|
| **vendor** (purchased) | 1,887 | **1,887 (100%)** | the animation pack |
| **legacy** | 511 | **355 (69%)** | Free Exercise DB text + clips matched onto it |
| **total shown to the user** | | **2,242** | all licensed, all animation |

The legacy half is switchable off (H3). With it off the catalog is 1,887, all
vendor, all demonstrated.

## Did anything from the purchased pack get missed?

**Almost nothing.** Checked against the bucket itself, not against the JSON:

| | |
|---|---|
| objects in the private bucket | 2,577 |
| object keys the two catalogs reference | 2,541 |
| **referenced but missing from the bucket** | **0** — nothing 404s on the phone |
| in the bucket, referenced by neither catalog | 36 |

Of those 36 unused clips, 34 are duplicate renders — files named `... Female.mp4`
sitting in the `men/` folder, which collapsed into their proper pairs when the
gender-suffix rule learned to read a space — plus one anatomy demo
(`MAJOR GROUPS Muscle body male`) that is not an exercise.

**Two are a real gap**, present in the pack and absent from the catalog:

- `Barbell front raise`
- `cable machine high to low` (the catalog has only `Cable Machine Low to High`,
  which is the opposite movement)

Marginal, and worth a follow-up when something else touches the builder.

## The vendor catalog itself is complete

Every one of these was measured, not assumed:

| check | result |
|---|---|
| entries with a clip | 1,887 / 1,887 |
| missing a poster | 0 |
| poster missing for one body | 0 |
| poster path in catalog, file absent on disk | 0 |
| missing Russian translation | 0 |
| Russian step-count differs from English | 0 |
| carries a muscle tag | 1,705 / 1,887 (182 deliberately untagged — Calisthenics, Powerlifting, Stretching, Yoga name no muscle honestly) |

## How the legacy half got to 355

| | legacy playing a clip |
|---|---|
| after the exact name-match import (2026-08-02) | 142 — of which 101 were half-converted, one body only |
| after removing the unlicensed scaffold | 186 |
| after the semantic re-match, round one | 337 |
| after round two (the failed batch, re-asked) | **355** |

Round two exists because 12 exercises were never asked at all — a model batch
failed twice and was skipped. Re-asking them, and re-judging the 19 rows the
guard flagged, recovered 18 more.

### A verdict of mine that was wrong

I wrote that **Recumbent Bike** had no match because *"the library has no
recumbent or upright stationary bike at all, only air/assault bikes"*. It does:
`Stationary Exercise Bike`. I had reached that conclusion from a search whose
output was truncated at 20 of 29 hits and did not read the rest. Corrected; the
exercise now plays.

## What is left: 156 exercises with no clip

| | |
|---|---|
| previously played the unlicensed scaffold | 80 |
| never had a clip at any point | 76 |
| **lost a licensed clip** | **0** |

Sorted by how close the nearest vendor clip is, in
`core/CLIPLESS_FOR_REVIEW.csv`. 46 sit at 0.75 similarity or above — those are
where a false negative would hide, and they are worth an eye first. The rest are
genuinely specific: sled drags, chains, harnesses, Rocky pull-ups, powerlifting
bench variants.

The matcher refuses when the equipment or the body position differs, which is
right three times out of four (`Barbell Rear Delt Row` is not the dumbbell one)
and occasionally too strict (`Cable Rope Pushdown` against `Cable Pushdown` is
an attachment, not an exercise). That last class is what the review list is for.
