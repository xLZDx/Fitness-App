# Vendor exercises linked to the 52-machine registry — verified by eye

2026-08-03. This is what closes the gap named on 2026-08-03: *"привязка к
тренажёрам. 82 строки оборудования вендора → наши 52 машины, иначе скан для
вендорских упражнений не работает"*. H5's scanner rewrite answered a different
question (what IS this machine); this is the one the machine detail page
actually depends on.

CSV twins: `core/vendor_equipment_visual_audit.csv` (all 1,887, full trail),
`core/vendor_equipment_needs_review.csv` (90 rows still open).

---

## Why this was necessary at all

`equipment_detail_page.dart` fills a machine's page through
`exercisesFor(equipmentId)`, which filters purely on `e.equipmentId ==
machineId`. Checked directly: **0 of 1,887 vendor exercises carried an
equipmentId** — the purchase never assigned one. So every one of the 52
machine pages was showing zero real, clip-carrying exercises and falling back
to AI-generated text with no video at all (confirmed:
`ai_exercise_generator.dart`'s response schema has no `video` field).

A first pass — resolve exercise titles, and the vendor's own spreadsheet
`Equipment` column, through the same alias index the scanner uses — reached
**1,088 of 1,887 (58%), 44 of 52 machines**.

## Why that number was not trusted

Operator: *"верить никому нельзя все надо проверять"*. Neither the vendor's
spreadsheet nor the `equipmentLabel` already derived from it were taken as
ground truth. Instead, for every one of the 1,887, independently:

1. Look at the exercise's own poster — a real frame from its own clip, already
   bundled, no download needed — and decide what equipment it shows, with no
   hint of what the spreadsheet claims.
2. Compare that independent answer against the spreadsheet's value for the
   same exercise, when it has one.
3. If they agree (or the sheet has nothing), resolve what was actually SEEN
   against the registry.
4. If they disagree, or nothing resolves, record exactly what the clip showed
   and hold it for review rather than guessing.

One vision call per exercise, not batched — a text batch cannot confuse row 3
with row 7, a multi-image vision prompt can, and getting this wrong is exactly
what the check exists to prevent.

## A defect the first prompt had, caught before the full run

The registry mixes a generic implement (`Barbell`, `Dumbbell`) with the
specific station a movement is normally performed at (`Squat rack`,
`Weight bench`). The first version of the prompt answered "Barbell" for a
barbell squat — technically true, useless in practice, since `squat_rack` is
the page a user actually opens after scanning the rack. Confirmed against the
legacy catalog's own established convention (`Barbell Squat → squat_rack`,
`Barbell Bench Press → bench_press`, `Barbell Deadlift → barbell`, because no
deadlift station exists) before fixing the prompt to prefer the station when
one exists for that exact movement, and the generic implement only when it
doesn't.

## The result

| | |
|---|---|
| resolved to a specific machine | **1,330 / 1,887 (70%)** |
| confirmed no equipment (correct, not a problem) | 436 |
| unresolved — no registry match | 84 |
| needed a manual look (disagreement) | 96 → resolved by eye |
| **registry machines with ≥1 vendor exercise** | **48 / 52** |

### The 96 disagreements, by hand

~30 were noise: the sheet tags almost every floor stretch `"Yoga Mat"`,
which isn't a real equipment claim (there is no `yoga_mat` in the registry
either) — my sheet loader didn't originally exclude it the way it already
excluded `"None"`. Fixed, and re-checked: **9** of those had vision find real
equipment the noisy sheet default had papered over (`Dead Hang Stretch` →
Squat rack, three `Exercise Ball ...` stretches → Stability ball,
`Leg Extended Stretch on Bench` → Bench, `Reverse Shoulder Stretch` → Plyo box,
two more → Resistance bands) — confirmed against the actual poster for every
one, not assumed from the pattern.

The other **~18** were genuine sheet-vs-vision conflicts, each looked at
directly:

- **17 promoted** — vision was right, the sheet was generic or wrong.
  `Standing Calf Raises Smith Machine` (title says Smith Machine, sheet said
  "Resistance Band"), `Dumbbell Single Arm Overhead Lunge` (sheet said
  "Kettlebells", poster is unambiguously a dumbbell overhead), `Chest Dip`
  (sheet said "Chair", poster is a dip station), `Low Resistance Band Lying
  Bicep Curl` ×2 (poster shows a cable tower, not a band).
- **1 rejected** — `Dumbbell Standing Wrist Curl`: vision said "Barbell", the
  poster clearly shows dumbbells. Never applied. The only case in this whole
  pass where the independent check itself was wrong, not the sheet.

## The 4 machines still at zero — genuine gaps, not misses

Confirmed by direct search, not inferred from the null count:

- **`recumbent_bike`** — the library's `Stationary Exercise Bike` is upright
  and correctly resolved to `exercise_bike`, a different registry id. No
  reclined-seat bike exists in the pack.
- **`glute_kickback_machine`** — every kickback clip uses a cable, a band, or
  a dumbbell + bench. No dedicated kickback machine.
- **`t_bar_row`**, **`rotary_torso_machine`** — no matching clip by name or by
  what any clip shows.

## What was applied

`equipmentId` written onto the 1,330 resolved entries in
`exercises_vendor.json`. `equipmentLabel` (the free-text type used by the "at
home" filter) is untouched — both fields now coexist on every linked entry.
16 new tests in `vendor_catalog_test.dart`. Full suite green.

## Still open

90 rows in `core/vendor_equipment_needs_review.csv`: 84 where nothing in the
registry matches what the clip shows, 6 where I deliberately withheld a link
(the wrist-curl rejection, plus 5 where vision correctly found nothing
distinctive to go on). None of these block the next gate — they are exercises
that either need no machine page or need a second look later.
