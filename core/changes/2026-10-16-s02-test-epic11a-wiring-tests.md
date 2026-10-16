# S02 test epic 11a: wiring and decorator tests rewritten for bindUid, compile fix

## What changed

Production (smallest change, defect D1 of epic 11a):

- `mobile/lib/features/activity/repository/activity_aware_local_data_wipe.dart` and `mobile/lib/core/wiring/activity_wiring.dart` (two places): `journal is AccountScopedJournal` does not promote an `ActivityJournal` variable to the unrelated interface `AccountScopedJournal` in Dart, so `bindUid` and `wipeForUid` were undefined and the app did not compile. Replaced by pattern matching (`case final AccountScopedJournal scoped`), same behaviour.

Tests (removed symbols `activity_journal_owner.dart`, `claimActivityJournal`, owner store and `ownerStore:` are gone from these files):

- `activity_journal_wipe_wiring_test.dart`: decorator on the real scoped journal (deleted uid's scope while another uid is bound, failed wipe reported as `activity_journal` with the pending marker kept and a retry, plain journal fallback to `wipe()`, inner `LocalWipeIncomplete` ordering, relaunch with a pending wipe while another account is bound) and the cloud wiring (bind before resume, fail closed on a failed bind).
- `activity_wiring_account_switch_test.dart`: cancel/resume ordering, bind-before-resume, mid-bind account change, nothing escapes the closure, flag off, and the always-on binding listener (anonymous binds, sign-out unbinds without deleting, only `localJournal` constructs no network objects, loading and error change nothing, rapid switches).

## Why

Remediation E1 removed the owner marker; these tests expressed the old behaviour. Oracles: E1 test notes, design 6.2, 7, 17, lessons log.

## Verification state

Both files pass individually; the complete run is recorded in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`. The flag matrix and account wipe e2e tests are rewritten in the next commit of this epic.
