# S02 test epic 5: activity rules emulator tests (summary shape, access, revision/fence/batch, permanent floor) and a rules expression-budget fix

## What
- `functions/src/__rules__/s02_rules_support.ts`: literal design 3.2 oracles (allowlist, numeric bounds), summary builders, golden-fixture loader (ISO strings to timestamps), rules-text helpers (remove one wildcard exclusion from a COPY of the rules text, open a delete or a server block in a copy, comment-stripping block parser, the permanent-floor lint).
- `s02_activity_summary_rules.test.ts`: R01, R04-R14, R19, R20, R21, R28, R29.
- `s02_activity_access_rules.test.ts`: R02, R03, R15, R16, R27, R30 (behaviour and rules-text/policy assertions).
- `s02_activity_revision_fence_rules.test.ts`: R26, R32-R37 (R32/R34 follow the design, see findings).
- `s02_activity_floor_rules.test.ts`: R17 (mutated copies loaded into separate emulator projects), R18, R31.
- `firestore.rules`: `actNumOk`, `actIntOk`, `actStrOk` now bind `d.get(k, default)` once with `let` instead of `!(k in d) || numberIn(d[k], ...)`. Call sites and semantics are unchanged (absent key passes, present key is type and range checked).

## Why
Test plan epic 5. The R01 full-document test (all 32 allowlisted keys) was REFUSED by the emulator: "maximum of 1000 expressions to evaluate has been reached" at the create rule. A client could not write a summary that carries every allowlisted key (same class as the food_entries expression-budget defect). The cheaper helper bodies fit the budget; the Dart parity parser (`firestore_rules_parser.dart`) reads the call sites, which did not change.

## Affected paths
The five files above under `functions/src/__rules__/`, and `firestore.rules` (three helper bodies, lines of the S02 block).

## Verification state
Emulator started by the repo wrapper on alternative ports because port 8080 is held by another process on this machine (`FIREBASE_EMULATOR_CONFIG`, `FIRESTORE_EMULATOR_PORT`, as the wrapper documents).
Command (from `functions/`): `npx jest --config jest.rules.config.js src/__rules__/s02_` against the running Firestore emulator.
Result: 4 suites passed, 224 tests passed. R35 discovered limit: 19 summaries accepted, 20 rejected.
Not re-run here: the Dart parity tests that parse `firestore.rules` (call sites unchanged).
