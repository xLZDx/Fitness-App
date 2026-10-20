# S02 test findings, epic 8: remediation batch A

## Epic 8a (jest, `functions/src/__tests__/activity/`)

Items covered: A1, A2, A3, A4, A5, A7, A8 (validator bound), A10, A11, A13, A14, A15, A16. The scaling-profile pin, rules tests, TTL checker, privacy text and access-policy checker belong to epic 8b.

### Final run (head after the last 8a test commit)

Command (cwd `functions`, every test file of the activity directory, which includes all files written or changed in 8a):
`npx jest src/__tests__/activity`
Summary lines:
`Test Suites: 26 passed, 26 total`
`Tests:       744 passed, 744 total`
Before the 8a changes the same directory gave 4 failing tests in 2 suites (670 passed of 674).

### Files

| File | Items | Tests |
|---|---|---|
| `remediation_a_fence.test.ts` (new) | A1 (heartbeat, 24 h boundary, retries record, retry race, fail closed, fenceAt fallback), A5, A10 late sweep | 15 |
| `remediation_a_reconcile.test.ts` (new) | A2, A3, A4, A14, A15 | 21 |
| `remediation_a_expiry.test.ts` (new) | A7 (commit transaction 2, reconciler repair, download URLs, classifyRow) | 12 |
| `remediation_a_validate_bound.test.ts` (new) | A8 validator bound with JSON.parse spy | 6 |
| `remediation_a_settings.test.ts` (new) | A11, A13, A16 | 15 |
| `sweeps_jobs.test.ts` (updated) | skipped-live cases now respect the 24 h window and the retries record | |
| `delete_fence.test.ts` (updated) | fence write refreshes `touchedAt`; A10 unset-bucket delete with and without a stream row | |

### Tests that pinned old behaviour (updated)

- `sweeps_jobs.test.ts` (c2) and the REGRESSION skipped-live run: the third run at +3 days now clears the abandoned fence, so the runs stay inside 24 h and the "never removed" case uses an `accountDeletionRetries` record.
- `delete_fence.test.ts` unset-bucket delete: now `delete_failed` when a stream row exists.
- `ACTIVITY_USER_COLLECTIONS` was not pinned by any earlier test; the new test pins five entries.

### Defects and discrepancies

- No production defect found in the A1..A16 server code covered here.
- Notes versus code: the notes name the scan-cycle fields `streamsCycleStartedAt` / `quarantineCycleStartedAt`; the code stores `streamsCursorCycleStartedAt` / `quarantineCursorCycleStartedAt` (field is `<cursor field>CycleStartedAt`). The tests assert the code names; the notes are shorthand.
- Notes A8 example (2 MB gzip of `1,` to 32 MiB) cannot pass the production compression ratio cap (20): such filler would be rejected as `bomb` first. The tests lift `maxRatio` to reach the separator bound; the production ratio check is covered by `decompression_limits.test.ts`.

### Not covered by 8a

- A6, A9, A12 and the scaling-profile pin (epic 8b).
- A14's log assertion checks the word `unrecognised` in the warn entry, not the exact field set.
- Mutation runs were not performed (operator decision); each assertion was chosen from the notes so that the named behaviour breaking would fail it.

## Epic 8b: rules, TTL declaration, privacy draft, scaling, access-checker pins (agent 8b)

Items A5, A6, A8 (scaling pins), A9, A12, F38, F42. No production code changed.

### Final run (head at run time: 6dba0037 plus the two test-defect fixes committed after it)

1. Rules emulator (cwd `functions`, `FIREBASE_EMULATOR_CONFIG=<alt config outside the repository> FIRESTORE_EMULATOR_PORT=18080 STORAGE_EMULATOR_PORT=19299`):
   `node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/s02_`
   Summary lines: `Test Suites: 6 passed, 6 total` and `Tests:       289 passed, 289 total`.
2. Jest (cwd `functions`): `npx jest src/__tests__/s02_remediation_a_policy.test.ts src/__tests__/scaling.test.ts`
   Summary lines: `Test Suites: 2 passed, 2 total` and `Tests:       191 passed, 191 total`.
3. Policy checker self-tests (repository root): `node scripts/ci/test_check_data_access_policy.js` -> `All mutation-proof cases passed (RED on injection, GREEN on the real fix).` (exit 0); `node scripts/ci/test_check_ru_en_drift.js` -> `All self-tests passed.` (exit 0).

### Files

| File | Ids |
|---|---|
| `functions/src/__rules__/s02_activity_source_id_rules.test.ts` (45, emulator) | A12: accepted ids, coordinate-like / charset / length / newline / empty denials at create and update, each with an accepted control |
| `scripts/ci/check_ttl_overrides.js` (new checker) | A6 |
| `functions/src/__tests__/s02_remediation_a_policy.test.ts` (43) | A6 mutated-copy proof (9 mutations), corrected policy and runbook TTL text, A9/F42 privacy paragraph tied to the rules allowlist, A5 five collections, F38 five pre-S02 violations, line-exact allowlist proof on a tree copy |
| `functions/src/__tests__/scaling.test.ts` (edited) | A8: ACTIVITY_COMMIT 1GiB / 4 / 5, reconciler 1GiB single-flight, other activity callables stay 256 MiB |

### Test defects fixed (stale expectations from earlier epics, no product change)

- `scripts/ci/test_check_data_access_policy.js` case (o): expected `account_export.ts` residue at 107, 131, 143; S02 moved and added call sites, now 107, 131, 234, 237, 323.
- `functions/src/__rules__/s02_activity_access_rules.test.ts` R30: expected policy path `{uid}`; epic 6b changed it to `{docId}`.
- `scaling.test.ts`: `commitActivityStream` added to the explicit-concurrency list (it now has concurrency 4).

### Observations

- A12 rule: the coordinate denial `[0-9][.][0-9][0-9]+` also rejects legitimate ids such as `v1.50`; this matches the server validator (`COORDINATE_LIKE`), so it is consistent, but a client sending such a source id has its summary refused by the rules.
- The Dart mirror `mobile/test/support/firestore_rules_parser.dart` (line 130) still checks only type and length for `primarySourceId`; it is hand-written, not parsed from rule text, so the parity tests did not need a rerun, but the mirror is now looser than the rule.
- The privacy tests cover the English section only; the Russian section is not updated (wording pending operator approval), so there is no RU assertion. `lifecycle_policy.test.ts` (8a) was not edited; its F42 assertions still hold.
- Mutation runs were not performed (operator decision); the checker mutations are on temporary copies.

### Not covered by 8b

- Real Firestore TTL deployment (the checker proves the declaration only).
- Russian privacy text.
