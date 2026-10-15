# E0 tests, rules part (T03, T04, T05) and two firestore.rules fixes

## What
- `functions/src/__rules__/firestore_rules.test.ts` (T03, extended): about 210 new emulator cases for RULES-01..11, 13, 17..20, PRIV-16, ONB-16, SAFE-19: body_scans read/write surface (each server-owned key separately, mixed writes, key removal), weight_entries, nutrition_plan (boundaries, enums, planVersion + 1), nutrition_plan_reviews (immutable, week ids, reasonCodes at every index), food_entries (1/30/31 items, per-index element checks, totals), saved_foods, body_scan_settings including every `cloudConsent` case (new, unchanged, bumped, decreased, forged timestamp, removed), profile `nutrition` map and the new health-flag keys (device-only answers refused, legacy five-key shape and explicit nulls accepted), the wildcard carve-out proof for all seven collections (generic-shape write refused, nested sub-paths denied, over-broad carve-out guard), canary refusal and cross-user refusal for all seven, and the server-only `nutrition_cache` / `body_scan_purge_state`.
- `functions/src/__rules__/storage_rules.test.ts` (T04, new): deny-all for owner, other user, canary and anonymous on read, write, delete and list, with a rules-disabled positive control, plus a source check that `storage.rules` has exactly one `allow read, write: if false`.
- `functions/src/__rules__/data_access_policy.test.ts` (T05): the four lifecycle-row expectations (PRIV-21, RULES-14) are recorded as `test.todo` DEFERRED to C25, because `scripts/ci/data_lifecycle_policy.json` has no rows for the new paths yet. Not faked.

## Defects found and fixed in firestore.rules (C01 code, E0)
1. `food_entries` was UNWRITABLE: even a one-item entry exceeded the 1000-expression budget ("maximum of 1000 expressions to evaluate has been reached"). Fix: per-element check inlined for all 30 slots (`l.size() <= k || l[k].name.size() <= 80`) and `rangeOk` reduced to one comparison chain (`low >= 0 && low <= mid && mid <= high && high <= 100000`, which also makes the range ordered). Measured on the emulator: a 30-item entry with every optional field is accepted.
2. `cloudConsent` withdrawal (key removed) was refused with "Property cloudConsent is undefined" although D-56 and the rule comment say it is allowed. Fix: `!('cloudConsent' in n)` is now the first disjunct of `consentOk`.

## Paths
firestore.rules, functions/src/__rules__/{firestore_rules,storage_rules,data_access_policy}.test.ts

## Verification
Emulator runs used an alternate emulator config because port 8080 on this machine is held by another process: `FIREBASE_EMULATOR_CONFIG=<scratch>/fbcfg/firebase.json FIRESTORE_EMULATOR_PORT=8181 STORAGE_EMULATOR_PORT=9299 node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules src/__rules__/firestore_rules.test.ts src/__rules__/data_access_policy.test.ts` (2 suites passed, 491 passed, 4 todo) and the same with `firestore,storage ... src/__rules__/storage_rules.test.ts` (82 passed).
