# 2026-10-15 S00 deploy guard: review fixes (security and silent-failure reviewers)

## What changed

- `functions/src/release_guard.ts`:
  - A: `checkSourceProvenance` scopes `git status` to the fixed list plus `firestore.rules`,
    `firestore.indexes.json`, `storage.rules`, `public`, and any rules, indexes, hosting public dir and
    functions source named in `firebase.json` (safe repo-relative paths only; the fixed list is the fallback).
  - B: `parseDeployArgs` adds `hasShortFlagCluster` (a token matching `/^-[A-Za-z]{2,}/` that contains `c` or
    `P` and is not a `-P<value>` or `-c...` token); `resolveEffectiveProject` blocks it as
    `project-undeterminable`.
  - C: new `PROJECT_ID_PATTERN` (`^[a-z][a-z0-9-]{4,28}[a-z0-9]$`) and new reason `project-invalid`
    (`PROJECT_RESOLUTION_REASONS` now has three slugs). `runReleaseGuard` validates `deps.project`, resolves and
    checks the deploy target BEFORE any gcloud or git-state call; on failure it returns BLOCK with the target
    check plus nine `UNAVAILABLE` "not run" checks in a fixed order.
  - E: new `GUARD_COMMAND`; `findUnguardedDeployTargets` requires the exact trimmed command, not a substring
    (`GUARD_COMMAND_MARKER` is kept for compatibility).
  - F: every check in `runReleaseGuard` is wrapped (`guardedCheck`); a throw becomes an `UNAVAILABLE` check with
    the error message. New exported `CHECK_NAME` holds the check names in one place.
- `scripts/deploy/guarded_deploy.mjs`: B (blocks short-flag clusters) and D (runs
  `findUnguardedDeployTargets` on the parsed `firebase.json`; an unreadable file blocks).
- `docs/phase2/split/BACKEND_SEPARATION.md`: new slugs, order of checks, exact guard command, wrapper
  behaviour, provenance scope, and "Open items before the first Phase 2 cloud deploy".

## Why

Two internal reviewers (security, silent-failure) found: deploy inputs outside the clean-tree scope, hidden
`-c`/`-P` in short-flag clusters, an unvalidated project id interpolated into gcloud arguments and gcloud
running before the target was validated, a substring guard match, and a single throwing check aborting the
report.

## Contracts and paths

- Reason slugs: added `project-invalid`; `DEPLOY_LINE_REASONS` unchanged. A blocked run now reports 10 checks
  (target first, nine "not run" `UNAVAILABLE`); a healthy run is unchanged.
- Not done here (recorded in the docs): deploy-time env and dotenv reading, and the hardcoded production
  secret path in `abuse_guard.ts`.
- Tests likely affected: the provenance `git status` args test, the closed `PROJECT_RESOLUTION_REASONS` set,
  tests that expected other checks to run after a blocked target, and tests using a project id that does not
  match `PROJECT_ID_PATTERN`.

## Verification state

NOT YET RUN: no test, build, tsc or lint. The test agent follows.
