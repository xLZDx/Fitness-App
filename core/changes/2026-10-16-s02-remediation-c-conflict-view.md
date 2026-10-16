# S02 remediation C: conflict view error handling (FL1, FL2)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/activity_sync_repository.dart`: `watch()` now reports a failed refresh with `addError` instead of leaving an unhandled async error and no state. `_conflictView` adds a generic catch after the Unavailable/Corrupt handlers: any other backend error yields `cloudKnown: false` (not cached).
- `mobile/lib/features/activity/state/sync_conflict_presenter.dart`: the view state gains `loaded` and `loadFailed`; the stream listener has `onError`; `retry()` re-subscribes.
- `mobile/lib/features/activity/widgets/sync_conflict_sheet.dart`: progress indicator until the first emission, an error text with a retry button after an error, the "everything is in sync" text only for a loaded empty state. Existing l10n keys are reused (`activitySyncCloudUnavailable`, `commonRetry`).
- `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md` (new): what tests must assert.

## Why
Flutter review findings FL1 (a permission-denied backend error or a journal I/O error left the view in a false empty state) and FL2 (empty text shown before the first emission, no error or retry state).

## Affected contracts and paths
Flag-off behaviour is unchanged (none of this code runs without `ACTIVITY_CLOUD_STREAMS`). `SyncConflictViewState` has two new defaulted fields.

## Verification state
Not run in this commit by design; the test agents write and run the tests listed in the test notes.
