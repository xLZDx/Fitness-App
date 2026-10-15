# Change record: C21 generic foods table

## What changed
- `scripts/nutrition/build_generic_foods.py` (new, standard library only, not run in CI): reads the USDA FDC Foundation Foods and SR Legacy JSON zips (`--download` or local `--foundation-zip/--sr-legacy-zip`), keeps nutrient ids 1008/1003/1005/1004 (energy falls back to Atwater ids 2047/2048, then 4/4/9 flagged `derivedEnergy`), drops brand, baby, fast-food, restaurant and Alaska Native rows, caps SR Legacy per category (simplest names first), and authors diet/allergen tags by category and keyword rules. Output is deterministic.
- `mobile/assets/nutrition/generic_foods_v1.json` (new, generated): 2,590 rows from the real USDA datasets (Foundation 2024-10-31, SR Legacy 2018-04), fetched by the agent; the 150-row fixture fallback was not needed. Row: `{id: "gen:<fdcId>", name, category, per100g{kcal,proteinG,carbsG,fatG}, sourceId, fdcId, tags}`.
- `mobile/assets/nutrition/generic_foods_ru.json` (new, own-authored): 321 Russian display names keyed by exact English name (names only). Smaller than the ~400 target; foods without an entry fall back to English.
- `mobile/pubspec.yaml`: registers `assets/nutrition/`.
- `mobile/lib/features/food_diary/data/generic_foods.dart` (new, pure): `GenericFoodTable.parse(foodsJson, {ruJson})`, token search (exact 3 > prefix 2 > substring 1, all query tokens must match, EN+RU synonym table, deterministic ties), restrictive tag parsing.
- `mobile/lib/features/food_diary/data/food_suggestions.dart` (new, pure): `fitsFilter` and `suggestFoods` (up to 5 foods, diet/allergen/exclusion filter, ranked by density of the macro the day is furthest behind, max two per category).

## Why
Sprint plan C21; design 17.5, 17.8, D-71 (suggestions live in `food_diary/data` so `nutrition_plan` never imports `food_diary`).

## Contracts and decisions
- Tags beyond the design's three: `allergens`, `allergenCertain`, `pork`, `alcohol`; `animalProduct` / `pescatarianOk` are `null` when unknown. Uncertain means: `allergenCertain != true`, unknown allergen name, or a null animal/pescatarian tag. Uncertain rows stay searchable (`GenericFoodHit.showTagWarning`) and are hidden from suggestions whenever a restriction applies.
- Halal and kosher also hide land-animal meat (slaughter certification is not modelled); kosher also hides shellfish. This is the restrictive reading of "uncertain defaults restrictive".
- The asset read (`rootBundle`) belongs to the state layer and is NOT part of this commit; `parse` takes the two JSON strings.
- Brand filtering is heuristic (brand word list, ALL-CAPS tokens); a few branded rows may remain.

## Operator items
- Licence/attribution: USDA FDC data is CC0 1.0; no attribution is required, but the /licences screen may list it (C-later).
- Optional: extend `generic_foods_ru.json` toward ~400 names.

## Verification state
Not run, per DEVELOPMENT RULES v4 (no tests, analyze or build). Only a JSON parse of both assets (2,590 and 321 entries; all RU keys exist in the table) was done. Focused tests: coverage map `food_suggestions` diet/allergen filtering with restrictive defaults.

## Review state
Pending the test phase and specialist reviewers.
