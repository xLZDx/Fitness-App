# S02 test epic 15: stale assertions after remediation I

Date: 2026-10-16. Head under test: 61389563 (remediation I, never compiled by its author).

What changed: the baseline run of the whole activity directory compiled and showed 27 failing tests, all caused by the two intended contract changes of remediation I (early consent bind; `grant`/`withdraw` on an unbound store throw). Fixed in tests: `InMemoryCloudStreamsConsentStore(boundUid: 'uid')` in `activity_consent_withdrawal_test.dart` and `activity_stream_upload_test.dart`; new start order (`signIn`, `load`, bind, `sync`, `resume`, `run`) and "consent load failure no longer blocks bind and sync" in `activity_consent_switch_wiring_test.dart`, `activity_wiring_account_switch_test.dart`, `activity_journal_wipe_wiring_test.dart`, `s02_consent_switch_e2e_test.dart`.

One production fix: `mobile/lib/core/wiring/activity_wiring.dart` lost the `account is being deleted; sync not started` log because the new early `current()` check returns before the scoped-journal branch that logged it; the early check now logs it when the signed-in uid is the one being deleted (`activity_republish_wiring_test.dart` G4).

Affected contracts: none beyond remediation I. Verification: ten affected test files rerun together, all green (see docs/phase2/s02/S02_TEST_FINDINGS_EPIC15.md).
