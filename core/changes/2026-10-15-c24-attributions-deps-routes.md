# Change record: C24 part 1, attributions, dependency, tile routes

## What changed
- `core/ATTRIBUTIONS_NUTRITION.md` (new) with the design s17.9 rows: USDA FoodData Central (CC0), Open Food Facts (ODbL 1.0 / DbCL 1.0, images not used), `mobile_scanner` (BSD-3), `calorie-tracker` (MIT, ideas only), `calorie-count` (licence ambiguous, nothing copied), OpenNutriTracker (GPL-3.0, design reference only), Mifflin-St Jeor and Deurenberg formulae, Nutrition5k (evaluation pointer). Registered in `core/INDEX.md`.
- `mobile/pubspec.yaml`: adds `mobile_scanner: ^6.0.11`. The design named the 7.x line, but 7.x requires Flutter 3.29 and the installed toolchain is Flutter 3.27.1 / Dart 3.6.0 (read from `flutter --version`), so the newest 6.0.x is used. `pub get` was NOT run and `pubspec.lock` is untouched.
- `mobile/lib/features/food_diary/add_food_page.dart`: the three tiles now push `/nutrition/add/photo`, `/nutrition/add/barcode` and `/nutrition/add/label` (they pushed `/nutrition/scan/meal|barcode|label`, which disagreed with the plan and design s21). The routes themselves are registered by the later C24 commits.

## Why
The plan row C24 and design s17.9 require an attribution file; the barcode page needs the scanner dependency; the tile paths and the planned routes must agree (coordinator instruction).

## Affected contracts and paths
Route table of design s21 (now matches the tiles). No data or rules change.

## Verification state
Nothing was run (no pub get, tests, analyze). `/nutrition/add/*` routes resolve only after the router commit of this story.

## Open VERIFY items
- Android `dev.steenbakker.mobile_scanner.useUnbundled` is left at its default; test the Play-services model download on the operator's phone before setting it.
