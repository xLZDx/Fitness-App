# Backend separation gate (Phase 1 / Phase 2)

Source: `docs/phase2/plan/02_PHASE_SPLIT_AND_REPO_LAYOUT_2026-10-15.md` section 7, operator decision D-4
(Phase 2 gets a separate Firebase alias).

## What the gate does

The release guard (`functions/src/release_guard.ts`, CLI `functions/scripts/run_release_guard.mjs`, wired
into `firebase.json` `functions[0].predeploy`) now checks the deploy LINE before any other check.

The line comes from the current git branch (`git rev-parse --abbrev-ref HEAD`):

| Branch | Line |
| --- | --- |
| `phase2/*` | `phase2` |
| `phase1/main`, `master`, `phase1/*` | `phase1` |
| anything else, detached HEAD, unreadable | `other` |

Rules (no environment override, no bypass):

- `phase1` may deploy only to the production project `fitness-app-korostelev`.
- `phase2` may deploy only to the project id under alias `phase2` in `.firebaserc`, and never to the
  production project, `legacy-shared`, or any other alias' project.
- `other` is blocked for every deploy.

Closed block reasons (leading slug of the `Deploy target` check detail):

- `deploy-line-unknown`: branch is not on a deploy line.
- `phase1-wrong-project`: phase1 line, resolved project is not production.
- `firebaserc-unreadable`: phase2 line, `.firebaserc` missing, unparseable or without a `projects` map.
- `phase2-alias-missing`: phase2 line, no non-empty alias `phase2`.
- `phase2-targets-production`: alias `phase2` equals production, legacy or another alias' project.
- `phase2-project-mismatch`: phase2 line, resolved project differs from the `phase2` alias.

The CLI output now prints the line, branch and project, and keeps exit code 0 = PASS, 1 = BLOCK.

## Operator step (required before any Phase 2 deploy)

1. Create the separate Phase 2 Firebase project (operator-owned; not done by agents).
2. Add alias `phase2` to `.firebaserc`, for example `firebase use --add` then name it `phase2`, so that
   `projects.phase2` holds the new project id.
3. Commit the `.firebaserc` change on the `phase2/*` line.

Until then Phase 2 stays on the emulator and any Phase 2 deploy is blocked with `phase2-alias-missing`.
