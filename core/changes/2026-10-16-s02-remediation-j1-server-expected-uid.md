# S02 remediation J1: server callables bound to the initiating account

Date: 2026-10-16. Kind: production change (server half) plus design and test notes.

## What changed
- functions/src/activity_streams/expected_uid.ts (new): pure helper `verifyExpectedUid(uid, data)`; returns a shallow copy of the request data without the `expectedUid` key after verifying it; non-object data is returned unchanged.
- functions/src/activity_streams/set_settings.ts, create_upload.ts, commit_stream.ts, delete_activity.ts: each exported `handle...` pipeline calls the helper right after the anonymous gate and before the strict parse, the feature or bucket check, the quota charge and every read or write. A mismatch throws `failed-precondition` / `account_changed` (logged as outcome `account_changed`, no uid); a missing or malformed key gives the handler's existing `invalid-argument` / `invalid_request`.
- docs/phase2/s02/S02_DESIGN.md: section 5.4 lists `expectedUid`; section 17 item 25 (remediation J) added.
- docs/phase2/s02/S02_REMEDIATION_J_TEST_NOTES.md (new): SERVER section for the test agent (behavior, order, error pair, stale tests, new tests); empty CLIENT section for J2.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, document registry.

## Why
GPT-PM round 13 (MAJOR): the Dart consent client checks only the locally bound uid, but the callable runs as whoever is signed in when the token is read, and the server resolves the account from `request.auth`. A sign-in flip between the check and the call applies account A's action to account B. The initiating account must travel with the call.

## Affected contracts and paths
- Callable request contract of `setActivityCloudSettings`, `createActivityStreamUpload`, `commitActivityStream`, `deleteActivity`: new REQUIRED key `expectedUid` (string, 1 to 128 characters). Breaking for any client that omits it; no deployed client exists (both flags are off). The Dart client (J2) is NOT updated in this commit and will be refused by these callables until J2 lands.
- New error pair: `failed-precondition` with message `account_changed` (the code is shared with `account_deleting` and other refusals; the message discriminates).
- `expectedUid` is a consistency check for an honest client racing its sign-in transition, not the authorization boundary (that stays `request.auth`).
- Not changed: `getActivityStreamDownloadUrls`, `deleteAllActivityStreams`, telemetry, rules, indexes, mobile/.

## Verification state
NOT RUN. No test, lint, typecheck or build was executed. Existing jest suites that call these handlers without `expectedUid` are expected to fail until the test agent updates `support/seven.ts` and `support/flow.ts` (listed in the test notes). Test agent pending.
