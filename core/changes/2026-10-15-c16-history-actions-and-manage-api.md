# Change record: C16 part 1, history rows, actions, manage API, compare start

## What changed
- `mobile/lib/features/body_scan/state/body_scan_manage_api.dart`: client of the `manageBodyScanData` callable (`applyRetention`, `deleteAllPhotos`, `deleteAllScans`), looping over `nextCursor` pages (max 500), errors mapped to closed slugs (D-67). Provider `bodyScanManageApiProvider` (constructing it touches no Firebase API).
- `mobile/lib/features/body_scan/state/scan_history_rows.dart`: pure `buildHistoryRows` merging local records and server entries into one row per scan; baseline marker, change label and "new estimator" marker derived from the segmented trend (D-54, D-73), never stored.
- `mobile/lib/features/body_scan/state/scan_history_actions.dart`: `deletePhotos` (cloud `deleteBodyScan(photosOnly: true)` first; on failure the record is saved with `pendingRemoteDelete` and kept on the phone until the runner flushes it; then the existing local delete path) and `editWeight` (local record plus re-derived provisional estimate, server `weightKg` when a document exists, and the same day's `weight_entries` row through `saveScanWeight`, D-72). Providers `scanHistoryActionsProvider`, `scanHistoryRowsProvider`.
- `mobile/lib/features/progress_photos/scan/ui/scan_compare_screen.dart`: extracted `deleteScanFiles` (shared with `confirmAndDeleteScan`, same behaviour), `ScanCompareStart` (`baseline` | `previous`) as the initial selection, and a second-scan prompt with a "take second scan" button when only the baseline exists.

## Why
Sprint plan commit C16; design s17, D-54, D-62, D-72, D-73, D-78.

## Deviations
An owed delete is executed by the existing runner as a full delete (tombstone), as designed for `pendingRemoteDelete`, so an offline "delete photos" ends with the server scan removed rather than only its photos.

## Affected contracts and paths
New l10n keys `bodyScanCompareBaselineOnly`, `bodyScanCompareTakeSecond` are added in the ARB commit of this story. The route query `?mode=` is wired in the routes commit.

## Verification state
Not run, per DEVELOPMENT RULES v4.

## Review state
Pending the test phase and specialist reviewers.
