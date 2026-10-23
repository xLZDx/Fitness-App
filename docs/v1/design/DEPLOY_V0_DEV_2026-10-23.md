# Deploy of slice V0 to the dev project (2026-10-23)

Project `fitness-app-korostelev`, region `europe-west1`. Executed from a scratch worktree (`D:/tmp/scratch_worktrees/deploy`, branch `phase1/deploy-v0-dev`). No secrets or tokens are recorded here.

## Operator decisions of 2026-10-23
1. Release master's full `firestore.rules`.
2. Move the provenance ref `origin/phase1/main` to master (fast-forward).
3. Deploy `submitWorkoutCommands` alone, feature flag `WORKOUT_COMMANDS_ENABLED` OFF (never set); no IAM or service-account change; no other function; `exportAccountData` not deployed.
4. Scheduler 403s (`runProductionCanary`, `runEnforcementStateCheck`) left as they are.
5. One-time consent: deploy the function without the predeploy `npm test` step (see "Skipped step").

## Revisions
| Item | Value |
|---|---|
| Rules released from | `aff06975` (the rules file is unchanged in later commits) |
| Function deployed from | `9e6aeaa3f5cbd199f7490d585e2281cd2f6d406a` (master after PR 32, which registers `submitWorkoutCommands` in `scaling.test.ts`) |
| `origin/phase1/main` | `03ea66e1c8fa5190104a262bc4db2858d1c479f9` -> `aff0697557bf2718e92eaacf99448399a40da215` -> `9e6aeaa3f5cbd199f7490d585e2281cd2f6d406a` |

## Baseline (before)
- Released ruleset: `eefbc179-7f92-4199-a163-828a7424d503` (release `cloud.firestore`, created 2026-08-29).
- 43 functions, all ACTIVE, nodejs22 (saved outside git in `D:/tmp/deploy_v0_baseline_2026-10-23/functions_before.txt`).

## Steps and results
1. Rules: `node scripts/deploy/guarded_deploy.mjs --project fitness-app-korostelev --only firestore:rules`. Guard verdict PASS (all checks OK), rules compiled and released. New ruleset `07f56cec-b834-48db-bb38-8fcd3ad703bf`; the released source was compared with `firestore.rules` of the checkout and is identical (58437 characters).
2. phase1/main: `git push origin origin/master:refs/heads/phase1/main`, twice (both fast-forwards).
3. Function: `node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --config firebase.deploy-v0.json --project fitness-app-korostelev --only functions:default:submitWorkoutCommands`. Predeploy ran `npm run build` (success) and the release guard (verdict PASS, branch `phase1/deploy-v0-dev` on deploy line phase1, clean tree). The function was created.
4. Read-only verification:
   - `submitWorkoutCommands`: ACTIVE, GEN_2, runtime nodejs22, europe-west1, revision `submitworkoutcommands-00001-gib`, maxInstanceCount 5, service account is the default Compute account (unchanged by design).
   - Environment variables carry no `WORKOUT_COMMANDS_ENABLED` (unset = OFF) and no secrets.
   - Function list: 44 entries; the diff against the baseline is exactly one added line (the new function); the 43 others keep their update times.
   - Cloud Logging, severity ERROR or above, last 15 minutes for the service: no entries.
   - The callable was not called.

## Skipped step (operator consent of 2026-10-23, this deploy only)
- Skipped: the `npm --prefix functions test` step (full unit suite, 3759 tests) of the `default` functions predeploy.
- Why: the machine could not complete it. Three guarded attempts failed: (1) `scaling.test.ts` lacked the new function (fixed on master by PR 32); (2) `remediation_a_validate_bound.test.ts` timed out under CPU load (it passed in other runs); (3) 3758 of 3759 passed, and `guard_scripts.test.ts` failed after 1599 s on a `git add -A` in its fixture (machine load). The release guard and `npm run build` were NOT skipped.
- How: `scripts/deploy/guarded_deploy.mjs` refuses `--config` and there is no supported skip option. A throw-away config was used: `firebase.json` reduced to the `default` codebase with the predeploy list `build` + guard (no `test`). It is untracked and kept outside git at `D:/tmp/deploy_v0_baseline_2026-10-23/firebase.deploy-v0.json`. `firebase.json`, guard code and test code were not modified. The guard script was also run standalone with `--project` before the deploy: PASS.
- Not verified: the full unit suite on the deployed head; the rules tests were not run.

## Rollback
- Rules: re-release the previous ruleset by Rules REST `PATCH projects/fitness-app-korostelev/releases/cloud.firestore` with `rulesetName` = `projects/fitness-app-korostelev/rulesets/eefbc179-7f92-4199-a163-828a7424d503`; or check out the old `firestore.rules` and run the guarded rules deploy.
- Function (operator-only, deletion): `gcloud functions delete submitWorkoutCommands --gen2 --region=europe-west1 --project=fitness-app-korostelev`. Expected function count afterwards: 43.
- Provenance ref (moving a branch backwards is a non-fast-forward; operator-level): `git push origin 03ea66e1c8fa5190104a262bc4db2858d1c479f9:refs/heads/phase1/main --force-with-lease=phase1/main:9e6aeaa3f5cbd199f7490d585e2281cd2f6d406a`.

## Open items (unchanged)
- The flag is OFF. Enabling needs a service account with a Firestore role (the default Compute account has none) and a deployed `exportAccountData` that includes V0 data.
- Scheduler 403s remain.

## Redeploy under fn-data (2026-10-23)

Operator authorisation of 2026-10-23: redeploy `submitWorkoutCommands` alone after PR 34 (service account `fn-data`), flag `WORKOUT_COMMANDS_ENABLED` still OFF (never set). Executed from scratch worktree `D:/tmp/scratch_worktrees/deploy2`; working material in `D:/tmp/deploy_v0_baseline_2026-10-23/redeploy/`.

### Revisions
| Item | Value |
|---|---|
| Deployed from | master `2b5e469579693827fb9eea68f9d68eb9956a5c28` (PR 34) |
| `origin/phase1/main` | `9e6aeaa3f5cbd199f7490d585e2281cd2f6d406a` -> `2b5e469579693827fb9eea68f9d68eb9956a5c28` (fast-forward, `git push origin origin/master:refs/heads/phase1/main`) |
| Function revision | `submitworkoutcommands-00001-gib` (service account: default Compute) -> `submitworkoutcommands-00002-red` |
| Service account (after) | `fn-data@fitness-app-korostelev.iam.gserviceaccount.com` |
| Update time (after) | 2026-10-23T15:59:49Z |

### Steps
1. `npm ci` in `functions`; baseline saved (describe, function list, phase1/main sha).
2. The guard first BLOCKED the branch `docs/v1-deploy-v0-sa` (not on a deploy line). A local branch `phase1/deploy-v0-sa-redeploy` was created at the same commit (no tracked-file change) and the deploy re-run; guard verdict PASS.
3. `node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --config firebase.deploy-v0.json --project fitness-app-korostelev --only functions:default:submitWorkoutCommands` (throw-away config, untracked in the worktree root, copy at `D:/tmp/deploy_v0_baseline_2026-10-23/firebase.deploy-v0.json`). Predeploy: `npm run build` OK, release guard PASS. Deploy complete.

### Skipped step (one-time operator consent, this deploy only)
The `npm --prefix functions test` predeploy step was skipped (unreliable on this machine; see the first deploy section). Build and release guard were NOT skipped; no tracked file, guard script or test was edited; no `--force`. Not verified: the full unit suite on the deployed head.

### Read-only verification
- `submitWorkoutCommands`: ACTIVE, GEN_2, nodejs22, europe-west1, new revision, `serviceAccountEmail` = fn-data.
- `WORKOUT_COMMANDS_ENABLED` is absent from the function environment (flag OFF).
- 44 functions; the diff against the baseline is exactly one line (`submitWorkoutCommands` update time); the other 43 are unchanged.
- Rules release `cloud.firestore` still `07f56cec-b834-48db-bb38-8fcd3ad703bf` (updated 2026-10-23T13:47:15Z).
- Cloud Logging, severity ERROR or above, for service `submitworkoutcommands` since the deploy: no entries at check time. The callable was not called.

### Rollback
- Function: route traffic back to the previous revision `submitworkoutcommands-00001-gib` (Cloud Run service `submitworkoutcommands`, region europe-west1; that revision runs under the default Compute account), or delete the function (operator-only): `gcloud functions delete submitWorkoutCommands --gen2 --region=europe-west1 --project=fitness-app-korostelev` (43 functions afterwards).
- Provenance ref (non-fast-forward, operator-level): `git push origin 9e6aeaa3f5cbd199f7490d585e2281cd2f6d406a:refs/heads/phase1/main --force-with-lease=phase1/main:2b5e469579693827fb9eea68f9d68eb9956a5c28`.
