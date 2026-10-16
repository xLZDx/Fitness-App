# Settings client tests for the invocation-bound identity and findings 16b (epic 16b, 2/3)

Date: 2026-10-16. Kind: new tests and test findings.

## What changed
- New mobile/test/features/activity/repository/activity_settings_client_expected_uid_test.dart (33 tests): expectedUid in the request map; start refusals (live uid B or null); a live-uid supplier that flips A to B at the pre-call check, the post-call check and during the write, for grant, withdraw and deleteCloudStreamsNow, each with an identical and a different prior consent of B; authMatchesAccount truth table; withdrawal presenter guard before cancelQueued, re-arm of the delete offer; isGranted and load with an unbound store; cloudFunctionsSettingsCall mapping of `account_changed` through a faked FirebaseFunctions, `account_deleting` and other refusals not mapped.
- docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md: section 16b appended.

## Why
Remediation J2 and J3b change the settings client contract; these tests fail if a guard, the expectedUid key, the guard order or the re-arm is removed.

## Affected contracts and paths
Test code and documentation only.

## Verification state
See the 16b section of the findings file for commands and verbatim result lines.
