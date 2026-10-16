# S02 remediation J3b: class sweep findings in the client activity calls

Date: 2026-10-16. Branch: phase2/s02-unified-activity. Base head: 01b9223c (J3a).

## What changed

- B1 `activity_cloud_settings_client.dart`: `isGranted` also requires a non-null `consentUid`; `load()` ignores the read result while the store is unbound.
- B2 same file, `ActivityConsentWithdrawal.withdraw()`: account guard first, `cancelQueued()` only after it passes; after a successful withdrawal `_deleteRequested.remove(uid)` re-arms the delete offer. Doc comments updated.
- B3 `activity_sync_repository.dart`: a `ConsentAccountChangedException` from the tombstone pusher while the pass is alive sets `anyFailed` and the neutral code `account-changed` and leaves the loop, so the normal backed-off retry runs. No `_failedTombstones` entry, no `_lastTombstonePushError`. A stale pass still returns `aborted`. `_kSystemicCodes` does not contain the code; the retry budget advances as for any retry.
- B4 `sync_conflict_presenter.dart`: `resolveCandidate` and the conflict choices return without calling the repository when the tap-time uid is null.
- B5 `activity_stream_uploader.dart`: `_runPending` and `_uploadEntry` end/return `cancelled` when a bound uid exists and the scoped journal is not bound to it, before the first journal read. `_journalBoundTo` already returned true for a plain journal and for an unbound uploader.
- Docs: design item 25 paragraph (e) J3 client; test notes section "CLIENT (J3b, Dart)".

## Why

Three independent reviewers swept the whole activity surface for calls where the identity is ambient instead of carried with the operation, and found these client gaps.

## Affected contracts

No signature changes. Behavior changes listed in the test notes (refused withdraw no longer cancels the uploader; transient account-changed tombstone push schedules a retry; unbound store is never granted; null-uid conflict tap is a no-op; mismatched scoped journal is never read).

## Verification state

NOT RUN. No test, analysis or build was executed. Independent review pending.
