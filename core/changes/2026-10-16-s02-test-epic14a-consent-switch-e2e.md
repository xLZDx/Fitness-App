# S02 test epic 14a: consent switch end-to-end test

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
New `mobile/test/features/activity/e2e/s02_consent_switch_e2e_test.dart` (2 tests): the real `FileActivityJournal` per-account scopes on a temp directory, the real sync repository, the real `AccountScopedConsentStore` and `ActivityCloudSettingsClient` over a gated fake preferences platform store, the real `ActivityStreamUploader` with a recording cloud, and the real startup closure. A has stored consent granted, B none; A's startup stalls in `syncAll` while B signs in. Oracle (the promise "my GPS data is never uploaded under another account's consent"): zero create, PUT and commit, B's stream marker unset, A's marker and stored consent untouched. A control test shows the same world uploads for A alone.

## Why
Remediation H-A external finding (round 12): the consent cache was not bound to the account.

## Affected contracts and paths
Test code only.

## Verification state
`flutter test --timeout 60s test/features/activity/e2e/s02_consent_switch_e2e_test.dart` gave `+2: All tests passed!` (first run `+1 -1`: my oracle assumed B's chain proceeds while A's sync pass is held, but the sync repository is single-flight, so B waits for A's pass; the test now releases A first).
