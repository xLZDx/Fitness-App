# S02-08 change record: data lifecycle policy rows for the unified activity collections

Date: 2026-10-16. Story: S02-08 (design 6 "scripts/ci/data_lifecycle_policy.json" row, 11; GPS-PRIV-004 and GPS-PRIV-065; test ids F38, F39, R23, R24).

## What changed

- `scripts/ci/data_lifecycle_policy.json`, six new `collections` rows, each with both axes (retention classification and `clientAccess`):
  - `activities`: BOTH; read OWNER, create and update CONDITIONAL (refs to the rules tests R23 and R24), delete NONE.
  - `activity_streams`: BOTH; read OWNER, writes NONE (index rows exported, stream bytes delivered by download links).
  - `activity_settings`: BOTH; read OWNER, writes NONE.
  - `activity_tombstones`: DELETE (see deviation); read OWNER, writes NONE.
  - `activity_account_state`: EXEMPT, top-level server-only, client NONE (deletion bookkeeping, replaces the withdrawn `activity_late_sweeps`).
  - `activity_reconcile_state`: EXEMPT, top-level server-only, client NONE (cursor bookkeeping, no uid).
- New top-level informational section `storageObjects` for the two bucket prefixes `streams/{uid}/...` and `quarantine/{uid}/...` with delete and export statements. No checker reads it (both checkers read `collections` only); it exists because object prefixes have no Firestore collection to discover.
- `debug_sessions` was verified, not changed: the S02-09 commit already set every client cell to NONE and names `sendDebugTelemetry` as the only writer.

## Why

GPS-PRIV-004 and GPS-PRIV-065: every new collection and Storage path needs a policy row before the feature can ship, and the lifecycle and access checkers fail when a discovered collection has no row.

## Affected contracts and paths

Only the policy file. The `conditionalRefs` test names are the names the test agents must use in `functions/src/__rules__/data_access_policy.test.ts`: the create name is the one fixed by R23; the update name `CONDITIONAL cell activities/update: a higher rev with an allowlisted summary is accepted, a geometry key or a rev that does not increase is refused` is chosen here because R24 only says "same file, activities/update" (test agents: use this exact string or change the policy row in the same edit).

## Deviations

- `activity_tombstones` is classified DELETE, not BOTH as the design table and test F39 say: the S02-07 export story deliberately does not export tombstones (ids and timestamps of the user's own deletions, no content). The reason text records the decision and the way to reclassify. F39 expects BOTH for this row and needs the matching adjustment (or the operator decides to export the ids and the row becomes BOTH).
- `activity_account_state` and `activity_reconcile_state` have no `firestore.rules` block by design (default deny); the first is found by the code scan (`.collection("activity_account_state")` in `late_sweep.ts`), the second only through a `doc()` path, so the coverage checker may list it as "no current code reference" (informational, not a failure).

## Verification state

No tests, checkers or builds were run (operator rule v4, task instruction). The JSON was written by hand and not parsed by a tool. The checkers (`check_data_lifecycle_coverage.js`, `check_data_access_policy.js`) and the F38/F39 tests are for the test agents.
