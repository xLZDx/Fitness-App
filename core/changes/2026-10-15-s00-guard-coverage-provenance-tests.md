# S00: focused tests for the guard coverage and provenance fix

Date: 2026-10-15. Branch: `phase2/s00-split-docs`. Tests for commit `915c52b0` (change record `core/changes/2026-10-15-s00-guard-coverage-provenance.md`).

## What changed
- `functions/src/__tests__/release_guard.test.ts`: every fake dependency set gets `isCommitOnProtectedLine`; the closed reason set is now seven slugs; new tests for provenance (true, false, rejection, synchronous throw, non-boolean value, Phase 2 content under a `phase1/x` branch name, provenance never consulted on `phase2/*` or unknown branches), `parseDeployArgs`, the `resolveEffectiveProject` matrix (env only, `--project X`, `--project=X`, `-P X`, `-PX`, alias mapping, missing value, neither source, conflicting flags, env/flag disagreement, ignored `FIREBASE_PROJECT` and `GOOGLE_CLOUD_PROJECT`, no fallback to the `.firebaserc` default alias), seven ways of naming the production or legacy project from a `phase2/*` branch (all blocked), and `findUnguardedDeployTargets` against the real `firebase.json` (empty list) and against synthetic configurations (firestore only, hosting only, functions[0] only, functions[1] only, a future `storage` block, unknown sections, malformed predeploy values).
- `functions/src/__tests__/guard_scripts.test.ts` (new): runs `guard_deps.mjs`, `run_release_guard.mjs` and `scripts/deploy/guarded_deploy.mjs` as real node child processes in throwaway fixture roots with a throwaway git repository, a fake `gcloud` (always unavailable) and a fake firebase CLI that records its arguments. Covers real-git provenance (HEAD equal to, ancestor of, ahead of, diverged from the protected ref, missing ref, local branch with the protected name, empty ref list, not a repository), fail-closed project resolution, `--config` refusal, blocking before the guard and before firebase, firebase receiving exactly `deploy --project <id> ...`, and exit-code propagation.
- No product code changed.

## Why
GPT-PM round 1 BLOCKER-01 (coverage of every deploy target) and BLOCKER-02 (provenance, not branch-name trust) require negative tests for production-targeted deploys from Phase 2, a Phase 2 content under a Phase 1 branch name, and reciprocal Phase 1 checks.

## Affected contracts and paths
Test files only.

## Verification state
Run by the test-writing agent (`tdd-guide`, Sonnet 5.5): `release_guard.test.ts` 232 passed, 0 failed; `guard_scripts.test.ts` 43 passed, 0 failed; combined run 275 passed, 0 failed (previous suite: 115). `functions/node_modules` is an untracked copy from another checkout; jest 29.7.0 and typescript 5.9.3 match the lockfile, ts-jest is 29.4.12 against a `^29.2.5` range, other packages were not diffed.
Not verified: a real `firebase deploy --dry-run` predeploy hook run and the real CLI exporting `GCLOUD_PROJECT` into the hook; real gcloud output; the wrapper's pass path against the real guard (needs live GCP state); a real `npm run build` of `functions/lib`; POSIX behaviour (tests ran on Windows with Git Bash). `findUnguardedDeployTargets` is enforced only when this test file runs, not at deploy time. No mutation runs were made (operator rule).
