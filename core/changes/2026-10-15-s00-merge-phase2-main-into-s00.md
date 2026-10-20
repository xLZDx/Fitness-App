# S00: merge `origin/phase2/main` (PR #5) into the S00 branch

Date: 2026-10-15. Branch: `phase2/s00-split-docs`. Merged: `origin/phase2/main` at `5137ccda` (PR #5, Body Scan and Nutrition Coach, approved head `cd9d7c3a`).

## What changed
- The S00 branch was created from `42d1b849` and did not contain the PR #5 code, so merging it into `phase2/main` conflicted in four files. This merge integrates both sides before the S00 PR is opened.
- `functions/src/release_guard.ts`: union of the PR #5 release-guard checks (six callables, `BODY_SCAN_BUCKET` check and canary, flag checks) and the S00 deploy-line work (`currentBranch`, `isCommitOnProtectedLine`, effective-project resolution, provenance, coverage helper). `ReleaseGuardDeps` is the union of both sides.
- `functions/scripts/run_release_guard.mjs`: passes `currentBranch`, `isCommitOnProtectedLine` and `env: process.env` to the merged guard.
- `functions/src/__tests__/release_guard.test.ts`: both sides' tests kept (S00 tests first, then PR #5 tests).
- `firebase.json`: PR #5 added a `storage` block (`storage.rules` now exists) without a guard; the same guard commands were added to it, so every deploy target (functions[0], functions[1], firestore, hosting, storage) carries the guard. `docs/phase2/split/BACKEND_SEPARATION.md` and `core/changes/2026-10-15-s00-guard-coverage-provenance.md` were corrected (they said there is no storage block).
- `core/DECISION_LOG.md`: both sides' entries kept; one new entry.
- `docs/DOCUMENT_REGISTRY.md`: regenerated.

## Why
The S00 PR must merge into `phase2/main` without conflicts and without leaving an unguarded deploy target. GPT-PM round 2 must be run on the merged head.

## Affected contracts and paths
Release guard (`functions/src/release_guard.ts`, `functions/scripts/*`), `firebase.json` predeploy hooks, documents. No Firestore or Storage rules changed.

## Verification state
The conflict resolution was textual (done by `implementation-engineer`); nothing was compiled or run in this commit. The test agent reruns the complete guard test set after this commit (the PR #5 expectations of 10 and 11 checks were written against the pre-merge guard and the real `firebase.json` must report no unguarded target). Results will be in the next change record.
