# S02 test findings, epic 6b: retention, deletion sweeps, export, telemetry, lifecycle policy, story-map lint

Stories: S02-05b, S02-06b, S02-07 (functions part), S02-08, S02-09 (functions part), S02-11. Jest unit tests with fakes, `functions/src/__tests__/activity/`.

## Final run

Command (cwd `functions`):
`npx jest src/__tests__/activity/retention_purge.test.ts src/__tests__/activity/sweeps_jobs.test.ts src/__tests__/activity/account_flow.test.ts src/__tests__/activity/export_downloads_telemetry.test.ts src/__tests__/activity/lifecycle_policy.test.ts src/__tests__/activity/story_map_lint.test.ts`
Summary lines: `Test Suites: 6 passed, 6 total` and `Tests:       178 passed, 178 total`.
Regression of the shared fakes edited in this epic: `npx jest src/__tests__/activity src/__tests__/body_scan` gave 23 suites, 943 tests passed (run after the fake edit, before the later test files).

## Files and ids

| File | Ids |
|---|---|
| `retention_purge.test.ts` (27) | F14-F19, F63-F67, F88, F89, F71 row 9 |
| `sweeps_jobs.test.ts` (43) | F24, F25, F27, F28, F54, F55, F57, F58, F72, F80/F95 timing table, F81, open-risk test |
| `account_flow.test.ts` (17) | F26, F56, F77, F78 (A, B, C), F80, F95 order, E03, E05 functions part |
| `export_downloads_telemetry.test.ts` (53) | F29-F37, F69, F70, F73, F74, F90, F93 |
| `lifecycle_policy.test.ts` (24) | F38-F40, F42, F43, F92 |
| `story_map_lint.test.ts` (14) | F96 with eight mutated-copy proofs |
| `support/indexes.ts` | F88 index/query guard over the parsed `firestore.indexes.json` |

Shared fakes edited (all three changes are strictly more faithful to Firestore; body_scan and activity suites stay green): `body_scan/fakes.ts` maps `orderBy("__name__")` to the document id, excludes null and mismatched types from range filters, and exposes `fx.checkQuery`; `support/fakes.ts` FakeBucket gained `getFiles` listing and creation times.

## Production fixes (each the smallest change)

1. `scripts/ci/data_lifecycle_policy.json`: the `activity_account_state` clientAccess path was `{uid}` but the access checker discovers `{docId}` for a collection with no rules block, so the checker failed with "NO clientAccess DECLARATION"; path changed.
2. `scripts/ci/check_data_access_policy.js`: audited dynamic call-site list was stale (`account_export.ts` `owned()` moved 143 to 323) and lacked the S02 call sites (`account_export.ts` 234, 237; `delete_all_streams.ts` 183; `late_sweep.ts` 179; `recompute.ts` 173, 204); entries added with reasons.
3. `public/privacy.html`: added one paragraph on GPS upload, the expiry choice (90 days, 1 year, 2 years, never) and heart rate staying on the device (F42). Wording is subject to the DQ-10 review.

## Plan versus design contradictions (design followed)

- F18: plan says lengthening resurrects an expired row; design 5.3 says it does not. The test asserts the row stays `expired` and is only stamped with the new generation.
- F95 cell (a): plan says `authDeletedAt = T - 5 min` removes the fence at `T + 1 h`; the design formula `max(lateSweepDone + 1 h, authDeletedAt + 70 min)` gives `T + 65 min`. Tests assert `T + 65 min` and add a cell where the 1 h bound wins (`authDeletedAt = T - 20 min`).
- F27: plan says a stored row without a summary is kept; code and design 6 remove it with its objects. The test asserts removal.
- F39: plan says `activity_tombstones` is BOTH; the policy row (decision recorded in its reason) is DELETE with no export. The test pins DELETE and owner-read, writes NONE.
- F73: a valid batch cannot reach 16 KiB (at most 100 closed-schema events); the size gate is proven on the sanitiser with a padded payload (16384 passes the gate, 16385 is `batch_too_large`).
- F78 Part B: with Step 2 failing, `deleteAccount` aborts with a retryable HttpsError (Auth not deleted); the single aggregated bare code is observable at Step 4 (record `lastErrorCode`) and in the reconciler. Tests cover both.
- F26 / F78 C wording "retry count stays below 12 when one prefix keeps failing": a permanently failing prefix does reach the terminal state; the test asserts what holds: the other prefix is cleaned on the first attempt and a recovered failure completes with attempts 1 then removal.
- F72 "pending row of a user with withdrawn consent is not aborted": the code aborts it (consent is re-checked by `selectPromotedObject`). Not asserted; listed below.

## OPEN RISK (documented by a test, production unchanged)

The late sweep erases user activity data after an ABORTED account deletion. `deleteAccount` writes the fence (Step 1c) before the first sweep. If the call then aborts (Stripe, Step 2 sweep or the intent record fails) the user still exists and can keep using the app, but `activity_account_state/{uid}` stays. At `lateSweepAt` (15 minutes later) the job sweeps both bucket prefixes and does the final recursive delete of `activities`, `activity_streams`, `activity_settings`, `activity_tombstones` of the LIVE account, marks `lateSweepDone`, and because Auth still exists never removes the fence (`authPresent` counted, F95 (c)); every activity callable keeps answering `account_deleting` for ever. Test: `sweeps_jobs.test.ts` "OPEN RISK (documents current behaviour)". Suggested fix (not applied, needs a decision): the late job must not erase while the Auth user exists (skip and report), and `deleteAccount` must remove its own fence when it aborts before Step 3.

## Other findings

- `check_data_access_policy.js` still fails on five violations that predate S02 (`body_scan/manage.ts` 218, 317, 355; `nutrition_cache.ts` 74, 109). The test pins exactly these five so any new violation fails.
- `functions/src/__rules__/data_access_policy.test.ts` needs the Firestore emulator and was not run here.
- Jest still reports no failing suite; an open-handle warning seen in epic 6a was not reproduced in the final run.

## Not covered by epic 6b

- Offline-replay half of E05 (summary writes with a valid token against the real rules, R36/R37): rules emulator, epic 5.
- F81: consent withdrawal choosing the offer starting the job (set_settings side) and the worst-case concurrency of two parallel calls on one job.
- F54 third interleaving (tombstone written, object delete failing): no per-activity late job exists by design (F20), so there is nothing to observe.
- F71 rows 1-8, 10 as a single `it.each` table: rows 4, 5, 9 and 10 are covered through purge, recompute, missing-index and stuck-job tests; rows 1-3, 6-8 only through the reconciler/commit/telemetry tests above, not as a table.
- F72 withdrawn-consent case; F93 callable-level check that the metric exists in a production-mode build (the callable has no debug mode, so it always emits).
- F96 maps GPS-PRIV ids only; named MAJOR/BLOCKER tokens of design sections 6.1, 6.2, 10 are not machine-mapped to stories.
- Dart-side ids of these stories (I13, U17-U20, U25, U26, U34, U35, I14, R22, I11, I12, E01) belong to other epics.
