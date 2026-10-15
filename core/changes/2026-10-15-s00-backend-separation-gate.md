# 2026-10-15 S00 backend separation gate (deploy-line check)

## What changed

- `functions/src/release_guard.ts`: new dep `currentBranch(): Promise<string | null>` in `ReleaseGuardDeps`;
  new exports `classifyDeployLine`, `resolveDeployTarget`, `checkDeployTarget` (now exported, optional second
  argument), `DeployLine`, `DeployTargetResolution`, `DeployLineReason`, `DEPLOY_LINE_REASONS`, `PHASE2_ALIAS`,
  `LEGACY_PROJECT_ID`, `FIREBASERC_PATH`. `ReleaseGuardResult` gains `line`, `branch`, `project`.
  `checkDeployTarget` now accepts the production project only on the phase1 line and the `.firebaserc` alias
  `phase2` project only on the phase2 line.
- `functions/scripts/run_release_guard.mjs`: real `currentBranch` (`git rev-parse --abbrev-ref HEAD`), prints
  line/branch/project. Exit codes unchanged.
- `docs/phase2/split/BACKEND_SEPARATION.md`: gate description and the operator step (create the Phase 2
  Firebase project, add alias `phase2` to `.firebaserc`).

## Why

Operator decision D-4 and plan section 7: a deploy must never cross lines (Phase 2 code to production, or
Phase 1 code to the Phase 2 project).

## Contracts and paths

- Branch to line: `phase2/*` = phase2; `phase1/main`, `master`, `phase1/*` = phase1; else other (including
  detached HEAD and unreadable branch). No environment override.
- Block reasons: `deploy-line-unknown`, `phase1-wrong-project`, `firebaserc-unreadable`,
  `phase2-alias-missing`, `phase2-targets-production`, `phase2-project-mismatch`.
- `ReleaseGuardDeps.currentBranch` is required: existing test fakes must add it.
- `firebase.json` predeploy order and `.firebaserc` are untouched.

## Verification state

Not yet tested. No test, build, lint or tsc was run. A separate test agent updates
`functions/src/__tests__/release_guard.test.ts` (fakes need `currentBranch`) and adds line tests.
