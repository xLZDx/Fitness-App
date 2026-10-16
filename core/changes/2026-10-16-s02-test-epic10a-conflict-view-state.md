# S02 test epic 10a: conflict view state tests (FL1, presenter side of FL2)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart` (new, 7 tests):
  - `watch()` with a `FirebaseException` permission-denied from `readSummary`: one state with the conflict, `cloudKnown: false`, no fields, no zone error, no stream error; the failed read is not cached.
  - `watch()` with a throwing journal `list()`: a stream error, no zone error, no state emitted.
  - Presenter: `loaded`/`loadFailed` before the first emission, after a list failure, `retry()` re-subscribes and a following emission carries the conflict, a repeated failure returns to `loadFailed`.

## Why
Oracles are `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md` items FL1 and FL2 (remediation C, commit 0b6a2aa0), which had never been compiled or run.

## Affected contracts and paths
Test-only. No production code changed in this commit.

## Verification state
`flutter test test/features/activity/state/sync_conflict_view_errors_test.dart` passes (7 tests). See `docs/phase2/s02/S02_TEST_FINDINGS_EPIC10.md` for the final run.
