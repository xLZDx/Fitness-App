# Equipment registry expansion, 52 -> 69 -- 2026-08-03 / 2026-08-04

Follows directly from `VENDOR_EQUIPMENT_LINK_2026-08-03.md`'s "still open"
list. Operator: *"я не понимаю что ты пытаешься сматчить вообще... ничего не
скрывай"* -- the 44 vendor exercises that could not resolve to any of the 52
machines were never a matching problem. They show real equipment the
registry never had an id for. Batch 3 (2026-08-03) gave 15 of them one and
fixed a real, independently-confirmed recognition bug found while doing it.
Batch 4 (2026-08-04) closed the remaining 4 groups -- all 44 are resolved
now, none dropped or hidden.

CSV twins: `core/EQUIPMENT_GAP_ITEMS_2026-08-03.csv` (all 44, now with a
`resolved_to` column), `core/vendor_equipment_visual_audit.csv` (full 1,887
trail).

---

## A real bug this surfaced, unrelated to the 44

`gemini_equipment_service.dart:135-150` -- `kCanonicalMachines`, the
hardcoded list of names the camera recognition prompt is allowed to answer
with, had 48 entries. `equipment.json` has had 52 for a while. The 4 missing
-- `stability_ball`, `skipping_rope`, `ab_wheel`, `parallettes` -- have real
pages and real exercises; the camera could just never return them, because
the prompt never offered their names. `scripts/catalog/build_registry.py`,
the generator that is supposed to be these files' source of truth, was
stale in the same way: its `M` dict also stopped at 48, so running it as
checked in would have crashed on its own
`assert set(existing) <= set(M)`.

Confirmed by reading the files, not inferred: `equipment.ru.json` and
`equipment_aliases.json` were already complete for all 52 (someone added
the 4 machines by hand, or with a version of the generator that was not
kept), so only the generator and the Dart prompt list had drifted.

Both fixed this gate; a new test closes the gap that let it happen
silently in the first place (below).

## The 15 additions

Every one came from looking at the poster of an exercise that already
exists in the vendor pack -- not an external catalog, not a name search.
`core/EQUIPMENT_GAP_ITEMS_2026-08-03.csv` has the per-exercise trail.

| id | source exercises |
|---|---|
| `seated_dip_machine` | Chest Dip Machine, Triceps Dip Machine -- same rig, two clips |
| `multi_hip_machine` | Multi Hip Glute Extension |
| `lateral_raise_machine` | Machine Lateral Raise |
| `sissy_squat_machine` | Dumbbell Supported Sissy Squat |
| `agility_ladder` | 10 clips |
| `mini_trampoline` | 6 rebounder clips |
| `balance_board` | 2 clips |
| `yoga_blocks` | 5 clips, incl. one vision had separately called "calf blocks" -- same object, verified by poster |
| `weighted_sled` | 2 clips |
| `ab_mat` | Ab Mat Sit-up |
| `bosu_ball` | Crunch (on Bosu Ball) |
| `sliding_disc` | Curtsy Lunge Slide with Towel -- the poster shows an actual disc, not fabric, despite the title |
| `sandbag` | Sandbag Cleans |
| `gymnastic_rings` | Ring Dips |
| `tyre` | Tyre Flip, Tyre Hammering |

37 exercises total. 4 stayed deliberately out of the "add now" set even
though they were on the shortlist at one point: vertical pole, push-up
blocks, aerobic step, outdoor air walker -- each is a real judgement call
(alias of an existing id, or a different context entirely) rather than a
name to rubber-stamp; see "Not done here" below.

## A stale alias, found while adding these

`tricep_extension_machine`'s alias list carried `'dip machine'` -- generic
and, now that a real dip machine exists in the registry, simply wrong: a
seated triceps extension is not the same movement as a dip. Removed from
`tricep_extension_machine`, which is what `seated_dip_machine` uses instead.
No test depended on the old mapping (checked before removing it).

## How it was built

Not by hand-editing the three JSON outputs. `scripts/catalog/build_registry.py`
is the checked-in source of truth for `equipment.json` / `equipment.ru.json`
/ `equipment_aliases.json`; its `M` dict got the 4 drift-fix entries (en/ru/
aliases copied verbatim from what was already shipped, so nothing already
on disk changed) plus the 15 new ones (freely authored, matching the file's
existing style). Its `main()` was deliberately NOT run -- it also patches
`exercises.json` (the legacy catalog) via a `REASSIGN` dict and hand-authored
cardio exercises from a 2026-07-30 gate, both irrelevant to this change and
risky to replay blindly against a catalog that has since been relicensed and
semantically rematched by hand. A one-off script imported the module (which
only runs the `m(...)` calls, gated behind `if __name__ == '__main__':` for
the risky part) and replicated just the equipment/ru/aliases generation.

Verified after regenerating: diffed old vs new content by key, not by line.
`equipment.json` and `equipment.ru.json` -- zero changes to any of the
existing 52, pure append. `equipment_aliases.json` -- zero changes except
the one deliberate `tricep_extension_machine` fix above.

`kCanonicalMachines` was hand-edited (it has no generator) to add all 19
names (4 fix + 15 new). Every one checked to resolve through the alias
index before running the suite, not assumed.

## The 37 exercises

`equipmentId` written directly onto `exercises_vendor.json` (37 entries;
diffed after -- 74 changed lines, all of them `equipmentId`, nothing else
touched). `core/vendor_equipment_visual_audit.csv` and
`vendor_equipment_needs_review.csv` updated the same way batch 1/2 were.

## Two test gaps this closed

1. `registry_test.dart`'s "NO machine has zero exercises" read only
   `exercises.json` (the legacy catalog). The real page merges legacy +
   vendor (`AssetEquipmentRepository._ensureLoaded`); checking legacy alone
   would have called all 15 new machines empty the moment this shipped,
   since they only have vendor exercises. Fixed to check the union. The 4
   pre-existing vendor-empty machines (`recumbent_bike`,
   `glute_kickback_machine`, `t_bar_row`, `rotary_torso_machine`) stay
   covered through legacy alone, same as before -- **worth knowing for the
   still-open legacy-removal decision: those 4 pages are not actually blank
   today; they show legacy exercises (1, 3, 4 and 3 respectively). Removing
   the legacy catalog would make them blank, which the earlier report did
   not say explicitly.**
2. `gemini_equipment_service_test.dart` only ever checked "every name the
   prompt offers resolves" -- the direction that would never have caught
   the 48-vs-52 drift, because it only ever walks the (stale) prompt list.
   Added the reverse: every registry id must be reachable through
   `kCanonicalMachines`. This is the test that would have caught the
   original bug on the commit that introduced it.

## Result after batch 3

| | before | after |
|---|---:|---:|
| `equipment.json` | 52 | **67** |
| `kCanonicalMachines` | 48 (4 real ids unreachable) | **67** |
| vendor exercises linked | 1,335 | **1,372** |
| machines with >=1 vendor exercise | 48/67 | **63/67** |
| `vendor_equipment_needs_review.csv` | 86 | **49** |

Full suite green after the change (targeted files re-run individually
first: 59/59, including both new tests).

## Batch 4 (2026-08-04) -- closing the last 7

The 4 groups batch 3 deliberately left open, decided one at a time rather
than rubber-stamped:

- **vertical pole** (Fixed Bar Stretch, Dragonfly) -- own id, `vertical_pole`
  (category `bodyweight`). Confirmed by poster to be neither a pull-up bar
  (horizontal, overhead) nor a captain's chair; distinct enough from
  anything existing to earn its own page rather than be forced onto one.
- **push-up blocks/risers** (Elevated Push Up) -- NOT a new id. Aliased onto
  `parallettes`: both exist to elevate the hands for a deeper push-up range,
  and one exercise did not justify a second entry for the same role.
- **aerobic step platform** (Decline Kneeling Push Up) -- NOT a new id.
  Aliased onto `plyo_box` for the same reason -- a stable elevated surface,
  one exercise.
- **outdoor air walker** (3 clips) -- own id, `outdoor_air_walker` (category
  `cardio`). Real equipment in a different context, but adding a
  location/context field for 3 exercises was over-engineering; a plain
  `cardio`-category entry costs nothing extra and the app has no concept of
  "commercial gym only" to violate.

`equipment.json` 67 -> **69**. `parallettes` and `plyo_box` gained aliases
(`push-up blocks`/`push up risers`, `aerobic step`/`step platform`) rather
than new ids; `kCanonicalMachines` offers those words too so the camera can
still recognise them by sight, even though they resolve to an existing page.

All 44 rows in `core/EQUIPMENT_GAP_ITEMS_2026-08-03.csv` now carry a
`resolved_to` value. None were dropped.

### Result after batch 4

| | batch 3 | batch 4 |
|---|---:|---:|
| `equipment.json` / `kCanonicalMachines` | 67 | **69** |
| vendor exercises linked | 1,372 | **1,379** |
| machines with >=1 vendor exercise | 63/67 | **65/69** |
| `vendor_equipment_needs_review.csv` | 49 | **42** |

The 4 machines with zero vendor coverage are still exactly the 4 named
above (`recumbent_bike`, `glute_kickback_machine`, `t_bar_row`,
`rotary_torso_machine`) -- nothing in this batch touched them; they need new
licensed footage, not a linking pass.

## Also intentionally not done

Two schema ideas surfaced alongside this gate and were not built:

- A `requiredProps`/`environmental_support` style status split for the
  household-prop rows (wall, chair, couch...) already in
  `EQUIPMENT_GAP_ITEMS_2026-08-03.csv`. The plain-text `note` column already
  says this; nothing today reads or branches on a dedicated field for it.
- `primaryEquipmentId` / `requiredEquipmentIds[]` to model exercises that
  use more than one implement (tyre + sledgehammer, sissy squat + dumbbell).
  `equipmentId` (one machine, for the page it belongs to) plus the existing
  free-text `equipmentLabel` already cover what is needed today. Revisit if
  a real feature needs the second implement to be queryable, not before.
