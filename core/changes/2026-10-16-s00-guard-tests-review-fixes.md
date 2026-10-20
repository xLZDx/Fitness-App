# S00: tests for the guard review fixes

Date: 2026-10-16. Branch: `phase2/s00-split-docs`. Tests for commit `f26ab450` (record `core/changes/2026-10-15-s00-guard-review-fixes.md`).

## What changed
- `functions/src/__tests__/release_guard.test.ts` and `functions/src/__tests__/guard_scripts.test.ts`: 19 tests that broke under the new contract were updated without weakening any assertion (exact `git status` path list, three project-resolution reasons, `hasShortFlagCluster` field, deploy-target check runs first and the other nine checks are reported as UNAVAILABLE "not run" with no command issued).
- New tests: clean-tree scope (rules, indexes, storage rules, `public`, functions sources, paths named in `firebase.json`, unsafe paths ignored, unreadable `firebase.json` falls back to the fixed list, also against real git); short-flag clusters (`-ic`, `-jc`, `-iPprod`, `-fc`, `-xP`) blocked in the resolver and the wrapper while legitimate flags still work; `PROJECT_ID_PATTERN` boundaries and twelve malformed ids rejected from env, flag and `deps.project`; zero gcloud/git-state calls on a blocked target (unit and end to end); every gcloud call carries the deploy project; wrapper blocks an unguarded or unreadable `firebase.json`; exact guard command (eight neutered variants count as unguarded); throwing checks become UNAVAILABLE and the report stays complete; process runner semantics (exit 0, non-zero with JSON, timeout, missing command, quoted filter); an end-to-end full PASS of `run_release_guard.mjs` with a committed fixture repo and a canned fake gcloud; all `GIT_*` variables stripped from fixtures.
- `docs/DOCUMENT_REGISTRY.md`: regenerated; `scripts/dev/gen_document_registry.py` no longer lists `core/DECISION_LOG.md` (its size changes with every commit, which made the registry stale after each decision-log entry; the log stays the canonical decision record).
- No product code changed.

## Why
Operator rule: the test-writing agent writes and runs every test for the code it changed. The internal security and silent-failure reviews (2026-10-15) required these cases.

## Affected contracts and paths
Test files and the derived registry.

## Verification state
Run by `tdd-guide` (Sonnet 5.5) on `f26ab450`: `release_guard.test.ts` 397 passed, `guard_scripts.test.ts` 86 passed, `scaling.test.ts` 125 passed; 608 passed, 0 failed (`guard_scripts.test.ts` takes about 200 s). Not verified: a real `firebase deploy` predeploy hook run, real gcloud output, the body-scan bucket check against a live bucket (the PASS fixture runs without a bucket), POSIX variants, whether a timed-out `gcloud` child survives on Windows (`shell: true` plus `SIGKILL` probably kills only `cmd.exe`). No mutation runs (operator rule).
