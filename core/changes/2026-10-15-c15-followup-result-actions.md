# Change record: C15 follow-up, result actions, resume card, nutrition card mount

## What changed
- `mobile/lib/features/body_scan/widgets/result_view.dart`: optional `onHistory`, `onEditWeight`, `onDeletePhotos`; each button renders only when wired (existing keys `bodyScanHistoryTitle`, `bodyScanHistoryActionEditWeight`, `bodyScanHistoryActionDeletePhotos`; no new ARB keys).
- `mobile/lib/features/body_scan/body_scan_result_page.dart`: finds the `ScanHistoryRow` of the open scan in `scanHistoryRowsProvider` (by `row.id == scanId`) and wires History (`/body-scan/history`), `editScanWeightFlow` and `deleteScanPhotosFlow`. When no row is found the two actions are hidden.
- `mobile/lib/features/body_scan/widgets/body_scan_entry_card.dart` (the owner of the `ResumeScanCard` callbacks on Progress): Cancel and Delete now call `ScanHistoryActions.deletePhotos` (cloud delete first, `pendingRemoteDelete` when offline, runner `forget`) instead of only `ScanRepository.delete`, with the same outcome snackbars. Resume calls `runner.resume()`, Retry calls `runner.retry(id)`, then both push `/body-scan?scanId=<id>`.
- `mobile/lib/features/nutrition_plan/widgets/nutrition_entry_card.dart`: new `compact` flag (smaller title, two-line body).
- `mobile/lib/features/progress/progress_page.dart` and `mobile/lib/features/home/home_page.dart`: mount `NutritionEntryCard` (compact on Home) under the Body check-in card. Titles differ ("Nutrition plan" vs "Body check-in").

## Notes
- `ResumeScanCard` itself is a pure widget with callbacks and is unchanged.
- The `/body-scan` route ignores the `scanId` query for now; the flow page still opens at the intro. Consuming the id in the flow page is not part of this change.
- Test item: no test in `mobile/test` taps `scan.entry.start` and expects `/photos/scan`; the only `/photos/scan` hit is a router redirect test, which is unaffected. No test edits made.
- `core/DECISION_LOG.md` also carries other sessions' uncommitted entries (C18, C25) that are included by the path-limited commit.

## Verification state
Not run (operator rule).
