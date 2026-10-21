# Functions Node 22 migration: test results

Date: 2026-10-21. Branch chore/functions-node22-2026-10-21, base commit 65e57db2 (tests added on top).
Interpreter: C:\Python314\python.exe (pytest 8.4.2). No npm install, build, analyzer, emulator, deploy or firebase command was run.

## Search for tests pinning the runtime

Searched the worktree (excluding node_modules and .git) for nodejs<N>, engines, runtime and firebase.json readers. Result:
- No existing jest or python test asserts the runtime, firebase.json runtime or engines.node.
- scripts/equipment_identity/test_deployment_isolation.py only mentioned `nodejs20` in the docstring of test_3a_folds_plain_path_under_both_algebras ("`functions` deploys to nodejs20 on Linux"). Updated to nodejs22 (comment only, no assertion change).
- Other hits (rights.py, contracts.ts, test_rights.py: "engines" = regex engines) are unrelated.

## Files changed

- NEW scripts/ci/test_functions_runtime_pin.py (pytest; 11 tests).
- scripts/equipment_identity/test_deployment_isolation.py (one docstring word).

## New regression test contract

Fails if: any codebase in firebase.json functions has runtime other than nodejs22; either functions package.json engines.node is not exactly "22"; the two package.json files disagree; a lock-file root engines.node differs from "22". Negative cases (stale, missing, other version, range, disagree) run against the checker functions to prove the guard can fail.

## Commands and results

1. `C:\Python314\python.exe -m pytest scripts/ci/test_functions_runtime_pin.py -q` -> 11 passed, 2 warnings (third-party deprecation).
2. `C:\Python314\python.exe -m pytest scripts/equipment_identity/test_deployment_isolation.py -q -p no:cacheprovider` -> 91 failed, 16 passed.
   Cause: environmental, not the Node 22 change. verify_deployment_isolation.IsolationVerificationError: `functions\node_modules\typescript is missing` (node_modules not installed; npm install forbidden for this task). Baseline check with my edit stashed gave the identical 91 failed (the unmodified file at 65e57db2). So this file cannot be shown green in this worktree; it needs `npm ci` in functions/ (operator or later agent).

## Not verified

- test_deployment_isolation.py is not green here (missing node_modules); the edit is comment-only.
- Runtime behaviour on Node 22, jest, tsc, emulator, deploy, CI: not run.
- The new test checks configuration only, not that code works on Node 22. It is not wired into CI (run manually with the command above).
