# S02 test epic 14a: consent binding, uploader and startup interleaving tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head under test: 4f66324d plus d2a53815.

## What changed
- New `mobile/test/support/gated_prefs.dart`: a shared-preferences platform store whose n-th read waits on a Completer, so the open of the real `AccountScopedConsentStore` is held at an exact point.
- New `activity_consent_account_binding_test.dart` (25 tests): consent store (stale signIn, stale completion after sign-out, signOut keeps keys, write with no account throws, write during open), settings client with a scripted store (delayed load of A after B, isGranted binding, grant under A finishing after the switch, withdraw persistence and failure paths, withdraw before signIn completes, withdraw gated across a switch, deleteCloudStreamsNow once per account, reset/signOut keep every account's key), uploader (consentUid must equal the run uid, A granted then B unknown/withdrawn/stale sign-out with zero create/PUT/commit, A to B to A mark guards, upload_failed guard, deletion-in-progress before create, after create, after PUT).
- New `activity_consent_switch_wiring_test.dart` (17 tests): the real startup closure with recording fakes (A held in syncAll, in signIn, in load, in the journal bind; order bind, sync, signIn, load, resume, run; failed load; signOut+reset on raw uid change; deletion listener) and with the real client, store and uploader (A granted/B unknown, A granted/B withdrawn, A stalled in syncAll, A stalled in store init while B finishes first, B init delayed, stale completion after sign-out).

## Why
External gate round 12: the consent cache was not bound to the account and the startup closure did not re-verify the account after its awaits.

## Affected contracts and paths
Test code only.

## Verification state
`flutter test --timeout 60s test/features/activity/repository/activity_consent_switch_wiring_test.dart test/features/activity/repository/activity_consent_account_binding_test.dart` gave `+42: All tests passed!` (one earlier run `+41 -1`, see defect in the lessons log). Not covered: the `accountBeingDeleted` supplier wiring inside the real `activityStreamUploaderProvider` and `activityRootOverrides` (they build Firebase objects; no seam).
