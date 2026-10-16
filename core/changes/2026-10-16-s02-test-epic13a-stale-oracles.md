# S02 test epic 13a: stale oracles and fakes after remediation G

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: tests only.

## What changed

- Four epic 9 to 12 tests expected `bindUid(uid)` to succeed right after `wipeForUid(uid)` of an UNBOUND uid;
  remediation G4 records the wiped uid in both branches, so the bind is refused until `bindUid(null)` or
  another uid. Updated to the G4 contract: `uid_scoped_activity_journal_test.dart` (2 tests),
  `uid_scoped_journal_wipe_rebind_test.dart` (1), `s02_account_wipe_e2e_test.dart` (1).
- `activity_wiring_account_switch_test.dart`: `_ThrowingSyncRepo` implements `onJournalBindingChanged()` and
  records both `onAccountChanged` and `onJournalBindingChanged`.
- New section file `docs/phase2/s02/S02_TEST_FINDINGS_EPIC13.md`.

## Why

First compiled run of the whole `test/features/activity` directory at fc63ec62 gave `+1260 -4`; all four were
stale oracles, no production defect.

## Verification state

The four edited files together: `+89: All tests passed!`.
