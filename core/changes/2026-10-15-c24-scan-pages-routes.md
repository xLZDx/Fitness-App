# Change record: C24 part 3, meal, barcode and label pages and routes

## What changed
- `mobile/lib/features/food_diary/meal_scan_page.dart`: camera or gallery pick, on-device resize to a 1024 px long edge (EXIF dropped by re-encode), optional note (<= 200 chars, passed as `note`), data-notice gate (D-79) before the call, `analyzeMealPhoto` in photo mode, empty result shows "We could not find food in this photo", result always goes through `FoodDetailSheet`. Optional private thumbnail (switch, default on, local pref `food_diary.meal_thumbnail.enabled`): 256 px, encrypted with the existing cipher via `MealThumbnailStore`, written only after the entry is saved, deleted with the entry.
- `barcode_scan_page.dart`: live preview through `BarcodePort`; only GTIN-valid values (`GtinValidator.normaliseValid`) call `lookupBarcode`; found goes to the confirm sheet (serving size or 100 g portion); not found offers the label scan or quick log; a typed barcode covers a denied camera; failures use the closed `FoodApiFailure` messages.
- `label_scan_page.dart`: 1280 px resize, `parseNutritionLabel`, then ALWAYS the editable `LabelConfirmSheet` (also when nothing could be read). Per-serving values are converted with `LabelScale` only when the serving weight is usable. Confirm writes a `saved_food` (`SavedFood`), then the detail sheet logs the entry with `scaleMissing` / `dataInconsistent` chips when applicable. `parseLabelDraft` is the pure validator (name, 0..1000, optional positive serving).
- `widgets/scan_common.dart`: shared day, language and failure-message helpers.
- `mobile/lib/core/router/app_router.dart`: routes `/nutrition/add/photo`, `/nutrition/add/barcode`, `/nutrition/add/label` (query `day`, `slot`), matching the tiles changed in part 1.

## Why
Plan row C24 and design s17.2, s17.4, s17.6.

## Affected contracts and paths
Uses the existing callables and `FoodApi` interface unchanged. Describe mode stays in `AddFoodPage`'s describe sheet (C23) and is not duplicated here. The thumbnail is stored but not yet displayed in the diary (follow-up).

## Verification state
Nothing was run (no analyze, tests, gen-l10n, pub get). The pages were written against the C23 sources by reading them; compile and behaviour are unverified. mobile_scanner 6.x API usage is a compile VERIFY item.

## Left for the test agents
Widget tests for the three pages with `FakeFoodApi`, `FakeBarcodePort`, `FakeCaptureImagePort`; unit tests for `parseLabelDraft`, `prepareJpeg`, `MealThumbnailStore` (put/read/delete/pruneExcept) and the deleteEntry thumbnail hook; route test for the three paths.
