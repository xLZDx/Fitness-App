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
