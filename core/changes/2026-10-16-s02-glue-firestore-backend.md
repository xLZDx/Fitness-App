# S02 glue: Firestore summary backend and cloud-sync flag

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/core/config/activity_flags.dart` (new): `ActivityFlags.cloudSync`, compile-time `ACTIVITY_CLOUD_STREAMS` (default OFF, design 12.1), exposed through `activityFlagsProvider` (same pattern as `BodyScanFlags`).
- `mobile/lib/features/activity/repository/firestore_activity_summary_backend.dart` (new): Firestore implementation of the `ActivitySummaryBackend` seam over `users/{uid}/activities/{id}` and `users/{uid}/activity_tombstones/{id}`. Reads use the server source. `permission-denied` on a write becomes `SummaryWriteDenied`; every other failure, a timeout or a missing/anonymous sign-in becomes `SummaryBackendUnavailable`. `writeSummaries` writes at most 8 summaries per batch and throws `SummaryBatchTooLarge` otherwise; `writeSummary` delegates to it.

## Why
S02 design 3.2 and 6.2 require a production adapter behind the seam that the sync layer already uses.

## Affected contracts and paths
Additive: two new files. Nothing reads them yet (wiring follows in the next commit), so the default build is unchanged.

## Verification state
No tests, analyzer or build were run (operator rule: checks run later by the test agents). Not verified: compilation against the installed cloud_firestore version.
