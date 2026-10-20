# S02 remediation F2 (1/4): no rebind of a wiped account

## What changed

`mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart`:

- `AccountScopedJournal` gains `String? get boundUid;` and `bool get isBound;` (consumed by the sync repository in remediation F1). `UidScopedActivityJournal` implements both.
- `wipeForUid(uid)` for the currently bound uid remembers it in `_wipedUid` (also when the wipe fails). `bindUid(uid)` for that uid returns false and creates no directory and no key until `bindUid(null)` or another uid is bound, which clears the memory.

## Why

A same-uid auth re-emission (token refresh, `userChanges`) after account deletion re-created the deleted account's journal scope and its key (reviewers security 3 and Flutter 3).

## Contracts and paths

Public: `AccountScopedJournal.boundUid`, `AccountScopedJournal.isBound`. Behaviour: `bindUid` fails closed for a wiped uid. Implementers to update: see `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`.

## Verification state

Not compiled and not run (operator rule: a test agent compiles and runs afterwards). Required tests are listed in the F2 test notes.
