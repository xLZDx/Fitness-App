# S02 test epic 10b: wiring account-switch tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/repository/activity_wiring_account_switch_test.dart` (new, 20 tests): `activityCloudSyncWiringProvider` calls `cancelQueued()` on uid A -> B, A -> null and A -> guest (not on first sign-in or a same-uid re-emission); `resume()` only after a successful claim and only while the auth uid is still the claimed one; a failed claim (marker write or previous-owner wipe) calls neither `resume`, `syncAll` nor `runPending`; exceptions in `resume`, `syncAll` and `settings.load` are logged and do not escape (FL6); with the flag off, or only `localJournal` on, the listener has no side effects.

## Why
Remediation C (FL5 wiring, FL6); oracle `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md`.

## Affected contracts and paths
Tests only.

## Verification state
Run by the author: 20 tests, all passed.
