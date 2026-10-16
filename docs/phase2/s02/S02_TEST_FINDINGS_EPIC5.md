# S02 test epic 5: findings (plan versus design versus rules)

Scope: Firestore and Storage rules, story S02-03 and the bucket rules of S02-04a. Ids: R01-R37 (R22 with them), S01-S03, I30, I34 (U06 is a Dart unit test of epic 1 and was not touched).

## Final run

Emulators on alternative ports because port 8080 is held by another process on this machine (the repo wrapper documents `FIREBASE_EMULATOR_CONFIG` and `FIRESTORE_EMULATOR_PORT` for that case; the alternative config lives outside the repository).

Command (from `functions/`, environment `FIREBASE_EMULATOR_CONFIG=<alt config> FIRESTORE_EMULATOR_PORT=18080 STORAGE_EMULATOR_PORT=19299`):
`node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/s02_ src/__rules__/data_access_policy.test.ts src/__rules__/firestore_rules.test.ts src/__rules__/storage_rules.test.ts`
Summary lines: `Test Suites: 8 passed, 8 total` and `Tests:       908 passed, 908 total` (five new S02 files, plus the three existing rules files I edited: `data_access_policy.test.ts`, `firestore_rules.test.ts`, `storage_rules.test.ts`).
Dart (from `mobile/`): `flutter test test/features/activity/repository/activity_rules_constants_test.dart` -> `00:11 +5: All tests passed!` (I30, I34).

## Production defect found and fixed (smallest change in firestore.rules)

A summary document carrying EVERY allowlisted key (32 keys) was refused by the emulator: "Unable to evaluate the expression as the maximum of 1000 expressions to evaluate has been reached" at the create rule. A real client write with many optional fields would have been rejected. Same class as the food_entries budget defect. Fix: the helpers `actNumOk`, `actIntOk`, `actStrOk` bind `d.get(k, default)` once with `let`; call sites and semantics are unchanged (the Dart parity parser reads the call sites). The first attempt (inlining `d[k]` without `let`) was not enough. After the fix the numeric bound tests (R08, both ends of every key, plus fractions and NaN/infinity) and the whole summary suite pass. Commit 5382a770.

## Contradictions and how they were resolved (design followed)

1. The plan's "Fails if" column describes what makes a test FAIL; rows such as R01, R11, R12, R28 read inverted if taken as expectations. R32, R33 and R34 follow the design: create requires `rev` 1; update requires `rev` STRICTLY greater than stored; equal and lower revs are refused (a resent identical body after a lost acknowledgement is refused, routine); stored + 1 and stored + 5 are accepted; a create-shaped write for an existing id is evaluated as an update (stored 3, sent 1 refused).
2. R15 and R27 in the plan text say owner read "denied" and other-user read "succeeds" in the fails-if sense; the tests assert owner read ALLOWED and other-user, signed-out and canary read DENIED, as the design table says.
3. R22 in the plan belongs to S02-09 but is run in this epic as requested. Two existing tests assumed client create of `debug_sessions` (`firestore_rules.test.ts`, `data_access_policy.test.ts`) and failed against the committed S02-09 rule: test defects, updated.
4. R30 asks for `activity_late_sweeps` to be absent from `data_lifecycle_policy.json`; the file is `scripts/ci/data_lifecycle_policy.json` and the test reads it there.
5. I30 and I34 are Dart ids. There is no class `FirestoreActivityRepository`; they run against `ActivitySyncRepository` in a new file `activity_rules_constants_test.dart`. The client sends single-summary backend calls today, so the 500-entry flush clause is proved as "every backend call carries one summary (never above 8)"; `syncBatch` of 9 is refused whole. The plan's PROPOSED flush splitting is not implemented because no multi-summary flush exists. The Firestore adapter's own `writeSummaries` guard is not exercised (no fake Firestore instance).
6. I30 text ("a local edit that changes `startUtc` or `sport` produces an update with a changed value") is a fails-if sentence: the test proves such an edit is rejected and the summary keeps both values and the id. The edit API accepts only numeric fields, so a string `sport` edit is excluded by type.

## R35 discovered limit

On the emulator a batch of 19 summaries (each with a tombstone and a fence `exists()` lookup) is accepted and a batch of 20 is rejected whole (`permission-denied`, nothing written). The fence path is the same for every write in the batch, so the emulator counts it once: 19 tombstone lookups + 1 fence lookup = 20 access calls. The design's 8 summaries (16 nominal, 9 after de-duplication) is within the emulator limit under both readings. Whether production de-duplicates the repeated fence lookup is NOT verified (section 4 of the plan, NOT_RUN). The design chose 8 and the test asserts only that the first rejected size is greater than 8.

## Other observations

- R21: the largest legal summary is about 982 bytes by the documented size formula, far below 4 KiB.
- R17/R31 falsification: removing any of the four write exclusions from a copy makes the probe write ALLOWED; removing a read exclusion is not behaviourally observable for owner-readable paths (shown by a test), so R18 and R31 are text checks and fail on each mutated copy.
- The Storage emulator's `clearStorage` does not remove objects between tests; S02 uses a path no other test seeds.
- Pairing rule: every denial is followed by an accepted control (same id, valid body, or the Admin-equivalent write).

## Not verified

- Real Firestore: production access-call counting, rule caching after the fence write, the 1000-expression budget in production (the emulator's evaluator is the only evidence).
- The Dart parity tests that parse `firestore.rules` were not re-run after the helper-body change (call sites unchanged).
- Port 8080 conflict: the repository default configuration was not used.
