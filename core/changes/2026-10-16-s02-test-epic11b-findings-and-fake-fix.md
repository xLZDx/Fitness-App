# S02 test epic 11b: findings section and stale fake fix

## What
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart`: the `_FlakyJournal` fake forwards `listTombstones()` (called by `refreshState()` since remediation E2).
- New `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md` with the epic 11b section (files, defects, exact commands and summary lines, what remains).

## Why
The complete run of the epic found 4 failures from the stale fake. Agent 11a may append its own section to the findings file.

## Affected paths
The two files above.

## Verification state
Dart run `+91: All tests passed!`; jest `Tests: 791 passed, 791 total` (commands in the findings file).
