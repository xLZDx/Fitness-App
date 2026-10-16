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

## J3 (class sweep follow-up)

Status: NOT RUN. No test, analysis or build was executed. This section supersedes the J1 statement that the download and delete-all callables are out of scope.

### SERVER (J3a)

Files: `functions/src/activity_streams/download_urls.ts`, `functions/src/activity_streams/delete_all_streams.ts`.

Signature change: `handleDeleteAllActivityStreams(deps, uid, signInProvider, data, limits = DEFAULT_DELETE_ALL_LIMITS)`. The new 4th parameter `data: unknown` is REQUIRED and sits BEFORE `limits` (a caller that passed `limits` as the 4th argument must now pass it 5th). `handleGetActivityStreamDownloadUrls(deps, uid, signInProvider, data)` keeps its signature.

Order of checks, `handleGetActivityStreamDownloadUrls`: (1) onCall wrapper: no `request.auth` -> `unauthenticated`/`sign_in_required`, then `noteAppCheck`; (2) anonymous gate (`permission-denied`/`anonymous_not_allowed`); (3) `verifyExpectedUid(uid, data)`: mismatch -> `HttpsError("failed-precondition", "account_changed")` with log outcome `account_changed` (warn, no uid); missing or malformed key -> `invalid-argument`/`invalid_request`; (4) the unchanged strict `parseDownloadRequest` on the stripped copy (an unknown extra key is still `invalid_request`; non-object data is returned unchanged by the helper and refused by the parser); (5) bucket check, quota charge, fenced transaction, signing as before.

Order of checks, `handleDeleteAllActivityStreams`: (1) onCall wrapper as above; (2) anonymous gate; (3) `verifyExpectedUid(uid, data)` with the same two failures; the helper's other failure mode (missing/malformed key) maps to `invalid-argument`/`invalid_request` (new `invalid_request` entry in the handler's refusal map); (4) the stripped body must be an empty plain object: any extra key, an array, null, a primitive or undefined -> `invalid-argument`/`invalid_request` (the smallest strict check; the handler never parsed a body before); (5) settings read, quota charge (only when starting a job), bulk page as before. Mismatch therefore causes no settings read, no quota usage document, no delete and no Storage call.

Existing jest support that MUST change:
- `functions/src/__tests__/activity/support/seven.ts`: entry `getActivityStreamDownloadUrls` (line ~69: `handleGetActivityStreamDownloadUrls(w.deps, uid, p, d)`) and entry `deleteAllActivityStreams` (line ~74: `handleDeleteAllActivityStreams(w.deps, uid, p)` currently ignores `d`; it must now pass a 4th argument, the body). In BOTH entries add `expectedUid: uid` when `d` is a plain object that does not carry the key; for `deleteAllActivityStreams` the body becomes `{ expectedUid: uid }` (also when the table passes an empty or undefined `d`). The J1 note that these two entries must NOT get the key is obsolete. Keep the ability to pass an explicit `expectedUid` and non-object data.
- Direct calls of `handleGetActivityStreamDownloadUrls` that pass `{ activityIds }` and now need `expectedUid`: `account_flow.test.ts:315` (uid `UID`), `export_downloads_telemetry.test.ts:29` (helper `dl`, explicit `uid` argument: send `expectedUid` equal to THAT uid).
- Direct calls of `handleDeleteAllActivityStreams(w.deps, UID, "password")` with no body (now `invalid_request`): `remediation_a_reconcile.test.ts:136, 145, 170`; `settings_consent.test.ts:200, 221`. Pass `{ expectedUid: UID }` as the 4th argument.
- `sweeps_jobs.test.ts:490` (`handleDeleteAllActivityStreams(w.deps, UID, "password", lim(o))`) and `:566` (`"anonymous", lim()`): `lim(...)` was the 4th argument and must move to the 5th; insert `{ expectedUid: UID }` as the 4th (for the anonymous case any body works, the gate is first).
- Tests that reach the two handlers only through `SEVEN` (fixed by the `seven.ts` change): `callable_hardening.test.ts` (`by(name)`, the quota loop ~144, the log-sentinel cases, line ~232 loop), `delete_fence.test.ts:174`, `remediation_a_expiry.test.ts:139`, `scaling.test.ts` (reads deployed options only; unaffected).
- Run `Grep` for `deleteAllActivityStreams|getActivityStreamDownloadUrls|handleDeleteAll|handleGetActivityStream` under `functions/src/__tests__` to catch any call this list missed; the list comes from reading, not from a run.

New tests required (a new file, e.g. `functions/src/__tests__/activity/expected_uid_more_callables.test.ts`), for EACH of the two handlers:
- mismatch: exactly `failed-precondition` / `account_changed`; no quota usage document (`usageOf(UID, quotaAction)` is 0), no read of the settings document or the fence (assert the read/write log is unchanged), no Storage call; log outcome `account_changed`, no uid in any log field.
- mismatch wins over an invalid request (download: `activityIds` malformed; delete-all: an extra key) and over an exhausted quota.
- missing key, non-string key, empty string, 129 characters -> `invalid-argument`/`invalid_request`, no charge, no read, no write.
- matching key -> the existing success path (download returns results; delete-all returns `done`/`more`).
- strict bodies: download `{ activityIds, expectedUid: UID, extra: 1 }` -> `invalid_request`; delete-all `{ expectedUid: UID, extra: 1 }`, `null`, `undefined`, `[]`, a string -> `invalid_request` with no charge.
- anonymous caller with a MISMATCHING key still gets `permission-denied`/`anonymous_not_allowed`.
- STRUCTURAL test: scan `functions/src/activity_streams/*.ts`, find every exported `onCall(` handler (`export const <name> = onCall(`), and fail when any handler other than `sendDebugTelemetry` does not call `verifyExpectedUid` (directly or via the `handle...` function it calls) before its first `await`. A practical form: for each such handler, resolve the `handle...` function it returns and assert the text of that function contains `verifyExpectedUid(` and that its index is smaller than the index of the first `await` in the function body; assert the exempt list is exactly `["sendDebugTelemetry"]`.

### CLIENT (J3b, Dart)

Status: NOT RUN (no flutter test, analyze or build). Files: `mobile/lib/features/activity/repository/activity_cloud_settings_client.dart`, `activity_sync_repository.dart`, `activity_stream_uploader.dart`, `mobile/lib/features/activity/state/sync_conflict_presenter.dart`.

Changed signatures: none (no new member, no changed parameter list, so no Fake needs updating).

Existing assertions that change:
- `cancelQueued` before a refused withdraw (B2): any test of `ActivityConsentWithdrawal.withdraw()` that expects the uploader to be cancelled although the account guard refuses (unbound store, or live uid differs). Look in `activity_consent_withdrawal_test.dart`, `activity_consent_unbound_test.dart`, `activity_consent_account_binding_test.dart`, `activity_consent_switch_wiring_test.dart`, `s02_consent_switch_e2e_test.dart`. A refused withdraw now leaves `_cancelled == false`. A successful withdraw re-arms the delete offer.
- Tombstone abort without retry on account-changed (B3): tests where the pusher throws `ConsentAccountChangedException` with the pass still alive and expect no retry timer: `activity_sync_pass_identity_test.dart`, `activity_sync_auth_tie_test.dart`, `s02_auth_flip_e2e_test.dart`, `s02_pass_account_switch_e2e_test.dart`, `activity_tombstone_continuation_test.dart`. Now a retry timer is scheduled (code `account-changed`); a pass that is no longer alive still ends aborted without a timer.
- `isGranted` with an unbound store (B1): tests that hold a stored `granted` with a null bound uid and expect `isGranted == true`, or call `load()` on an unbound store and expect the stored value: `activity_consent_unbound_test.dart`, `activity_consent_account_binding_test.dart`. Now false and state unknown.
- Presenter calling the repository with a null uid (B4): tests of `sync_conflict_presenter.dart` that tap `keepDevice`/`keepCloud`/`resolveCandidate` with `syncConflictUidProvider == null` and expect a repository call with `expectedUid: null`. Now no call.
- Uploader with an unbound or mismatched scoped journal (B5): tests that run the uploader with a scoped journal whose `boundUid` differs from the uploader's uid (or is null) and expect a journal read or an upload: `activity_stream_upload_test.dart`, `activity_consent_account_binding_test.dart`, `stream_upload_world.dart` users. Now `cancelled` and no read. A plain (non-scoped) journal fake is unaffected.
- Run Grep over `mobile/test` for `withdraw(`, `pusher`, `isGranted`, `syncConflictUidProvider`, `AccountScopedJournal` to catch what this list missed (derived from reading, not from a run).

New behaviors that need tests (one deterministic test each):
- B1: store unbound but `read()` returns `granted`: after `load()` the state is unknown, `consentUid == null`, `isGranted == false`; with a state granted for A and the store then unbound, `isGranted == false`.
- B2: refused withdraw (unbound, then live uid differs): throws `ConsentAccountChangedException`, `cancelQueued` not called, uploader `_cancelled == false`, no server call. Re-grant then withdraw then `deleteCloudStreamsNow` sends TWO `deleteExisting` requests across two withdrawals; a repeated `deleteCloudStreamsNow` within one withdrawal sends one.
- B3: a pusher throws `ConsentAccountChangedException` while the pass stays alive: a retry timer is scheduled (fake timer factory records it with the first backoff delay), the id is still owed (pending count 1, not confirmed), `lastTombstonePushError` unchanged, the id is NOT in `_failedTombstones` (observable: the next round's ordering does not demote it); a pass made stale by an account change returns aborted with no timer. Also confirm `'account-changed'` is not in `_kSystemicCodes` and the retry budget counter advances by exactly one.
- B4: `syncConflictUidProvider == null`: `keepDevice`, `keepCloud` and `resolveCandidate` do not call the repository and leave `busy` empty.
- B5: a scoped journal bound to B while the uploader runs for A: `runPending()` returns without reading the journal; `uploadEntry` returns `StreamUploadOutcome.cancelled` and `read` was not called; a plain journal still uploads.
