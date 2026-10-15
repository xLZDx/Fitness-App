# S00: tests for the git-ignored deployable files check

Date: 2026-10-16. Branch: `phase2/s00-split-docs`. Tests for commit `9987f02d` (record `core/changes/2026-10-16-s00-guard-ignored-files.md`).

## What changed
- `functions/src/__tests__/release_guard.test.ts` and `guard_scripts.test.ts`: tests broken by the new `git status --porcelain --ignored=matching` invocation were updated without weakening any assertion; new unit tests (git fake that reports only paths covered by the pathspec, as real git does) for ignored files that must block (`public/app.js`, nested public files, `functions/src/*`, second-codebase sources, `.runtimeconfig.json`, rules and indexes files, quoted paths, env files nested below the source dir), ignored entries that must be allowed (dot files by `**/.*`, `node_modules`, `functions/lib` and `functions-equipment-identity/lib`, `.env` and `.env.<project>`, `*.local`), scope (ignored entries outside the deploy scope do not matter), mixed output (uncommitted change is reported first), unreadable `firebase.json` (strict classification), unsupported ignore-pattern syntax (never matches, so stricter), truncation of more than 20 offenders, and `git status` failure (UNAVAILABLE, BLOCK).
- New end-to-end tests with real git, a real committed `.gitignore`, the real guard script and the real wrapper: an ignored `public/ignored_app.js`, invisible to plain `git status --porcelain`, makes the guard exit 1 with `ignored-deployable-files:` and `guarded_deploy.mjs` does not spawn firebase; a control run without the file deploys; all allowed kinds together still pass.
- No product code changed.

## Why
GPT-PM round 2 on `4c635f75` returned MODIFY with MAJOR-02A: the clean-tree check could not see git-ignored files that Firebase uploads.

## Affected contracts and paths
Test files only.

## Verification state
Run by `tdd-guide` (Sonnet 5.5) on `9987f02d`: `release_guard.test.ts` 477 passed, `guard_scripts.test.ts` 101 passed (about 320 s), `scaling.test.ts` 125 passed; 703 passed, 0 failed. Not verified: `git status` failing end to end (covered at unit level only; removing `.git` is blocked earlier at the deploy target), the matcher against Firebase's own ignore implementation (patterns Firebase honours but this matcher does not support block by design), a real `firebase deploy` hook run, real gcloud, POSIX. No mutation runs (operator rule).
