# 2026-10-15 S00 backend separation gate: focused tests

## What changed

- `functions/src/__tests__/release_guard.test.ts`:
  - `makeDeps` now provides the new required dep `currentBranch` (default `phase1/main`, so every existing
    expectation holds) and serves `.firebaserc` through `readFile` (default: production + legacy aliases only).
    New options `branch`, `branchThrows`, `firebaserc`. No existing assertion was changed or weakened.
  - New tests (63 added, 52 pre-existing): `classifyDeployLine` mapping (17 cases), the closed reason set, PASS paths for both
    lines, every reason slug (`deploy-line-unknown`, `phase1-wrong-project`, `firebaserc-unreadable`,
    `phase2-alias-missing`, `phase2-targets-production`, `phase2-project-mismatch`) with boundary inputs, detail
    formats, the phase2 run with the default production project fallback (blocks), result fields
    `line`/`branch`/`project`, and a no-override test (env vars and extra deps fields cannot flip a block).
- No other file constructs `ReleaseGuardDeps` (`scaling.test.ts` only mentions the module in a test title).
- No product code was changed.

## Why

Prove the S00 deploy-line gate (operator decision D-4) at the behavior level, deterministically, with fakes.

## Verification state

`cd functions; npx jest src/__tests__/release_guard.test.ts`: 1 suite passed, 115 tests passed, 0 failed.
Not verified: `run_release_guard.mjs` real execution (read only; it needs the compiled `lib/` and gcloud), and the
real `git rev-parse --abbrev-ref HEAD` branch reader. `functions/node_modules` was copied (untracked) from the main
checkout to run Jest; the two lockfiles differ, so dependency versions are not guaranteed identical.
