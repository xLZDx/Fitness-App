# S00: guard tests rerun on the merged tree

Date: 2026-10-15. Branch: `phase2/s00-split-docs`, tests for the merge commit `7f9e0216` (record `core/changes/2026-10-15-s00-merge-phase2-main-into-s00.md`).

## What changed
- `functions/src/__tests__/release_guard.test.ts`: 8 new interaction tests: the real `firebase.json` (now with the `storage` block added by PR #5) reports no unguarded target and reports exactly `storage` when its guard is stripped; Phase 1 provenance failure (false or rejecting reader) blocks through the Deploy target check while the bucket check and the six-callable inventory stay OK; a Phase 2 branch with the production project blocks with `phase2-project-mismatch` while those checks pass; a missing bucket-canary entry blocks only the bucket check; the six `AI_SOURCE_PATHS` entries match `AI_CALLABLES` and exist on disk.
- `functions/src/__tests__/guard_scripts.test.ts`: the child environment strips an ambient `BODY_SCAN_BUCKET` so the script tests do not depend on the machine environment.
- No product code changed; no existing assertion was weakened (the expected check counts 10 and 11 still hold: the bucket check is the only extra check and appears only when `BODY_SCAN_BUCKET` is set).

## Why
The merge brought the PR #5 guard checks and a new `storage` deploy target; the combined guard needed fresh evidence.

## Affected contracts and paths
Test files only.

## Verification state
Run by the test-writing agent (`tdd-guide`, Sonnet 5.5) on `7f9e0216`: `release_guard.test.ts` 268 passed, `guard_scripts.test.ts` 43 passed, `scaling.test.ts` 125 passed (the only other jest file importing `release_guard`); combined 436 passed, 0 failed. Python files `scripts/equipment_identity/test_deployment_isolation.py` and `verify_deployment_isolation.py` mention the guard and were not run. Not verified: the real body-scan bucket check against a live bucket, a real `firebase deploy --dry-run` hook run, `functions/node_modules` versions after the merge. No mutation runs were made (operator rule).
