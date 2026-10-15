# C25 part 2: client export paging/merge and device wipe list

## What changed
- `mobile/lib/features/data_export/server_export.dart`: `ServerExport.fetchPage` and `fetchAll`;
  `mergeServerPages` concatenates continuation pages per section (loop capped at `kMaxExportPages` = 50)
  and sets `pagingIncomplete` when a page fails or the cap is hit.
- `mobile/lib/features/data_export/data_export_providers.dart`: uses `fetchAll()`; merges the device-only
  `SensitiveProfile` (`excludedFoods`, D-55) into the exported profile explicitly via `mergeSensitive`.
- `mobile/lib/features/data_export/data_export.dart`: file note when `pagingIncomplete`.
- `mobile/lib/features/account_deletion/data/local_data_wipe.dart`: per-uid keys under the prefixes
  `data_notice.`, `body_scan.`, `nutrition.`, `food_diary.`, `weight.` ending in `.<exact uid>` are wiped
  (covers `data_notice.v<N>.<uid>` of every version). `scans/` sidecars and `meals/` thumbnails live inside
  `progress_photos/<uid>/`, which the existing step already deletes recursively.
- In-flight writers: `accountBeingDeletedUidProvider` is already read by the scan capture, scan history
  actions, body-scan job provider, weight, plan, review scheduler and diary providers (verified by grep);
  `mobile/lib/features/food_diary/**` is owned by C23 and was not touched.

## Verification state
Not run. No new Dart tests were written (test agents own them).
