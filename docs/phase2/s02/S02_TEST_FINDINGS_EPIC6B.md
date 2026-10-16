# S02 test findings, epic 6b: retention, deletion sweeps, export, telemetry, lifecycle policy, story-map lint

Stories: S02-05b, S02-06b, S02-07 (functions part), S02-08, S02-09 (functions part), S02-11. Jest unit tests with fakes, `functions/src/__tests__/activity/`.

## Final run (revision 2, after the lead decision on the late-sweep risk)

Command (cwd `functions`; the seven epic-6b files plus the five epic-6a files that touch the fence, settings and late sweep):
`npx jest src/__tests__/activity/retention_purge.test.ts src/__tests__/activity/sweeps_jobs.test.ts src/__tests__/activity/account_flow.test.ts src/__tests__/activity/export_downloads_telemetry.test.ts src/__tests__/activity/lifecycle_policy.test.ts src/__tests__/activity/story_map_lint.test.ts src/__tests__/activity/ops_signals.test.ts src/__tests__/activity/delete_fence.test.ts src/__tests__/activity/settings_consent.test.ts src/__tests__/activity/upload_fence.test.ts src/__tests__/activity/callable_hardening.test.ts src/__tests__/activity/commit_overlap.test.ts`
Summary lines: `Test Suites: 12 passed, 12 total` and `Tests:       423 passed, 423 total`.
Revision 1 of this document reported 178 tests for six files; `ops_signals.test.ts` (14 tests) and eight new tests in `sweeps_jobs.test.ts` were added since. Regression of the shared fakes edited in this epic: `npx jest src/__tests__/activity src/__tests__/body_scan` gave 23 suites, 943 tests passed (before the later test files).

## Files and ids

| File | Ids |
|---|---|
| `retention_purge.test.ts` (27) | F14-F19, F63-F67, F88, F89, F71 row 9 |
| `sweeps_jobs.test.ts` (51) | F24, F25, F27, F28, F54 (all three interleavings), F55, F57, F58, F72 (incl. withdrawn consent), F80/F95 timing table, F81 (incl. the deleteExisting withdrawal start), regression of the live-account late sweep |
| `account_flow.test.ts` (17) | F26, F56, F77, F78 (A, B, C), F80, F95 order, E03, E05 functions part |
| `export_downloads_telemetry.test.ts` (53) | F29-F37, F69, F70, F73, F74, F90, F93 |
| `lifecycle_policy.test.ts` (24) | F38-F40, F42, F43, F92 |
| `story_map_lint.test.ts` (14) | F96 with eight mutated-copy proofs |
| `ops_signals.test.ts` (14) | F71 rows 1-10 (forced failure to signal) |
| `support/indexes.ts` | F88 index/query guard over the parsed `firestore.indexes.json` |

Shared fakes edited (all three changes are strictly more faithful to Firestore; body_scan and activity suites stay green): `body_scan/fakes.ts` maps `orderBy("__name__")` to the document id, excludes null and mismatched types from range filters, and exposes `fx.checkQuery`; `support/fakes.ts` FakeBucket gained `getFiles` listing and creation times.

## Production fixes (each the smallest change)

1. `scripts/ci/data_lifecycle_policy.json`: the `activity_account_state` clientAccess path was `{uid}` but the access checker discovers `{docId}` for a collection with no rules block, so the checker failed with "NO clientAccess DECLARATION"; path changed.
2. `scripts/ci/check_data_access_policy.js`: audited dynamic call-site list was stale (`account_export.ts` `owned()` moved 143 to 323) and lacked the S02 call sites (`account_export.ts` 234, 237; `delete_all_streams.ts` 183; `late_sweep.ts` 179; `recompute.ts` 173, 204); entries added with reasons.
3. `functions/src/activity_streams/late_sweep.ts` (lead decision): the destructive part of the late job never runs while the Auth user exists; the job logs the bare slug `skipped-live-account`, counts `skippedLive`, keeps the fence and stays armed; a failing Auth lookup fails closed (counted failure, nothing erased). One sentence added to design 6.1. The audited call-site line for `late_sweep.ts` in the access checker moved 179 to 184.
4. `runbooks/activity_stream_bucket.md`: the validator-code alert row named `hr_kind` and `bad_sha`; the code emits `forbidden_kind` and `sha_mismatch`; the row now lists the real codes (F71 row 6 asserts them).
5. `public/privacy.html`: added one paragraph on GPS upload, the expiry choice (90 days, 1 year, 2 years, never) and heart rate staying on the device (F42). Wording is subject to the DQ-10 review.

## Plan versus design contradictions (design followed)

- F18: plan says lengthening resurrects an expired row; design 5.3 says it does not. The test asserts the row stays `expired` and is only stamped with the new generation.
- F95 cell (a): plan says `authDeletedAt = T - 5 min` removes the fence at `T + 1 h`; the design formula `max(lateSweepDone + 1 h, authDeletedAt + 70 min)` gives `T + 65 min`. Tests assert `T + 65 min` and add a cell where the 1 h bound wins (`authDeletedAt = T - 20 min`).
- F27: plan says a stored row without a summary is kept; code and design 6 remove it with its objects. The test asserts removal.
- F39: plan says `activity_tombstones` is BOTH; the policy row (decision recorded in its reason) is DELETE with no export. The test pins DELETE and owner-read, writes NONE.
- F73: a valid batch cannot reach 16 KiB (at most 100 closed-schema events); the size gate is proven on the sanitiser with a padded payload (16384 passes the gate, 16385 is `batch_too_large`).
- F78 Part B: with Step 2 failing, `deleteAccount` aborts with a retryable HttpsError (Auth not deleted); the single aggregated bare code is observable at Step 4 (record `lastErrorCode`) and in the reconciler. Tests cover both.
- F26 / F78 C wording "retry count stays below 12 when one prefix keeps failing": a permanently failing prefix does reach the terminal state; the test asserts what holds: the other prefix is cleaned on the first attempt and a recovered failure completes with attempts 1 then removal.
- F72 "pending row of a user with withdrawn consent is not aborted": design 9.1 says pending rows are aborted by the reconciler after withdrawal, and the code does. The plan row is a plan error; two tests assert the abort (plain pending and an interrupted good upload).

## Late sweep after an aborted deletion: FIXED

Before: an aborted `deleteAccount` left the fence, and at `lateSweepAt` the job erased a LIVE account's GPS objects and activity documents and the fence never went away. Now `processJob` checks Auth first: a live user is skipped (nothing erased, nothing marked done, fence kept, `skippedLive` counted, slug `skipped-live-account` logged); the deletion intent keeps driving the account deletion; as soon as Auth is gone the same job proceeds. Regression tests in `sweeps_jobs.test.ts` ("REGRESSION: the late sweep never touches a LIVE account"): the live user survives three runs, the job proceeds after Auth deletion, an unreadable Auth state fails closed. Remaining design question (not changed): a fence left by an aborted deletion keeps the activity callables refused until the deletion completes; `deleteAccount` does not remove its own fence on an abort before Step 3.

## Other findings

- `check_data_access_policy.js` still fails on five violations that predate S02 (`body_scan/manage.ts` 218, 317, 355; `nutrition_cache.ts` 74, 109). The test pins exactly these five so any new violation fails.
- `functions/src/__rules__/data_access_policy.test.ts` needs the Firestore emulator and was not run here.
- Jest still reports no failing suite; an open-handle warning seen in epic 6a was not reproduced in the final run.

## Not covered by epic 6b

- Offline-replay half of E05 (summary writes with a valid token against the real rules, R36/R37): rules emulator, epic 5.
- F81: the worst-case concurrency of two parallel calls on one job.
- F54 third interleaving: the plan says the late sweep removes the object; by design there is no per-activity late job (F20), so the test asserts the real mechanism (the tombstone blocks commits, the retry of `deleteActivity` finishes).
- F96 maps GPS-PRIV ids only; named MAJOR/BLOCKER tokens of design sections 6.1, 6.2, 10 are not machine-mapped to stories.
- Dart-side ids of these stories (I13, U17-U20, U25, U26, U34, U35, I14, R22, I11, I12, E01) belong to other epics.
