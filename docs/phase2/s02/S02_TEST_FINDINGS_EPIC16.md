# S02 test findings: epic 16 (remediation J)

Head at start: 0e687439 (server code unchanged since 1f2cbf3f). Branch: `phase2/s02-unified-activity`.

## 16a server (remediation J1, `expectedUid`)

### What was changed (existing tests)
- `functions/src/__tests__/activity/support/flow.ts`: new `withUid(data, uid)` adds `expectedUid: uid` to a plain object that does not carry the key; non-object data and an explicit key (right or wrong) pass through untouched. `create` and `commit` use it.
- `functions/src/__tests__/activity/support/seven.ts`: the four J1 entries (`createActivityStreamUpload`, `commitActivityStream`, `deleteActivity`, `setActivityCloudSettings`) use `withUid`; the other three entries are unchanged.
- No individual test needed an edit: the activity suites reach the four handlers only through these two files. F60 id and bytes cases now prove the original checks because the key is present.

### What was written
- `functions/src/__tests__/activity/expected_uid.test.ts` (unit, helper): match returns a copy without the key, input not mutated, unknown keys kept; 128 characters accepted; mismatch and case-different uid give `account_changed`; missing, null, number, object, array, boolean, empty and 129-character keys give `invalid_request` (also when equal to the uid, so shape precedes equality); non-object data returned unchanged.
- `functions/src/__tests__/activity/expected_uid_handlers.test.ts` (handlers, each of the four): mismatch is `failed-precondition` / `account_changed` with the Firestore store, write log, operation timeline, bucket calls, Auth lookups and both users' usage counters unchanged; the log has outcome `account_changed` and no uid or activity id; mismatch wins over an invalid rest of the request and over an exhausted quota (with a control call proving the quota really is exhausted); missing and malformed keys and non-object data give `invalid-argument` / `invalid_request` with nothing touched; a matching key charges exactly once and has the normal effect; the settings strict parser still refuses `uid` next to a valid key; a caller as UID_B with UID's key is a mismatch; an anonymous caller with a mismatching key gets `permission-denied` / `anonymous_not_allowed`; the `onCall` wrapper refuses a missing auth as `unauthenticated` / `sign_in_required`.

### Commands and verbatim results (run from `functions/`)
| Command | Result |
|---|---|
| `npx jest src/__tests__/activity/expected_uid src/__tests__/activity/support` | `Test Suites: 2 passed, 2 total` / `Tests:       88 passed, 88 total` |
| `npx jest src/__tests__/activity src/__tests__/abuse_guard.test.ts src/__tests__/callable_hardening.test.ts` (final run) | `Test Suites: 1 failed, 28 passed, 29 total` / `Tests:       1 failed, 878 passed, 879 total` |
| `npx jest src/__tests__/activity/remediation_a_validate_bound.test.ts` (the one failing suite, alone) | `Test Suites: 1 passed, 1 total` / `Tests:       6 passed, 6 total` |
| `npx jest src/__tests__/s02_remediation_a_policy.test.ts src/__tests__/scaling.test.ts src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts src/__tests__/firestore_indexes_body_scan.test.ts` | `Test Suites: 5 passed, 5 total` / `Tests:       315 passed, 315 total` |

A file `src/__tests__/callable_hardening.test.ts` does not exist; the one that exists (`src/__tests__/activity/callable_hardening.test.ts`) is inside the activity directory run.

### Findings
1. Load-sensitive timeout, not a J1 defect: `remediation_a_validate_bound.test.ts` "a 32 MiB comma filler is rejected too_many" exceeded the 5000 ms test timeout in both parallel runs of the activity directory (first run after the central fix: 744 passed, 1 failed; final run: 878 passed, 1 failed) and passed when run alone. It exercises `validateUploadedStream` only, no J1 code. The specified run is therefore not fully green. Not changed (outside this epic); recommended fix: a longer timeout for that test.
2. Test-notes inaccuracy (not a product defect): the notes say the strict parser refuses an unknown extra key with a valid `expectedUid` for all four handlers. Only `setActivityCloudSettings` is strict. `createActivityStreamUpload`, `commitActivityStream` and `deleteActivity` ignore unknown keys (existing F60 behavior, pinned in `callable_hardening.test.ts`). The new tests assert the strict refusal for settings and, for the other three, that an extra `uid` key is ignored and never used as the account.
3. Observation: `verifyExpectedUid` reads the key by destructuring, so an inherited prototype property would count as present. Callable data is JSON-decoded and cannot carry one, so this is not reachable; no test pins it.
4. No product defect was found in J1.

### Not covered
- The red state of the existing tests before the central fix was not observed (the fix was applied before the first run); the stale-test list in the notes was not confirmed by a failing run.
- No mutation run (not permitted); each assertion is justified by what it observes, not by a broken-code run.
- Not run: the whole repository suite, lint, typecheck, build, CI, the rules emulator. `getActivityStreamDownloadUrls`, `deleteAllActivityStreams` and telemetry are out of J1 scope and are not tested for the key.
- The client half (16b) is not part of this section.

## 16a2 server (J3a)

Head under test: a3530664 on top of 7f15f7db (J3a product change is 01b9223c). Author: Claude Sonnet 5.5 (test agent).

### What was changed (existing tests)
- `support/seven.ts`: `getActivityStreamDownloadUrls` uses `withUid`; `deleteAllActivityStreams` passes its body as the 4th argument (`{ expectedUid: uid }` when the table body is undefined, otherwise `withUid(d, uid)`).
- Call sites: `account_flow.test.ts`, `export_downloads_telemetry.test.ts` (key equals the helper's own `uid` argument), `remediation_a_reconcile.test.ts` (3), `settings_consent.test.ts` (2), `sweeps_jobs.test.ts` (2; `lim(...)` moved to the 5th argument).
- Found by the extra Grep, not in the notes: `callable_hardening.test.ts` asserted that `deleteAllActivityStreams` ignores a client body (`{ activityId: "../x", uid }` -> `done`). That would now be wrong; it asserts `invalid-argument / invalid_request` and keeps a control that `{}` still returns `done`.

### What was written
`functions/src/__tests__/activity/expected_uid_more_callables.test.ts` (43 tests), for both handlers: mismatch is `failed-precondition / account_changed` with no `firestore()` seam call (no read), no write, no timeline entry, no storage or auth call, no quota document, warn log with outcome `account_changed` and no uid or activity id; case-different key; mismatch beats an invalid body (with a control that the same body is `invalid_request` under the right key) and an exhausted quota (with a control that the right key gives `quota_exceeded`); anonymous gate first with a mismatching key (no `account_changed` log); missing, null, number, object, empty and 129-character key; non-object data (null, undefined, array, string, number); matching key succeeds and charges once; download with a bad id; deleteAll with an extra key or client path fields; real `onCall` wrapper (`unauthenticated`, and mismatch through `.run`). Structural scan `scanHandlers`: all seven exported `onCall` handlers are found, exactly `sendDebugTelemetry` (exempt, with reason) lacks `verifyExpectedUid(` before its first `await`; five synthetic-source self-checks prove the scan fails for an await-first handler, a missing call, an unresolved handle function and a verification that lives in a different function.

### Commands and verbatim results (run from `functions/`)
| Command | Result |
|---|---|
| `npx jest src/__tests__/activity/expected_uid_more_callables.test.ts src/__tests__/activity/callable_hardening.test.ts src/__tests__/activity/account_flow.test.ts src/__tests__/activity/export_downloads_telemetry.test.ts src/__tests__/activity/remediation_a_reconcile.test.ts src/__tests__/activity/settings_consent.test.ts src/__tests__/activity/sweeps_jobs.test.ts` (final) | `Test Suites: 7 passed, 7 total` / `Tests:       321 passed, 321 total` |
| `npx jest src/__tests__/activity src/__tests__/abuse_guard.test.ts` | `Test Suites: 2 failed, 28 passed, 30 total` / `Tests:       3 failed, 919 passed, 922 total` |
| `npx jest src/__tests__/activity/remediation_a_validate_bound.test.ts` (alone) | `Tests:       6 passed, 6 total` |
| `npx jest src/__tests__/s02_remediation_a_policy.test.ts src/__tests__/scaling.test.ts src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts src/__tests__/firestore_indexes_body_scan.test.ts` | `Test Suites: 1 failed, 4 passed, 5 total` / `Tests:       2 failed, 313 passed, 315 total` |

### Findings
1. DEFECT (J3a product-side leftover, not a test problem): the data-access policy checker `scripts/ci/check_data_access_policy.js` pins the allowlist entry for `functions/src/activity_streams/delete_all_streams.ts` to line 201. The J3a edit moved that `.collection(\`users/${uid}/activity_streams\`)` call to line 203, so the checker now reports `functions/src/activity_streams/delete_all_streams.ts:203` as a sixth violation. Three tests fail because of it: `s02_remediation_a_policy.test.ts` ("the repository run reports exactly the five pre-S02 violations" and "the unmutated copy gives the same five violations") and `activity/lifecycle_policy.test.ts` ("the access policy checker reports nothing about any S02 file"). I did not edit the checker (not a test file). Required change: set `line: 203` in that allowlist entry (line 250 of the checker); acceptance: the three tests above go green. Not re-run after a fix because I did not make it.
2. Load-sensitive timeout, known flake: `remediation_a_validate_bound.test.ts` (32 MiB filler and the comma filler) failed in the parallel run and passed alone (`6 passed`). No timeout was changed.
3. The J3 notes list of stale call sites was complete for call sites; the stale assertion in `callable_hardening.test.ts` was not listed.
4. Two of my own first-run test bugs (unused variable; log assertion without `mockClear`) were fixed in the test; no product defect behind them.

### Not covered
- The red state of the changed existing tests before the fix was not observed (edits were applied before the first run).
- No mutation run (not permitted); assertions are justified by what they observe. `sendDebugTelemetry` is exempt and untested for the key by design.
- Not run: the whole repository suite, lint, typecheck, build, CI, the rules emulator. The client half (J3b) is not part of this section.

## 16b Dart settings client (J2 and J3b), test agent

Head before: 5ec1acc1. Commits: 3239e4d4 (compile fixes), then the new tests commit (see git log).

### What changed
- Compile fixes (commit 3239e4d4): helper `storeUid(store)` and `expectedUid` recording in `mobile/test/support/stream_upload_world.dart`; `currentUid: storeUid(store)` in six test files; two-argument tombstone pusher closures in ten files; `FakeStreamCloudStub` takes `expectedUid`.
- Stale assertion fixed: the presenter test of `activity_sync_pass_identity_test.dart` (group C) tapped without a uid; J3 B4 makes that a no-op, so the test now overrides `syncConflictUidProvider` with `'A'`.
- New file `mobile/test/features/activity/repository/activity_settings_client_expected_uid_test.dart`, 33 tests (list in core/changes/2026-10-16-s02-test16b-2-settings-client-tests.md). The A to B flip uses a supplier answering A for N reads: grant N=1 (pre-call), N=2 (post-call), N=3 (after the write); withdraw N=1 (call not sent, A stays locally withdrawn, nothing for B), N=2; deleteCloudStreamsNow N=0, 1, 2. Each runs with B prior granted (identical to the usual A value) and withdrawn (different) and asserts zero requests carrying another uid, no write for B, B's stored value unchanged, and for delete that the refused call leaves no requested key (a later call under A sends exactly one).
- The server refusal is tested through a faked `FirebaseFunctions` and `HttpsCallable` (`Fake implements`), so the real `cloudFunctionsSettingsCall` code runs.

### Commands and verbatim results
1. All 15 touched existing files, first run (before the presenter fix): `flutter test --timeout 60s test/features/activity/e2e/s02_consent_switch_e2e_test.dart ... test/features/activity/repository/activity_tombstone_sync_test.dart` -> `00:33 +238 -1: Some tests failed.` (the one failure: the presenter test, fixed as above).
2. New file: `flutter test --timeout 60s test/features/activity/repository/activity_settings_client_expected_uid_test.dart` -> `00:00 +33: All tests passed!`
3. `flutter test --timeout 60s test/features/activity/repository` -> `01:22 +749: All tests passed!`
4. `flutter test --timeout 60s test/features/activity/e2e/s02_consent_switch_e2e_test.dart test/features/activity/e2e/s02_auth_flip_e2e_test.dart test/features/activity/e2e/s02_pass_account_switch_e2e_test.dart test/features/activity/e2e/s02_delete_wins_e2e_test.dart` -> `00:07 +29: All tests passed!`

### Findings
1. Only one older assertion changed behavior in the files run (the presenter, B4). The J3b notes predicted more places (withdraw with cancelQueued on a refused call, unbound isGranted, tombstone retry on account-changed, uploader journal tie); no existing test failed on them, so those behaviors had no prior test that pinned the old behavior. The tombstone retry and uploader journal tie are for part 16c.
2. No product defect found in the settings client.

### Not covered
- Red-before-fix was not observed (no mutation or revert runs, by rule).
- `cloudFunctionsSettingsCall` success path (the SDK result type has a private constructor); only failure mapping and the request map passed to the callable are asserted.
- Wiring-level check that `activityCloudSettingsClientProvider` passes a live-uid supplier (needs Firebase) and parts 16c: uploader, tombstone push, real stream client and pusher.
- The third grant flip test (flip during the write) accepts `unknown` or `granted` for the cache but asserts nothing is written for B and the cache is not attributed to B.
