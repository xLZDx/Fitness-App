# S00: tests for the node_modules scope fix

Date: 2026-10-16. Branch: `phase2/s00-split-docs`. Tests for commit `8391de16` (record `core/changes/2026-10-16-s00-guard-node-modules-scope.md`).

## What changed
- `functions/src/__tests__/release_guard.test.ts` and `guard_scripts.test.ts`: one unit test whose assertion contradicted the new rule (unreadable `firebase.json` no longer allows `functions/node_modules/`) was corrected; two end-to-end tests for an unreadable `firebase.json` now expect `functions/node_modules/` among the offenders; no assertion was weakened otherwise.
- New unit tests: hosting `ignore []` blocks `public/node_modules`; `**/node_modules/**` allows it (also nested); `['node_modules']` allows only the top-level one for hosting (whole-path matching); functions without an `ignore` key use Firebase's default `['node_modules', '.git']`; `ignore []` blocks both; basename matching for functions only (nested `node_modules`, slash-free patterns) and not for patterns with a slash; `node_modules_backup` blocks; unreadable, invalid, null or string `firebase.json` blocks every `node_modules` and `.git`; `lib` dirs and env files stay allowed with empty ignore lists; implicit `firebase-debug*.log` exclusion for functions; hosting implicit exclusions are not modelled (stricter than firebase-tools, pinned as a known false-positive source).
- New end-to-end tests with real git, a real committed `.gitignore`, the real guard and the real wrapper: hosting `ignore []` with an ignored `public/node_modules/pkg/index.js` exits 1 with `ignored-deployable-files:` and firebase is never spawned; the control with `**/node_modules/**` deploys; functions default and empty ignore lists; second codebase reports only its own `node_modules`; nested `node_modules` passes when listed; invalid `firebase.json` blocks.
- No product code changed.

## Why
GPT-PM round 3 on `3b93b15e` returned MODIFY with MAJOR-02B: an ignored `node_modules` was allowed unconditionally, even where the target's own ignore list does not exclude it.

## Affected contracts and paths
Test files only.

## Verification state
Run by `tdd-guide` (Sonnet 5.5) on `8391de16`: `release_guard.test.ts` 505 passed, `guard_scripts.test.ts` 112 passed (798 s in this run, plan 10 to 15 minutes), `scaling.test.ts` 125 passed; 742 passed, 0 failed. Not verified: the matcher against firebase-tools' own file listing (a pattern Firebase honours but this matcher does not support blocks by design), hosting implicit exclusions end to end, a real `firebase deploy` hook run, real gcloud, POSIX. No mutation runs (operator rule).
