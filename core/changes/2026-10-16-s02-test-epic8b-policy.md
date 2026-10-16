# S02 test epic 8b: policy, privacy text, scaling and access-checker tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/__tests__/s02_remediation_a_policy.test.ts` (new, 43 tests): A6 mutated-copy proof for `check_ttl_overrides.js` and the corrected `activity_tombstones` policy and runbook text; A9/F42 privacy paragraph and exception sentence tied to the rules allowlist and the settings callable; A5 five-entry `ACTIVITY_USER_COLLECTIONS`; F38 exactly five pre-S02 access-checker violations; line-exact allowlist proof by moving `late_sweep.ts` in a tree copy.
- `functions/src/__tests__/scaling.test.ts`: `ACTIVITY_COMMIT` pins (1GiB, concurrency 4, maxInstances 5), reconciler 1GiB single-flight, other activity callables stay at 256 MiB; `commitActivityStream` added to the explicit-concurrency list (the old test pinned platform default).

## Why
Remediation A5, A6, A8, A9, F38, F42 need behaviour-level evidence. The Russian privacy section is not covered (wording pending operator approval).

## Affected contracts and paths
Test files only; no product code changed. `lifecycle_policy.test.ts` (owned by agent 8a) was not edited; its F42 assertions still hold on the new text.

## Verification state
jest run of the two files: 191 passed (see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`).
