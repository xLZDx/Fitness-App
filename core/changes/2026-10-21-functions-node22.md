# Cloud Functions runtime: Node.js 20 to Node.js 22

Date: 2026-10-21. Branch: chore/functions-node22-2026-10-21 (based on origin/master dc124bbc).

## Why

Google decommissions the Node.js 20 runtime for Cloud Functions on 2026-10-30. Node.js 22 is supported (deprecation 2027-04-30, decommission 2027-10-31 per the official runtime table). Deployed functions still report `nodejs20` (core/PRODUCTION_MANIFEST.md).

## What changed

Both Cloud Functions packages (`functions` = default codebase, `functions-equipment-identity` = equipment-identity codebase) move to Node 22:

- `firebase.json`: `"runtime": "nodejs20"` -> `"nodejs22"` in both `functions` sections.
- `functions/package.json` and `functions-equipment-identity/package.json`: `engines.node` `"20"` -> `"22"`.
- `functions/package-lock.json` and `functions-equipment-identity/package-lock.json`: root package `engines.node` mirrored to `"22"` (one line each; no dependency versions touched).
- `.github/workflows/functions.yml`: all five `node-version` entries `"20"` -> `"22"` (all jobs run the functions package).
- `.github/workflows/equipment-identity-functions.yml`: three `node-version` entries `'20'` -> `'22'`.
- `.github/workflows/flutter.yml`: only the `functions-build` job (cloud functions tsc, working-directory functions) `'20'` -> `'22'`. Other jobs in that file were not touched.
- Docs: `core/TECHSTACK.md` (runtime line) and `core/PHASE_4B_STRIPE_SETUP.md` (runtime requirement sentence).

## Deliberately NOT changed

- Historical records that describe past facts: core/PRODUCTION_MANIFEST.*, core/changes/2026-10-19-*, DECISION_LOG/LESSONS_LOG history, evidence JSON, design/consensus documents, reports/*.html, p0 feasibility notes (they describe the then-current runtime).
- The comment "Node 20+ refuses to spawn..." in `functions/scripts/run_emulator_tests.js` (still true on 22). The nodejs20 comments in `scripts/equipment_identity/test_deployment_isolation.py` and `scripts/equipment_identity/ts_dependency_probe.cjs` were updated to nodejs22 (the first in the test commit, the second after review).

## Review round 1 (reliability-reviewer, 0 BLOCKER, 0 MAJOR, 3 MINOR)
- The runtime-pin test `scripts/ci/test_functions_runtime_pin.py` is not wired into any CI job; it is a manual check. Accepted (CI is outside this task); run it with `C:\Python314\python.exe -m pytest scripts/ci/test_functions_runtime_pin.py`.
- Some CI jobs run `node` scripts on the runner default Node; they do not load the functions dependency tree and were not pinned to 20 before. Accepted, no change.
- Stale comment in `ts_dependency_probe.cjs` fixed in this commit; this record corrected.

## Operator actions (not done by this change)
- Deploy BOTH codebases (`functions` and `functions-equipment-identity`) before 2026-10-30; a codebase left on nodejs20 will be decommissioned.
- A redeploy rebuilds every function on Node 22 with no canary; watch error rates afterwards. Rollback is revert plus redeploy and is only possible before 2026-10-30.
- The Linux emulator/e2e container used for rules and e2e runs needs a Node 22 image.
- No .nvmrc, .node-version or Dockerfile exists in the repo that pins Node for functions (checked by search, excluding node_modules).

## Dependency compatibility (static, from package-lock.json only)

functions/node_modules was not present, so metadata was read from the lock files. Direct dependencies: firebase-admin 13.10.0 (engines >=18), firebase-functions 6.6.0 (>=14.10.0), stripe 17.7.0 (>=12), @google/genai 2.19.0 (>=20), @google-cloud/secret-manager 5.6.0, google-auth-library 9.15.1, firebase 11.x, jest 29.7, ts-jest 29.4.12, typescript 5.9.3. firebase-tools 15.17.0 (dev) declares `>=20 || >=22 || >=24`. No locked package declares an upper bound that excludes Node 22; some transitive dev packages (re2, @google-cloud/cloud-sql-connector via firebase-tools) require >=22, which Node 22 satisfies. No dependency change was needed.

## Not verified

- Runtime behaviour on Node 22 (native/gRPC modules, jest, tsc) was not exercised: no tests, build, analyzer or npm install were run in this change.
- Engine ranges say "allowed", not "works"; actual compatibility is for the test agents.
- A real deploy and the Firebase emulator were NOT run. They are the operator's action: deploy (functions become `nodejs22`), and run the emulator rules/e2e suites on Node 22 (known earlier: Windows host emulator e2e is blocked on Node 24 gRPC; use the Linux container).
- GitHub Actions results were not read.

## Rollback

Revert the commit; redeploy if functions were already deployed on nodejs22 (note Node 20 is decommissioned on 2026-10-30, so rollback is only useful before that date).
