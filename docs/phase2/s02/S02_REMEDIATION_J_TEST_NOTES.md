# S02 remediation J: invocation-bound identity (test notes)

Status: SERVER half (J1) implemented, NOT RUN. Test agents write and run the tests. Design: `S02_DESIGN.md` section 17 item 25.

## SERVER section (J1, for the test agent)

### The helper

File: `functions/src/activity_streams/expected_uid.ts`. Exports `verifyExpectedUid(uid: string, data: unknown): unknown`, `ExpectedUidError` (`code`: `"invalid_request"` or `"account_changed"`), `EXPECTED_UID_KEY` (`"expectedUid"`), `EXPECTED_UID_MAX_LENGTH` (128). Pure, no I/O, no logging.

Exact behavior:
- `data` is not a plain object (null, undefined, array, string, number, boolean): returned UNCHANGED, no throw (the handler's own parser then refuses it with its existing error).
- `data` is an object and `expectedUid` is missing, not a string, an empty string, or longer than 128 characters: throws `ExpectedUidError("invalid_request")`. A string of exactly 128 characters is valid.
- `expectedUid !== uid` (exact, case-sensitive comparison): throws `ExpectedUidError("account_changed")`.
- `expectedUid === uid`: returns a SHALLOW COPY of `data` without the `expectedUid` key (the input object is not mutated; all other keys, including unknown ones, are kept so the strict parsers still reject unknown keys).
- Order of checks inside the helper: shape/length first, then equality (so a malformed key never reports `account_changed`).

### Handler order of checks (all four `handle...` functions)

1. Caller-side `onCall` wrapper: `request.auth` missing -> `unauthenticated` / `sign_in_required`; then `noteAppCheck` (one cost-free log line carrying no uid); then the `handle...` function.
2. `handle...`: anonymous gate (`permission-denied` / `anonymous_not_allowed`), FIRST, unchanged.
3. `verifyExpectedUid(uid, data)`.
4. Everything else as before: strict parse, feature or bucket check, quota charge, transactions, Storage.

Handlers: `handleSetActivityCloudSettings` (`set_settings.ts`), `handleCreateActivityStreamUpload` (`create_upload.ts`), `handleCommitActivityStream` (`commit_stream.ts`), `handleDeleteActivity` (`delete_activity.ts`).

### Exact error pair (J2 maps this)

- Mismatch: `HttpsError("failed-precondition", "account_changed")`, so `error.code == "failed-precondition"` and `error.message == "account_changed"` (Dart `FirebaseFunctionsException.code == "failed-precondition"`, `.message == "account_changed"`). Logged with outcome `account_changed` at level `warn`, no uid.
- Collision note: `failed-precondition` is also used by `account_deleting` (settings, delete, upload, commit) and by other refusals (`deleted`, `no_summary`, `consent_required`, `consent_withdrawn`, `already_expired`, `expired`, `upload_missing`). The MESSAGE string `account_changed` is unique and is the discriminator; a client must compare the message, not only the code.
- Missing, non-string, empty or over-long key: the handler's existing invalid-request error, `HttpsError("invalid-argument", "invalid_request")` in all four handlers (settings via `toHttpsError`, upload and commit via `toUploadHttpsError`, delete via `toHttpsError`).

### Existing jest tests that will now fail (no `expectedUid` in the request)

All four handlers now refuse a request without `expectedUid` with `invalid-argument` / `invalid_request`. Central fix points (fix these first, most of the list below follows):

1. `functions/src/__tests__/activity/support/seven.ts`: the `SEVEN` table; the `call` of the four entries (`createActivityStreamUpload`, `commitActivityStream`, `deleteActivity`, `setActivityCloudSettings`) is `handleX(w.deps, uid, p, d)`. Add `expectedUid: uid` to `d` there when `d` is a plain object that does not already carry the key (keep the ability to pass an explicit `expectedUid` and non-object data for the new negative tests). The three other entries (`getActivityStreamDownloadUrls`, `deleteAllActivityStreams`, `sendDebugTelemetry`) must NOT get the key (their strict parsers would refuse it; they are out of J1 scope).
2. `functions/src/__tests__/activity/support/flow.ts`: `create(w, data, uid, provider)` and `commit(w, data, uid, provider)` call `handleCreateActivityStreamUpload` / `handleCommitActivityStream` directly; add `expectedUid: uid` the same way. `stage` and `fullUpload` build on them, and `prime` in `seven.ts` builds on `fullUpload`.

Test files that reach the four handlers through those two helpers (affected until the helpers are fixed; test cases that pass explicit `uid` arguments, e.g. a call as `UID_B`, must send `expectedUid` equal to THAT uid):
- `functions/src/__tests__/activity/callable_hardening.test.ts`: calls through `by(name).call(...)`, `create`, `commit`. Cases that rely on a specific error and will otherwise pass for the wrong reason or fail: "F60 shared input validation" (all `BAD_IDS` cases would still see `invalid_request` but for the missing key, so they would no longer prove the id check; `bytes`/`contentSha256` cases likewise), "client-supplied path, prefix, uid, bucket and objectPath fields never reach a path" (line ~122, requests spread `...evil` including a `uid` key; the strict settings parser must still refuse `uid`; delete and commit cases), "settings: unknown keys are refused" (line ~134), the quota loops at lines ~172-196 (1000 deletes, `UID_B` call at line ~191, `account_deleting` at ~196), the log-sentinel cases at ~213-215, and ~264. Line ~63 (anonymous gate: `e.call(w, e.ok(p), UID, "anonymous")`) still passes because the anonymous gate is first. Line ~57 (`.run(callReq({}, null))` unauthenticated) still passes (auth gate first).
- `functions/src/__tests__/activity/delete_fence.test.ts` (helper `del`, line ~18, passes an explicit `uid`; plus `SEVEN` loops for F76 "every callable refuses behind the fence" and F79).
- `functions/src/__tests__/activity/settings_consent.test.ts` (helper `settings`, line ~19, explicit `uid` and provider; `deleteActivity` calls at ~184 and ~250).
- `functions/src/__tests__/activity/remediation_a_settings.test.ts` (helper `settings`, line ~19).
- `functions/src/__tests__/activity/sweeps_jobs.test.ts` (`deleteActivity` at ~457 and ~593, settings withdraw at ~571 and ~617, and the create/commit flows of F54).
- `functions/src/__tests__/activity/account_flow.test.ts` (`SEVEN.find(...).call` at ~273 for settings and ~334 for delete; also uses `.run`/`callReq` at five places: review each, any call that reaches a handler after the auth gate needs the key).
- `functions/src/__tests__/activity/export_downloads_telemetry.test.ts` (`deleteActivity` at ~169; the `.run` calls at two places: check whether they target the four).
- `functions/src/__tests__/activity/upload.test.ts` (imports `createActivityStreamUpload` and calls `.run(callReq(req(), null))` at ~37: unauthenticated, still passes; every other case uses `create`/`stage` from `flow.ts`).
- Via `flow.ts` only: `commit_state.test.ts`, `commit_overlap.test.ts`, `upload_fence.test.ts`, `remediation_a_expiry.test.ts`, `remediation_a_reconcile.test.ts`, `ops_signals.test.ts`, `sweeps_jobs.test.ts`.
- `functions/src/__tests__/scaling.test.ts` (lines ~105-108 and ~253): only reads deployed options of the four callables; not affected by the new key.
- `functions/src/__tests__/s02_remediation_a_policy.test.ts` (line ~248): source-text scan of `set_settings.ts` for the words `summarySync` etc.; the new comment text does not contain them, so it is unaffected.
- `callable_hardening.test.ts` "F41" (lines ~51-56) scans the source for `noteAppCheck(request, "<name>")` and the unauthenticated guard in the `onCall` wrappers; the wrappers are unchanged, so it is unaffected.

I could only read the tests; no test was run, so the list is derived from the call graph, not from a failing run. The test agent must confirm by running the activity suites.

### New behaviors that need tests

Unit tests of the helper (new file, e.g. `functions/src/__tests__/activity/expected_uid.test.ts`):
- match returns a copy without the key; the input object is not mutated; other keys (including an unknown key) are preserved.
- mismatch throws `account_changed`; case-different uid is a mismatch.
- missing key, `null`, number, object, empty string, 129 characters -> `invalid_request`; exactly 128 characters equal to uid -> accepted.
- non-object data (null, undefined, array, string, number) is returned unchanged and does not throw.
- a malformed key never yields `account_changed` (shape check precedes equality).

Handler tests, for EACH of the four handlers:
- mismatch: error is exactly `failed-precondition` / `account_changed`; NOTHING is written (no Firestore write including no quota usage document, no Storage call, no Auth lookup: assert `w.bucket.totalCalls` unchanged, the write log unchanged, `usageOf(UID, quotaAction)` is 0, and for settings no settings document, no fence read); the log line has outcome `account_changed` and contains no uid (captured logger).
- mismatch happens even when the rest of the request is invalid (proves it runs before the parse) and even when the quota would be exhausted (proves it runs before the charge).
- missing key and invalid key (non-string, empty, 129 characters) -> `invalid-argument` / `invalid_request`, no charge, no write, no storage call.
- matching key -> the existing success path (create returns an upload, commit stores, delete tombstones, settings change), and the strict parser still refuses an unknown extra key even with a valid `expectedUid` (settings: `{ streamRetentionDays: 90, uid: UID_B, expectedUid: UID }` -> `invalid_request`).
- non-object data (null, array) -> the handler's existing `invalid_request`, still no charge.
- settings only: anonymous caller with a MISMATCHING key gets `permission-denied` / `anonymous_not_allowed` (the anonymous gate stays first); the same for the other three.
- the `onCall` wrapper still refuses a missing `request.auth` with `unauthenticated` before the handler.

Out of J1 scope (documented, not changed): `getActivityStreamDownloadUrls`, `deleteAllActivityStreams` and the telemetry callable do not take `expectedUid` in this change.

## CLIENT section (J2)

Status: CLIENT half (J2) implemented, NOT RUN (no test, analyze or build was executed). Test agent: FIRST get `mobile/` compiling (the fakes and call sites listed below), THEN write the new tests.

### Changed signatures (old -> new)

All under `mobile/lib/features/activity/repository/` unless stated.
- `ActivityCloudSettingsClient({required call, store})` -> `ActivityCloudSettingsClient({required call, required String? Function() currentUid, store})` (`activity_cloud_settings_client.dart`). New getter `bool get authMatchesAccount` (`store.boundUid != null && currentUid() == store.boundUid`). `_requireUid(uid)` now also requires `currentUid() == uid` and a non-null uid.
- `grant()` / `withdraw({deleteExisting})`: start check (store unbound OR live auth uid != bound uid -> `ConsentAccountChangedException`, before any state change or set insertion); request map gains `'expectedUid': uid`; a synchronous `_requireUid(uid)` sits immediately before the `_call(...)` expression; the existing post-call `_requireUid` now includes the auth check. In `withdraw` the local flip and persist still come first; if the account changes after the flip the call is NOT sent and the initiating account stays locally withdrawn.
- `cloudFunctionsSettingsCall`: maps `FirebaseFunctionsException(code: 'failed-precondition', message: 'account_changed')` to `ConsentAccountChangedException` (other failures are rethrown unchanged). New public helper `bool isAccountChangedRefusal(FirebaseFunctionsException e)`.
- `ActivityConsentWithdrawal.deleteCloudStreamsNow`: refuses (throws `ConsentAccountChangedException`, no `_deleteRequested` key) when `accountUid == null` OR `!authMatchesAccount`.
- `ActivityStreamCallableClient.create({activityId, bytes, contentSha256})` -> adds `required String? expectedUid`; `commit({activityId, uploadId})` -> adds `required String? expectedUid` (`activity_stream_uploader.dart`).
- `CloudFunctionsActivityStreamClient.create/commit`: put `expectedUid` into the payload; a null `expectedUid` throws `ConsentAccountChangedException` BEFORE any network call; the server pair maps to `ConsentAccountChangedException` (`_rethrow`).
- `ActivityStreamUploader`: passes the pass `bound` uid as `expectedUid` (null for an unbound test configuration); `on ConsentAccountChangedException` returns `StreamUploadOutcome.cancelled` (no retry counter, nothing marked, no quarantine, no failure state, no `_failedThisStart` entry).
- `ActivityTombstonePusher` typedef (`activity_sync_repository.dart`): `Future<void> Function(String activityId)` -> `Future<void> Function(String activityId, String? expectedUid)`. The repository calls `push(id, p.authUid)` (the value `_mayCall(p)` just checked). `ConsentAccountChangedException` from the pusher ends the pass like `_mayCall == false` (returns the aborted run; no `_failedTombstones`, no `_lastTombstonePushError`, no confirmation, tombstone stays pending). There is exactly one call site (`_pushLocalTombstones`); `activity_sync_resolution.dart` does not call the pusher.
- `CloudFunctionsActivityTombstonePusher.push(String activityId)` -> `push(String activityId, String? expectedUid)` (`cloud_functions_activity_tombstone_pusher.dart`): sends `expectedUid`, throws `ConsentAccountChangedException` before the network call when null, maps the server pair.
- Wiring (`mobile/lib/core/wiring/activity_wiring.dart`): settings client gets `currentUid: () => FirebaseAuth.instance.currentUser?.uid`. The tombstone pusher tear-off `CloudFunctionsActivityTombstonePusher().push` and `CloudFunctionsActivityStreamClient()` need no wiring change.
- Firestore summary backend (`firestore_activity_summary_backend.dart`): NOT changed. It addresses documents by `users/{uid}/...` using the uid it resolves per operation, and `firestore.rules` enforces `request.auth.uid == uid` on those paths (33 `request.auth.uid` uses), so a mismatch is refused by the rules; no callable, no `expectedUid`.

### Existing test code that no longer compiles or changes behavior (mobile/test)

Constructors without `currentUid:` (must add `currentUid: () => <live uid source>`; most tests should wire it to the same source as the store bound uid so existing scenarios keep their meaning):
- `mobile/test/features/activity/e2e/s02_consent_switch_e2e_test.dart` (~126)
- `mobile/test/features/activity/repository/activity_consent_withdrawal_test.dart` (~28, ~93)
- `mobile/test/features/activity/repository/activity_consent_unbound_test.dart` (~98, ~131, ~150, ~199)
- `mobile/test/features/activity/repository/activity_consent_switch_wiring_test.dart` (~367)
- `mobile/test/features/activity/repository/activity_consent_account_binding_test.dart` (~193, ~241, ~302, ~359, ~410)
- `mobile/test/features/activity/repository/activity_stream_upload_test.dart` (~160)

Fakes of `ActivityStreamCallableClient` (add `expectedUid` to `create` and `commit`; record it):
- `mobile/test/support/stream_upload_world.dart` (`FakeStreamCloud`, ~59)
- `mobile/test/features/activity/repository/activity_consent_account_binding_test.dart` (`FakeStreamCloudStub`, ~584)

Tombstone pusher closures/fakes (typedef now takes two positional arguments, e.g. `(id, expectedUid) async {...}`):
- `mobile/test/support/two_device_world.dart` (`ActivityTombstonePusher? pusher`, ~265-271)
- `mobile/test/features/activity/e2e/s02_auth_flip_e2e_test.dart` (~103), `s02_pass_account_switch_e2e_test.dart` (~124)
- `mobile/test/features/activity/repository/activity_sync_deletion_flag_test.dart` (~58), `activity_sync_corrupt_summary_test.dart` (~337), `activity_sync_auth_tie_test.dart` (~131), `activity_tombstone_continuation_test.dart` (~169), `activity_sync_pass_identity_test.dart` (~277)

Callers of `cloudFunctionsSettingsCall`, `CloudFunctionsActivityStreamClient`, `CloudFunctionsActivityTombstonePusher` exist only in `mobile/lib/core/wiring/activity_wiring.dart` (no test constructs them today).

Existing assertions whose behavior changes:
- Any grant/withdraw/deleteCloudStreamsNow test where the store `boundUid` is set but the live auth source returns another uid (or null) now expects `ConsentAccountChangedException` and ZERO server calls where it previously succeeded. Tests that moved only `store.boundUid` to simulate an account switch must also move the live uid source if the call is expected to proceed; tests that expect a refusal on a store-uid switch still pass.
- Request-map assertions on the settings call (exact map equality) now include `'expectedUid'`.
- Tests that count `unpersistedWithdrawals`/state after a refused withdraw: the refusal now happens before the flip, so no state change at all.
- Tombstone tests that expect a thrown pusher error to count as a failure still hold for generic errors; only `ConsentAccountChangedException` is special.

### New behaviors that need tests

For EACH of grant, withdraw, deleteCloudStreamsNow, uploader create, uploader commit, tombstone push:
- (a) Deterministic A to B flip: the live-uid supplier returns A for the first N reads and B afterwards (N chosen so the flip lands between the start check and the pre-call check, and again between the pre-call check and the post-call check). Run with DIFFERENT and with IDENTICAL prior consent values for A and B. Assert ZERO server mutation for B (the fake server records calls; none carries B's uid), the call is not sent when the flip lands before the pre-call check, no consent state change for B, no `_deleteRequested` key, no uploaded marker, no quarantine, no failure counter, no confirmed tombstone.
- (b) The request carries `expectedUid` equal to the initiating account (settings map, create/commit payload via the fake, tombstone second argument = `pass.authUid`).
- (c) A server refusal `FirebaseFunctionsException(code: 'failed-precondition', message: 'account_changed')` is not a generic failure: settings -> `ConsentAccountChangedException` (no `_unpersistedWithdrawals` change for another uid; `deleteCloudStreamsNow` removes its key); uploader -> outcome `cancelled`, no retry, nothing marked; tombstone -> pass stops, tombstone pending, not in `_failedTombstones`. Also the negative: `failed-precondition` with message `account_deleting` is NOT mapped (stays a generic refusal).
- (d) The real clients refuse a null `expectedUid` before any network call: `CloudFunctionsActivityStreamClient.create/commit` and `CloudFunctionsActivityTombstonePusher.push` (inject a `FirebaseFunctions` fake or assert no callable is created) throw `ConsentAccountChangedException`.
- Start refusals: store unbound; store bound A while live auth is null; store bound A while live auth is B; `authMatchesAccount` truth table.
- Unbound uploader (no `currentUid`): passes `expectedUid == null` to the fake and still uploads.

### Accepted limits
- The account can still flip after the server accepted the request but before the client applies the result: the existing post-call re-check throws and nothing is written for B; the server wrote only the initiating account's own consent or data, so this is not a data leak. A and the client cache can then differ until the next `load()`.
- `withdraw` keeps the local-first order: if the account changes after the local flip, the initiating account stays locally withdrawn but the server is not told (privacy-conservative; the user can withdraw again as that account).
