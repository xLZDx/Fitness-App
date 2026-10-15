# Backend separation gate (Phase 1 / Phase 2)

Source: `docs/phase2/plan/02_PHASE_SPLIT_AND_REPO_LAYOUT_2026-10-15.md` section 7, operator decision D-4
(Phase 2 gets a separate Firebase alias).

## What the gate does

The release guard (`functions/src/release_guard.ts`, CLI `functions/scripts/run_release_guard.mjs`, shared
real dependencies in `functions/scripts/guard_deps.mjs`) checks the deploy LINE before any other check.

The line comes from the current git branch (`git rev-parse --abbrev-ref HEAD`):

| Branch | Line |
| --- | --- |
| `phase2/*` | `phase2` |
| `phase1/main`, `master`, `phase1/*` | `phase1` |
| anything else, detached HEAD, unreadable | `other` |

Rules (no environment override, no bypass):

- `phase1` may deploy only to the production project `fitness-app-korostelev`, and only when HEAD is
  verified to be on the protected Phase 1 line (see "Commit provenance" below).
- `phase2` may deploy only to the project id under alias `phase2` in `.firebaserc`, and never to the
  production project, `legacy-shared`, or any other alias' project.
- `other` is blocked for every deploy.

Closed block reasons (leading slug of the `Deploy target` check detail; exported as `DEPLOY_LINE_REASONS`):

- `deploy-line-unknown`: branch is not on a deploy line.
- `phase1-wrong-project`: phase1 line, resolved project is not production.
- `firebaserc-unreadable`: phase2 line, `.firebaserc` missing, unparseable or without a `projects` map.
- `phase2-alias-missing`: phase2 line, no non-empty alias `phase2`.
- `phase2-targets-production`: alias `phase2` equals production, legacy or another alias' project.
- `phase2-project-mismatch`: phase2 line, resolved project differs from the `phase2` alias.
- `phase1-provenance-unverified`: phase1 line, HEAD is not verified to be on the protected Phase 1 line.

Closed reasons for the effective-project step (exported as `PROJECT_RESOLUTION_REASONS`; the CLI blocks
before any other check):

- `project-undeterminable`: neither `GCLOUD_PROJECT` nor an explicit project flag is present, a flag has
  no value, or a combined short-flag token (for example `-ic x.json`, `-iPprod`) could hide `--config` or
  `--project`.
- `project-conflict`: `GCLOUD_PROJECT` and the project flag disagree, or several different project flags.
- `project-invalid`: the resolved project is not a valid project id (`PROJECT_ID_PATTERN`,
  `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`); the id is interpolated into gcloud arguments, so it is refused before any
  command runs. `runReleaseGuard` applies the same check to `deps.project` and reports it as a failing
  `Deploy target` check whose detail leads with `project-invalid`.

Order inside `runReleaseGuard`: the deploy-target check runs FIRST. If it does not pass, no gcloud or git
state command is run; the nine remaining checks are reported as `UNAVAILABLE` with the detail "not run: the
deploy-target check did not pass" and the verdict is BLOCK. Each remaining check is also wrapped, so an
unexpected throw becomes an `UNAVAILABLE` check with the error message instead of aborting the report.

The CLI output prints the line, branch and project, and keeps exit code 0 = PASS, 1 = BLOCK.

## Commit provenance (Phase 1)

The branch name is not proof of what is checked out: a local branch called `phase1/x` can hold Phase 2
commits. A phase1 deploy therefore also requires commit-ancestry proof:
`git merge-base --is-ancestor HEAD <ref>` must succeed for at least one of
`refs/remotes/origin/phase1/main` or `refs/remotes/origin/master` (`master` stays valid while it is still a
Phase 1 branch name). It is the injected dependency `isCommitOnProtectedLine` (real implementation in
`guard_deps.mjs`, `execFileSync`, no shell). Fail closed: a missing ref, a git failure, or a HEAD with
commits outside the protected line all block with `phase1-provenance-unverified`. The guard does not fetch;
run `git fetch origin` first so the remote-tracking refs are current (a stale ref only makes the check
stricter for newer commits).

## Coverage: every deploy target runs the guard

`firebase.json` runs the same guard (`node functions/scripts/run_release_guard.mjs`) in the `predeploy` hook
of every deploy target present: `functions[0]` (`default`), `functions[1]` (`equipment-identity`),
`firestore`, `storage` (added by the Body Scan + Nutrition Coach merge, `storage.rules`) and `hosting`. The schema of the pinned firebase-tools (`schema/firebase-config.json`) accepts
`predeploy` for `firestore`, `hosting`, `storage`, `database`, `dataconnect` and `remoteconfig`; the
non-functions targets rebuild `functions/lib` first so the guard is never stale.

A deploy target counts as guarded only when its `predeploy` contains the exact command
`node functions/scripts/run_release_guard.mjs` (`GUARD_COMMAND`); a bare substring such as an `echo` of the
script name does not count. The wrapper `guarded_deploy.mjs` runs `findUnguardedDeployTargets` on the real
`firebase.json` and refuses to deploy when any present target lacks the guard or the file is unreadable.

The `storage` block arrived with the Body Scan + Nutrition Coach merge and carries the guard. Any future
`database`, `dataconnect` or `remoteconfig` block, or a second `storage` entry, MUST carry the same `predeploy` guard entries; the exported
`findUnguardedDeployTargets(firebaseJson)` lists any present deploy target that lacks the guard and is the
basis for a mechanical test. `apphosting`, `auth` and `extensions` have no `predeploy` hook in the schema
and must not be added to `firebase.json` without a separate guard decision.

Note: the guard runs the full release-guard check set for every target (the AI-gateway live checks are not
split per target), so a deploy to the Phase 2 project is also blocked by those live checks until the Phase 2
project has its own matching setup. Splitting the check set per target is not done here.

## Supported deploy path

```
node scripts/deploy/guarded_deploy.mjs --only firestore:rules --project <alias-or-id>
```

(`npm run deploy` in `functions/` uses it for `functions:default`.) The wrapper builds the guard library,
refuses `--config`/`-c` and short-flag clusters that could hide them (`-ic x.json`, `-iPprod`; pass flags
separately, `-m message` and the long flags are unaffected), checks that every target in `firebase.json` is
guarded, determines the project, runs the guard with `GCLOUD_PROJECT` set to it, and only on
PASS runs the repo-pinned `firebase deploy --project <id> ...`. Without `--project` it derives the project
from the deploy line and passes it explicitly, so the CLI's per-user active project can never redirect the
deploy. The `predeploy` hooks then run the guard again inside the CLI as a backstop (deliberate duplication).

## Effective project resolution

Verified in firebase-tools 15.17.0 (`lib/deploy/lifecycleHooks.js`, `lib/command.js`): inside a `predeploy`
hook the CLI sets `GCLOUD_PROJECT` to the resolved project id (an alias is already mapped through
`.firebaserc`). The CLI picks the project from `--project`/`-P`, else the per-user `firebase use` store, else
the single/`default` alias in `.firebaserc`; `FIREBASE_PROJECT` is read only by `firebase init`.
`resolveEffectiveProject` therefore accepts only `GCLOUD_PROJECT` and/or an explicit project flag (alias
resolved through `.firebaserc`), blocks when they disagree, and blocks (`project-undeterminable`) when
neither is present; it never falls back to a hardcoded or `.firebaserc`-default project. An explicit
`--project <production>` from a `phase2/*` branch is caught: the project reaches the guard through
`GCLOUD_PROJECT` and fails `phase2-project-mismatch`.

## Residual limits (not solved)

- A local guard cannot stop someone who bypasses it: calling the firebase CLI with a different
  `--config`, a different working directory, `--only` on a target without hooks, or different credentials,
  or editing `firebase.json`. Real enforcement needs separate production deploy credentials and/or
  protected CI. This is operator-owned and an OPEN ITEM, not claimed as solved.
- Provenance depends on the local remote-tracking refs; it does not contact the remote.
- The clean-tree check covers `functions`, `functions-equipment-identity`, `firebase.json`, `.firebaserc`,
  `.gitignore`, the release-evidence file, `firestore.rules`, `firestore.indexes.json`, `storage.rules` and
  `public`, plus any rules, indexes, hosting public dir and functions source named in `firebase.json`.
- Git-IGNORED files are checked too (`git status --porcelain --ignored=matching`, entries starting with `!!`):
  Firebase uploads everything in the hosting public dir and the functions source except the target's own
  `ignore` list, so an ignored file such as `public/app.js` would reach production without being in the
  verified commit. An ignored entry under a deploy-relevant path blocks (detail leads with
  `ignored-deployable-files:` and lists the paths) unless it is: (a) inside the compiled output dirs
  `functions/lib` or `functions-equipment-identity/lib` (built by `predeploy` from tracked source and packaged
  by design, `main` is `lib/index.js`); (b) excluded by the target's own `ignore` list in `firebase.json`
  (functions: `functions[].ignore`, with the firebase-tools default `["node_modules", ".git"]` only when no
  `ignore` key exists, plus `firebase-debug*.log`, and slash-free patterns also match at any depth as in
  firebase-tools; hosting: `hosting.ignore`; supported pattern forms: exact names, `*`/`?` globs, `**/` and
  `/**`; an ignored directory excludes its contents; unsupported pattern syntax never matches, so it can only
  make the check stricter); or (c) a functions env file, `.env` or `.env.*` directly in a functions source dir
  (deploy input by design). `node_modules` is NOT allowed unconditionally: it is allowed only through rule (b),
  so `hosting.ignore: []` with an ignored `public/node_modules/...` blocks. With an unreadable `firebase.json`
  the strict mode has no ignore lists, so an ignored `functions/node_modules` also blocks (fail closed). The candidate dotenv
  content is NOT verified by the guard: this is the known open item (2) below. A `git status` failure or a
  quoted (special-character) path fails closed. Expect to remove stray ignored files before a deploy, for
  example `functions/.runtimeconfig.json`, `functions/jest_result.json`, `functions/coverage/`, other `*.log`
  files or `Thumbs.db` in `public/`: Firebase would upload them.

## Operator step (required before any Phase 2 deploy)

1. Create the separate Phase 2 Firebase project (operator-owned; not done by agents).
2. Add alias `phase2` to `.firebaserc`, for example `firebase use --add` then name it `phase2`, so that
   `projects.phase2` holds the new project id.
3. Commit the `.firebaserc` change on the `phase2/*` line.

Until then Phase 2 stays on the emulator and any Phase 2 deploy is blocked with `phase2-alias-missing`.

## Open items (operator)

- Separate production deploy credentials / protected CI for Phase 1 production deploys.
- Decide whether the guard check set should be split per deploy target for the Phase 2 project.

## Open items before the first Phase 2 cloud deploy

1. `functions/src/abuse_guard.ts` (around line 206) hardcodes
   `projects/988522745882/secrets/ai-gateway-kill-switch/versions/latest`, and `988522745882` is the
   PRODUCTION project number (the Phase 2 project `fitness-app-phase2-korostelev` is `254096452830`). The
   secret path must become project-relative, with its own kill-switch secret in the Phase 2 project. This is
   runtime code, not the deploy guard, and is a separate sprint.
2. The release guard reads the previously deployed environment, not the candidate's deploy-time environment
   (`process.env` and `functions/.env*` files, last value wins), and the body-scan bucket check can be skipped
   silently if the dotenv sources are not read. Pre-existing from PR #5 and out of scope of S00; backlog for a
   guard hardening sprint.
3. Blaze billing for the Phase 2 project (operator; the billing account's project quota is exceeded).
4. Residual limit already stated above: a local guard cannot stop use of the firebase CLI with another
   config or credentials; separate production deploy credentials or protected CI are operator-owned.
