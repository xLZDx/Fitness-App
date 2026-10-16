# test(s02): add expectedUid helper and handler tests (epic 16a)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
New `functions/src/__tests__/activity/expected_uid.test.ts` (unit tests of `verifyExpectedUid`) and `expected_uid_handlers.test.ts` (the four handlers: mismatch writes and charges nothing and logs `account_changed` without a uid, mismatch wins over an invalid request and an exhausted quota, missing or malformed key gives `invalid_request`, non-object data, matching key success, strict settings parser, anonymous gate first, onCall wrapper refuses a missing auth).

## Why
Remediation J1 added behavior with no tests; the J test notes list the required cases.

## Affected contracts and paths
Tests and documentation only: `functions/src/__tests__/activity/expected_uid.test.ts`, `functions/src/__tests__/activity/expected_uid_handlers.test.ts`. No product code.

## Verification state
88 tests in the two new files passed (88 total). Broader sets are recorded in docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md.
