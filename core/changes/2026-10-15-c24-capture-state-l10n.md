# Change record: C24 part 2, capture state, thumbnail store, ARB keys, sources list

## What changed
- `mobile/lib/features/food_diary/state/image_prep.dart`: `prepareJpeg` (bake EXIF orientation, resize to a long edge, re-encode JPEG from raw pixels so EXIF/GPS/ICC are dropped, never enlarges, null when undecodable or over 3 MB) plus an isolate wrapper; constants 1024 px (meal), 1280 px (label), 256 px (thumbnail).
- `state/capture_image_port.dart`: `CaptureImagePort` (camera or gallery, null on cancel or denied permission), `image_picker` implementation, `FakeCaptureImagePort`, provider.
- `state/barcode_port.dart`: `BarcodePort` wrapping `mobile_scanner` (decoded values stream, preview with an error builder, torch, pause/resume, dispose), `FakeBarcodePort`, factory provider. No `formats` filter: the page keeps only values that pass `GtinValidator`, which also covers ITF-14 without depending on enum names that differ between mobile_scanner majors.
- `state/meal_thumbnail_store.dart`: optional private meal thumbnail encrypted with the existing progress-photo cipher, stored on device at `<per-uid photo dir>/meals/<entryId>.bin`; `put/read/exists/delete/pruneExcept`; `mealThumbnailDeleterProvider` (best effort, never throws).
- `state/diary_providers.dart` (C23 file, one edit): `FoodDiaryActions.deleteEntry` calls the thumbnail deleter after the repository delete, so the thumbnail is deleted with the entry.
- ARB (EN and RU): keys `foodScan*`, `foodMeal*`, `foodBarcode*`, `foodLabel*` and `nutritionSources{SoftwareTitle,Scanner,CalorieTracker,ReferenceOnly,FullList}`. No plural strings were needed, so there are no RU one/few/many/other forms in this story; every string is a plain sentence.
- `nutrition_plan/plan_sources_page.dart`: new "Software and references" section so the in-app list matches `core/ATTRIBUTIONS_NUTRITION.md`.

## Why
Shared building blocks for the three scan pages (design s17.2, s17.4, s17.6), and the attribution consistency required by C24.

## Affected contracts and paths
Thumbnail files live inside the per-uid photo directory, which account deletion already wipes. `PhotoStore.prune` only touches top-level `.bin` files, so the `meals/` subfolder is not pruned by it. The thumbnail is not yet displayed in the diary (follow-up).

## Verification state
Nothing was run (no analyze, tests, gen-l10n, pub get). `mobile_scanner` 6.x API names (`MobileScannerController`, `MobileScanner(onDetect, errorBuilder)`, `DetectionSpeed.noDuplicates`, `toggleTorch/start/stop/dispose`) are written from memory of the 6.0.x API and are an on-device/compile VERIFY item.
