# Change record: C22 food diary data layer

## What changed
New pure Dart files (no Flutter, Firestore or platform imports) under `mobile/lib/features/food_diary/data/`:
- `food_entry.dart`: `MacroRange` (`low <= mid <= high`, sanitised, `combine` = mid sum with root-sum-square spreads), `Per100g`, `MacroTotals`, enums `MealSlot`, `EntrySource`, `EntryConfidence`, `MatchQuality`, `FoodItem`, `ModelRef`, `FoodEntry`. `toJson` omits null and empty optional keys (`model`, empty `checkThese`) and throws `FormatException` when `validate()` reports what Firestore rules would refuse (0 or more than 30 items, more than 8 chips, name over 80, bad `day`, degraded entry). `fromJson` is tolerant: unknown enums degrade to safe defaults and set `degraded`, which blocks a later write; unknown check codes are dropped.
- `portion_math.dart`: `itemMacros`, `itemTotals`, `entryTotalsOf`, `editItemGrams` (recomputes only the edited item, user grams become an exact range), `buildEntry`, `quickLogEntry` (one `user:quick` item, 100 g pseudo-portion), `isAtwaterConsistent` (`max(25 %, 10 kcal)`), `applyHiddenOil` (none / 5 g / 14 g from a caller-supplied generic oil row; replaces an earlier choice; marks the chip resolved).
- `day_totals.dart`: `computeDayTotals` (RSS ranges, `below | within | above` on mid with inclusive bounds, `belowRangeBy`, `remainingKcal` against the top, protein minimum at exactly the minimum), `mealShares` and `mealKcalTargets` (3 meals 30/35/35).
- `check_these.dart`: closed `CheckCode` (11 codes), `CheckResolution` per code, `OilChoice`, `CheckItem`, `CheckThese` helpers (cap 8, de-duplication, unknown codes dropped, `markResolved`).
- `gtin_validator.dart`: GS1 check digit, lengths 8/12/13/14, digits only, no trimming or leading-zero stripping in `isValid`; `normaliseValid` trims whitespace for typed input.
- `label_scale.dart`: exact per-serving <-> per-100 g inverse; a missing, zero, negative or non-finite serving weight returns `scaleMissing` and never divides.
- `food_source.dart`: `FoodSource` (off, usda, llmEstimate, user, label) with wire ids `open_food_facts | usda_fdc | llm_estimate | user | label_ocr`, attribution name and estimate flag.

## Why
Sprint plan commit C22 (design s5.6, s17.3, s17.4, s17.6, s17.7, s17.10; D-39, D-71); coverage map FOOD-12, FOOD-16 to FOOD-20, FOOD-23.

## Decisions and deviations to review
- Per-meal split for 4 or more meals is not fully specified in the design ("remainder spread evenly"). Chosen: each snack 10 % (total at most 40 %), the three main meals keep 30/35/35 of the remainder; 2 meals 50/50; 1 meal 100 %. Shares always sum to 1.
- `FoodItem.sourceId` accepts `llm_estimate` (design s17.3 gives items that tag) although the s5.6 item list and the rules allowlist name only `usda_fdc | open_food_facts | user | label_ocr`. The Firestore rules (C-rules commit) must allow `llm_estimate` for items, or the diary must write such items as `user`. Flagged for the C23 repository / rules reviewers.
- `FoodEntry.id` is the document id and is not serialised.
- `loggedAt` serialises as an ISO-8601 string; the Firestore repository (C23) maps it to a Timestamp.
- The oil item for `hiddenIngredients` is supplied by the caller from the bundled generic table (C21); this layer does not import `generic_foods.dart`.

## Affected contracts and paths
New files only; nothing existing is modified. `generic_foods.dart` and `food_suggestions.dart` (C21) are untouched.

## Verification state
Not run, per DEVELOPMENT RULES v4 (no tests, analyze or lint before the sprint test phase). Focused tests are planned as T90 to T94 and T96 in the coverage map.

## Review state
Pending the test phase and specialist reviewers.
