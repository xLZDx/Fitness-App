# 2026-10-15 S00 deploy guard: full target coverage and commit provenance

## What changed

- `functions/src/release_guard.ts`:
  - `ReleaseGuardDeps.isCommitOnProtectedLine(): Promise<boolean>` (new, required injected dependency).
  - `resolveDeployTarget` on the phase1 line now requires it; a false result or a rejection yields
    `phase1-provenance-unverified` (added to `DEPLOY_LINE_REASONS`, now seven slugs).
  - New exports: `PROTECTED_PHASE1_REFS` (`refs/remotes/origin/phase1/main`, `refs/remotes/origin/master`),
    `PROJECT_RESOLUTION_REASONS` (`project-undeterminable`, `project-conflict`), `ProjectResolutionReason`,
    `parseDeployArgs`, `DeployArgs`, `resolveEffectiveProject`, `EffectiveProjectResolution`,
    `GUARD_COMMAND_MARKER`, `findUnguardedDeployTargets`.
- `functions/scripts/guard_deps.mjs` (new): shared real deps (gcloud/git runner, file reader, branch reader,
  `makeIsCommitOnProtectedLine` using `execFileSync("git", ["merge-base","--is-ancestor","HEAD",ref])`, no shell).
- `functions/scripts/run_release_guard.mjs`: uses the shared deps; resolves the effective project with
  `resolveEffectiveProject` (`GCLOUD_PROJECT` and/or explicit project flag, fail closed); the hardcoded
  default project fallback is removed; unexpected crashes exit 1.
- `firebase.json`: `predeploy` guard (`npm --prefix functions run build` then
  `node functions/scripts/run_release_guard.mjs`) added to `firestore`, `hosting` and `functions[1]`
  (`equipment-identity`); `functions[0]` unchanged. No `storage` block exists (no `storage.rules`).
- `scripts/deploy/guarded_deploy.mjs` (new): supported wrapper (build, refuse `--config`, resolve project,
  run guard with `GCLOUD_PROJECT`, then `firebase deploy --project <id> ...` with the repo-pinned CLI).
- `functions/package.json`: `deploy` script now goes through the wrapper.
- `docs/phase2/split/BACKEND_SEPARATION.md`: coverage, provenance, supported path, effective-project
  resolution, residual limits and open items.

## Why

GPT-PM verdict MODIFY on the S00 deploy-line guard: BLOCKER-01 (the guard ran only in `functions[0]`
predeploy, so `firestore`, `hosting` and the second functions codebase could be deployed to production from a
`phase2/*` branch, and an explicit `--project` was not tied to the CLI's real project) and BLOCKER-02 (the
phase1 line was trusted from the branch name alone).

## Contracts and paths

- Effective project: inside predeploy the firebase CLI sets `GCLOUD_PROJECT` to the resolved id (verified in
  `functions/node_modules/firebase-tools/lib/deploy/lifecycleHooks.js`). The guard accepts `GCLOUD_PROJECT`
  and/or an explicit `--project`/`--project=`/`-P` (alias via `.firebaserc`); disagreement or absence blocks.
  `FIREBASE_PROJECT` is not read by `firebase deploy` and is ignored.
- Breaking for tests: `ReleaseGuardDeps` requires `isCommitOnProtectedLine`; the test "DEPLOY_LINE_REASONS
  is exactly the closed set of six slugs" must become seven.
- Not done: separate production credentials / protected CI (operator-owned open item); per-target split of
  the check set; `firebase deploy` invoked with a different `--config` or credentials is not stoppable locally.

## Verification state

NOT YET RUN. No test, build, lint or tsc was run. Tests still to be written/run by the test agent:
provenance true/false/throw on phase1; `resolveEffectiveProject` matrix; `parseDeployArgs`;
`findUnguardedDeployTargets` against the real `firebase.json` (must be empty); the six-to-seven slug test;
fakes in `release_guard.test.ts` need `isCommitOnProtectedLine`. Not verifiable without a build: real
execution of `run_release_guard.mjs`, `guard_deps.mjs`, `guarded_deploy.mjs` and a real
`firebase deploy --dry-run` hook run.
