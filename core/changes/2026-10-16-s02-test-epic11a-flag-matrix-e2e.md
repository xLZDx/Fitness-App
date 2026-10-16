# S02 test epic 11a: flag matrix and account wipe e2e on scoped journals

## What changed

- `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart`: owner store symbols removed; `openActivityJournal` is asserted to return an unbound `UidScopedActivityJournal` with no disk I/O; the start-up group uses the real scoped journal: flags off or localJournal only bind nothing in the sync wiring, localJournal only WITH the binding listener binds the uid with no network call, cloud flags bind the uid and sync.
- `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart`: `ownerStore:` removed; two new tests: deleting account A through `AccountDeletionAction` wipes only A's scope and key (B byte-identical and still bound); a relaunch with a pending wipe of A while B is signed in wipes only A.

## Why

These files referenced symbols removed by remediation E1. Oracles: E1 test notes, design 6.2, 7, 17.

## Verification

`flutter test test/features/activity/e2e/s02_account_wipe_e2e_test.dart test/features/activity/config`: all passed (48). Final complete run in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`.
