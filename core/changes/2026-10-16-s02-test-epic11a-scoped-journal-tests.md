# S02 test epic 11a: account-scoped journal tests (remediation E1)

## What changed

- Added `mobile/test/support/scoped_journal_world.dart` (temp directory, real `FileActivityJournal`, fake secure store with one key per scope, recording factory).
- Added `mobile/test/features/activity/repository/uid_scoped_activity_journal_test.dart` (22 tests): A to B to A persistence, sign-out keeps data, hashed scope id and key name, production factory path, unbound reads and refused writes, `bindUid` idempotence and race serialization, fail-closed bind, copied-directory isolation, `wipeForUid` and `wipe` scope limits.

## Why

Remediation E1 replaced the device-wide journal and owner marker with account-scoped journals; the code had never been compiled or run. Oracles are the E1 test notes, design 6.2, 7, 17 and the lessons-log promise, not the code.

## Affected contracts and paths

Test files only under `mobile/test`. No production change in this commit.

## Verification state

`flutter test test/features/activity/repository/uid_scoped_activity_journal_test.dart`: 22 passed (see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md` for the final run).
