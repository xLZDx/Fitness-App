# S02 test epic 11b: tombstone continuation (remediation E2) and account change

## What
- New `mobile/test/features/activity/repository/activity_tombstone_continuation_test.dart` (34 tests) over the real `FileActivityJournal` (in-memory file system of the journal harness, counting subclass), a fake backend, a fake pusher and a fake timer factory: backlogs of 9, 30, 100, 1000 (2, 4, 13, 125 rounds), 8 and 1024 boundaries, 1100 (1024 first, 76 pending, one 60 s timer), restart resume, quota and other systemic refusals, partial failures and bad-id-last ordering, unknown tombstone list, the 60 s to 15 min backoff with no seventh attempt, dispose and cancel, `watch()` observability, and the existing semantics (server tombstone, fence refusal, denial without tombstone).
- Production fix in `activity_sync_repository.dart`: `onAccountChanged()` plus an epoch counter. It cancels the retry timer, clears the confirmed and failed id sets, the backoff budget and the last error, and a pass in flight pushes nothing more and schedules nothing.
- One line in `activity_wiring.dart` (`activityCloudSyncWiringProvider`, account-change block) calls `onAccountChanged()`. That file is also being edited by agent 11a; the line lands with 11a's commit of that file.

## Why
Evidence from the code: the repository is one instance per process and the retry timer, `_confirmedTombstones` and the backoff budget were never reset on sign-out or uid change (nothing called `cancelTombstoneRetry()`). Ids are deterministic, so an id confirmed for account A would never be pushed for account B, and A's timer would run an unattended pass under B.

## Affected paths
- `mobile/test/features/activity/repository/activity_tombstone_continuation_test.dart`
- `mobile/lib/features/activity/repository/activity_sync_repository.dart`
- `mobile/lib/core/wiring/activity_wiring.dart` (one line, committed with agent 11a)

## Verification state
Run with flutter test, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`. The wiring test in the new file needs agent 11a's compile fix of `activity_wiring.dart`.
