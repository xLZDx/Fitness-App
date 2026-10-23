# Environment preparation for deploying slice V0 to the dev project (2026-10-23)

Scope: read-only recon of project `fitness-app-korostelev` (region `europe-west1`) against `master` at `4a5e6b6d`. Nothing was deployed, set, created, updated or called. Every fact below was read on 2026-10-23 from `gcloud` read commands, the Firebase Rules REST API (GET only), `firebase functions:list`, git, or the repository files cited. Items marked INFERENCE or UNKNOWN were not measured.

Inputs: `SOURCE_RUNTIME_MANIFEST_2026-10-22.md`, `PRE_IMPLEMENTATION_CONDITIONS_2026-10-22.md` section 5, merged slice V0 (`84ea5636`).

## Summary

| # | Finding | Severity for the V0 deploy |
|---|---|---|
| 1 | The released Firestore ruleset is from 2026-08-29 and is about 700 lines behind master. It does not contain the five V0 carve-outs, so today the owner wildcard lets a client write the five V0 collection names. Releasing master's full file is NOT a minimal change. | Decision needed |
| 2 | `submitWorkoutCommands` uses the default Compute service account, which has no Firestore role on the project. With the flag on, every call would hit a Firestore permission error (INFERENCE). With the flag off nothing is touched. | Blocks enabling, not deploying |
| 2 | The release guard requires `HEAD` to be contained in `origin/phase1/main` (now `03ea66e1`, 28 commits behind master) and the branch to be `master` or `phase1/*`. A guarded deploy is blocked until that ref is moved. | Blocks deploying |
| 3 | `P1_SNAPSHOT_STALE` is a false alarm caused by line endings, not stale content. Git blobs are identical. | Cosmetic, one-line fix |
| 4 | The two scheduler 403s are an invoker mismatch: the jobs authenticate as the default Compute service account, the Cloud Run services only allow the function's own service account. | Pre-existing, independent of V0 |

## 1. Firestore rules

### 1.1 What is released

- FACT: `GET projects/fitness-app-korostelev/releases` returns exactly one release, `cloud.firestore`, pointing to ruleset `eefbc179-7f92-4199-a163-828a7424d503`, created 2026-08-29T01:04:18Z, release updated 2026-08-29T01:04:21Z. 382 lines.
- FACT: ruleset history (newest first): `eefbc179` (2026-08-29 01:04), `ce36df36` (2026-08-29 00:34), `28f058a8` (2026-08-27), `298949ea` (2026-08-05).
- FACT: no rules were released when the project was brought to master `03ea66e1` on 2026-10-22 (the manifest section 6 does not list a rules release, and the release date confirms it).
- Method: the ruleset source was downloaded into a scratch file outside the repository and diffed against `firestore.rules` on master with whitespace, blank lines and CR ignored. The 539-line comment-stripped diff was read in full.

### 1.2 Semantic differences (released -> master)

Group A, the five V0 carve-outs (the only rules change since the deployed function code at `03ea66e1`; 45 lines in `84ea5636`):
- `workout_command_fence`, `workout_command_receipts`, `workout_command_policy`, `workout_command_counters`, `workout_typed_sessions` are added to the exclusion list of BOTH the read and the write condition of the owner wildcard `match /users/{uid}/{coll}/{document=**}`.
- Five `match` blocks with `allow read, write: if false;` are added.

Group B, everything else that master's file changes and that is NOT in the released ruleset (all older than V0, none released yet):
1. Owner wildcard: 12 more collections excluded from read and write (`equipment_identity_latest_session`, `body_scans`, `body_scan_settings`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`, `activities`, `activity_streams`, `activity_settings`, `activity_tombstones`); `profile` is also excluded from the wildcard read (it was already excluded from the write).
2. New shape-validating blocks, which replace the old unrestricted owner write:
   - `weight_entries` (date key, `kg` 30..300, `source` manual|scan), `food_entries` (closed key set, at most 30 items, slot and source enums, totals ranges), `saved_foods`, `nutrition_plan` (closed key set, `planVersion` must increment by exactly 1 on update, id must be `main`), `nutrition_plan_reviews` (create only, no update), `body_scan_settings` (id `main`, retention in 0/30/90/365, consent monotonic and equal to `request.time`).
   - `body_scans`: client create and delete denied; client update limited to `weightKg` (30..300) and `clientNote` (at most 200 chars).
   - `activities`: strict summary schema, `rev` must increase, tombstone and account-fence check by `exists()`, client delete denied. `activity_streams`, `activity_settings`, `activity_tombstones`: client read only.
3. Profile document: health map and health flags now require a closed key set (`hasOnly`); `nutritionGuidance` and `foodAllergens` must be empty; a new `nutrition` map is shape-checked (`nutritionOk`). An unknown key now fails the whole profile save.
4. `debug_sessions`: client `create` was allowed (with a key list and at most 500 events); now `create: false` (the writer is the callable `sendDebugTelemetry`, which is deployed).
5. `isOrdinaryUser()` (no canary token) replaces the bare `request.auth != null` on the profile read/write and three other read grants.
6. New explicit deny blocks: `accountDeletionRetries`, `equipment_identity_latest_session`, `equipment_model_text_keys`, `nutrition_cache`, `body_scan_purge_state`. Of these only `users/{uid}/equipment_identity_latest_session` was previously client-writable (through the wildcard); the others were default-denied already.
- No difference was found that loosens a previously closed path.

### 1.3 What releasing master's full file would change

- For the deployed functions: nothing (INFERENCE, strong). All 41 default-codebase functions and the 2 equipment-identity functions use the Admin SDK, which bypasses rules; they are server callers of these collections (`body_scans`, `activity_*`, `sendDebugTelemetry`).
- For the shipped app: UNKNOWN which build is in users' hands (master's `mobile/pubspec.yaml` says `1.0.0+14`; I did not find a record of the shipped build). A client built before the corresponding rules would be refused when it:
  - creates a debug session directly (the master app uses the callable since `660856e8`, 2026-10-16) -> only debug telemetry is lost;
  - writes `weight_entries`, `food_entries`, `saved_foods`, `nutrition_plan*`, `body_scan_settings` or `activities` in a shape that master's validators do not accept, or writes `body_scans` / deletes `activities`;
  - saves a profile containing a health key outside the closed list or a non-empty `nutritionGuidance` / `foodAllergens`.
  Those feature screens were added on 2026-10-15 (food diary `7f4ed32e`, body scan `13aabb4c`), after the released ruleset, so a build that predates them cannot hit these paths and a build that has them was written against these validators (the rules tests in the repo cover them). Risk is therefore concentrated in a mid-range build; verify the shipped version before a full release.
- Not verified here: that master's file compiles and stays inside the rules expression budget in the live service (repo tests exist; I did not run them).

### 1.4 Is the full release safe, and what is the minimal V0 deploy

- Releasing master's full file is probably safe for the deployed functions but widens the blast radius to every existing client for a slice that only needs five collections closed. It is not the minimal change.
- Minimal safe deploy for V0 (proposal): release a ruleset equal to the CURRENTLY RELEASED source plus only Group A (add the five names to the two exclusion lists at the two `coll != 'equipment_identity_telemetry';` anchors, and add the five `if false` blocks). The five collections do not exist in the shipped app, so existing clients see no change at all.
- Why the carve-outs are needed before the flag is turned on: with the released ruleset the wildcard allows any signed-in owner to read and write `users/{uid}/workout_command_receipts` and the other four names, so a client could forge a receipt, a fence entry or a policy document before the callable ever writes it.
- `firebase deploy --only firestore:rules` always uploads the whole `firestore.rules` from the checkout; there is no flag to release a part. To release only Group A, the repository needs a rules file equal to released + Group A (a temporary file or branch; the operator decides where it lives), and the deploy must use a config that points to that file. Note the repository rule that the guard hooks stay in `firebase.json`; use the supported `guarded_deploy.mjs` path.
- Alternative (operator decision D-1 below): release master's full file after a shipped-build check.

## 2. Functions

### 2.1 Deployed versus master

- FACT: `gcloud functions list` (europe-west1) returns 43 functions, all 2nd gen, all `ACTIVE`, all `nodejs22`. 41 updated between 2026-10-22T15:14:08Z and 15:14:56Z (deploy of `03ea66e1`); `equipmentIdentityRecordTelemetry` (2026-10-22T07:01Z) and `equipmentIdentityResolveFromText` (07:05Z) are from the runtime migration and run older source with max instances 100.
- FACT: master's `functions/src/index.ts` exports 42 functions. The 41 default-codebase deployed names equal 41 of them; the only export not deployed is `submitWorkoutCommands`. No deployed function is missing from master. (The two equipment-identity functions belong to the second codebase, `functions-equipment-identity`.)
- FACT: since `03ea66e1` master changed function source in two places: the new `workout_commands/` module with its export, and `account_export.ts` (adds the V0 collections to the data export). So the deployed `exportAccountData` is behind master; it does not export V0 data. `deleteAccount` already uses `recursiveDelete(users/{uid})`, which covers the V0 subcollections.
- FACT: `firebase.json` has two function codebases: `default` (`functions/`) and `equipment-identity` (`functions-equipment-identity/`), both `nodejs22`.

### 2.2 What the targeted deploy does

- Command syntax per `firebase.json`: `firebase deploy --only functions:default:submitWorkoutCommands` (`codebase:function`). In the repo-pinned CLI (15.17.0, `lifecycleHooks.js`) a `functions:<codebase>:<fn>` target selects only configs whose `codebase` equals `default`, so only the `default` predeploy runs; the equipment-identity predeploy does not run.
- It would deploy: one new 2nd-gen callable `submitWorkoutCommands`, region europe-west1, nodejs22, `maxInstances: 5` (bundle `RARE`), `enforceAppCheck` = value of env `APP_CHECK_ENFORCED` (unset -> false), built from the master checkout, public invoker as for every callable.
- It would NOT touch: the other 42 functions (no redeploy, no deletion, no config change), the equipment-identity codebase, Firestore rules, indexes, Storage rules, Hosting, Cloud Scheduler jobs. (Firebase only deletes functions when a whole codebase is deployed without the filter.)
- Predeploy for the `default` entry: `npm run build`, `npm test` (the full unit suite of `functions`), then `node functions/scripts/run_release_guard.mjs`.

### 2.3 What the new callable needs

| Need | Status on the project |
|---|---|
| Secrets | None declared by `apply.ts` (no `secrets:` option). Nothing to create. |
| Environment variable `WORKOUT_COMMANDS_ENABLED` | Not set anywhere. No `functions/.env*` file exists in the repo (gitignored) and none of the checked deployed functions has user variables. Unset means OFF: the callable answers `failed-precondition: feature-disabled` and writes nothing. |
| Environment variable `APP_CHECK_ENFORCED` | Not set; no enforcement (as for the existing callables). |
| Region | europe-west1 in the `RARE` bundle (matches). |
| Service account | `RARE` sets none, so the default Compute service account `988522745882-compute@developer.gserviceaccount.com` runs it. FACT: the project IAM policy gives that account only `roles/cloudbuild.builds.builder`. It has no `roles/datastore.user` (granted to `fn-account-delete`, `fn-ai-runtime`, `fn-billing`, `fn-bodyscan`, `fn-data`, `fn-video`) and no editor role (only the App Engine default account has `roles/editor`). INFERENCE: with the flag on, `assertAccountExists` and the transaction would fail with a Firestore permission error. The eleven other functions that also run as the Compute account (the activity stream functions and `sendDebugTelemetry`) are exposed to the same question; their runtime behaviour was not verified. Fix options are in D-4.
| Build | Cloud Build, Artifact Registry, Cloud Run, Eventarc, Cloud Scheduler and Firebase Rules APIs are enabled. |
| Firestore indexes | None required (document gets and transactional reads only; `firestore.indexes.json` has no V0 entry). |
| Rules | The five carve-outs from section 1.4. |

### 2.4 Does the Windows quirk or the stale snapshot block the targeted deploy

- Snapshot (`P1_SNAPSHOT_STALE`): no. It is raised by `functions-equipment-identity` (`npm run build` -> `check:p0-snapshot`), which is in the `equipment-identity` predeploy only. The `default` predeploy does not call it.
- Windows `%RESOURCE_DIR%` spawn error: not reproduced (no deploy was run). The CLI runs each predeploy command through `cross-env-shell` and passes `RESOURCE_DIR` in the environment (`lifecycleHooks.js`), and the `default` codebase predeploy, which uses the same `"$RESOURCE_DIR"` syntax, passed on 2026-10-22 (manifest section 6). The error was seen only with both codebases selected. UNKNOWN root cause; it is not on the targeted path.
- What WOULD block the targeted deploy (read from `functions/src/release_guard.ts`, `functions/scripts/run_release_guard.mjs`, `scripts/deploy/guarded_deploy.mjs`):
  1. Branch: only `master`, `phase1/*` or `phase2/*` are deploy lines; a feature branch is `deploy-line-unknown`.
  2. Provenance: `HEAD` must be an ancestor of `refs/remotes/origin/phase1/main`. FACT: that ref is `03ea66e1`; master `4a5e6b6d` is 28 commits ahead, so `phase1-provenance-unverified` blocks. The same manual step as on 2026-10-22 (fast-forward the ref, rollback: move it back) is needed.
  3. Other guard checks (AI gateway set completeness, kill switch secret and so on) were not run here. On 2026-10-22 the full AI set check blocked a deploy of two functions until consent for a bypass; whether it blocks one unrelated function is UNKNOWN until the guard is run (it only reads, but needs `functions/node_modules`, which this worktree does not have).
  4. `npm test` inside the predeploy runs the whole unit suite; a failure there blocks. Not run.

## 3. equipment-identity cannot be rebuilt: `P1_SNAPSHOT_STALE`

- FACT: the check is `functions-equipment-identity/scripts/sync_p0_type_snapshot.js --check`, run by `npm run build` and `pretest`. It compares, byte for byte, `core/equipment_identity/p0/functional_type_snapshot_v1.json` with `functions-equipment-identity/src/generated/functional_type_snapshot_v1.json`. Two sibling checks fail the same way: `P1_GENERATED_STALE` (`src/generated/source_registry.json`) and `P0_G0_READINESS_STALE` (`p0_g0_app_check_platform_readiness.json`). I ran the three `--check` modes (read only); all three fail in this worktree.
- FACT: the content is NOT stale. `git show HEAD:<source>` and `git show HEAD:<generated>` are byte-identical blobs. The difference is line endings in the working tree: `git ls-files --eol` shows the source as `w/lf attr/text eol=lf` (rule `core/equipment_identity/p0/*.json text eol=lf` in `.gitattributes`) and the generated copies as `w/crlf attr/` (no rule, `core.autocrlf=true` on this Windows machine). Sizes: 16333 bytes (LF) against 16824 bytes (CRLF), the difference equals the line count. All 33 files under `functions-equipment-identity/src/generated` are `i/lf w/crlf`.
- Root cause: `.gitattributes` pins `eol=lf` for the source but not for its generated copies, and the check compares bytes. On a Linux runner it passes; on this machine it cannot.
- Smallest fix (not run): `node functions-equipment-identity/scripts/sync_p0_type_snapshot.js && node functions-equipment-identity/scripts/sync_p1_generated.js && node functions-equipment-identity/scripts/sync_p0_app_check_readiness.js` from the repository root (or `npm run sync:p0-snapshot`, `sync:p1-generated`, `sync:p0-app-check-readiness` in `functions-equipment-identity`). It rewrites the working-tree copies with the source bytes (LF); git would show no change because the index blobs are already equal (verify with `git status` afterwards). The durable fix is one `.gitattributes` line, `functions-equipment-identity/src/generated/** text eol=lf`, plus a renormalised checkout; the same line fixes the rebuild for every machine.
- This is independent of V0: the two equipment-identity functions stay on their current source until someone rebuilds that codebase; the V0 deploy does not need it.

## 4. Scheduler 403 on `runProductionCanary` and `runEnforcementStateCheck`

Evidence (all read-only):
- Job `firebase-schedule-runProductionCanary-europe-west1`: ENABLED, every 30 minutes, POST to `https://europe-west1-fitness-app-korostelev.cloudfunctions.net/runProductionCanary`, OIDC token with service account `988522745882-compute@developer.gserviceaccount.com`, status code 7, last attempt 2026-10-23T13:11Z. Cloud Logging `AttemptFinished`: `PERMISSION_DENIED`, original HTTP response 403; Cloud Run request log shows 403 at 13:11:01Z and 12:41:00Z.
- Job `firebase-schedule-runEnforcementStateCheck-europe-west1`: same shape, every 6 hours, same Compute service account, status code 7.
- Cloud Run IAM of service `runproductioncanary`: `roles/run.invoker` for `serviceAccount:fn-canary@fitness-app-korostelev.iam.gserviceaccount.com` only. Service `runenforcementstatecheck`: `roles/run.invoker` for `fn-enforcement@...` only. The services run as `fn-canary` / `fn-enforcement` (source: `serviceAccount: RUNTIME_SA.canary` in `canary_schedule.ts`).
- Comparison: the healthy jobs have the invoker identity equal to the job identity: `reconcileAccountDeletions` (job SA `fn-account-delete`, invoker `fn-account-delete`), `sweepLateBodyScanUploads` and `purgeExpiredBodyScanPhotos` (job SA `fn-bodyscan`), and the activity jobs (Compute account on both sides).

Most likely cause (FACT for the mismatch, INFERENCE for how it arose): the two jobs were created when these functions ran as the default Compute account; the functions were later moved to dedicated accounts (`RUNTIME_SA`), which moved the invoker binding, but the scheduler jobs were not updated. The 2026-10-22 runtime migration used `gcloud functions deploy`, which does not rewrite the scheduler job, and the `03ea66e1` deploy via the firebase CLI did not refresh these two jobs either (job identity is still the Compute account).

Fix, either one (not applied):
- Option 1, align the job with the function (preferred, least privilege):
  `gcloud scheduler jobs update http firebase-schedule-runProductionCanary-europe-west1 --location=europe-west1 --project=fitness-app-korostelev --oidc-service-account-email=fn-canary@fitness-app-korostelev.iam.gserviceaccount.com --oidc-token-audience=https://europe-west1-fitness-app-korostelev.cloudfunctions.net/runProductionCanary`
  and the same for `runEnforcementStateCheck` with `fn-enforcement@...`. The caller (the person or service running this command) needs `roles/iam.serviceAccountUser` on that account, and Cloud Scheduler's service agent needs token creation on it; the existing healthy jobs show the pattern works.
- Option 2, add the binding the jobs currently lack:
  `gcloud run services add-iam-policy-binding runproductioncanary --region=europe-west1 --project=fitness-app-korostelev --member=serviceAccount:988522745882-compute@developer.gserviceaccount.com --role=roles/run.invoker`
  and the same on `runenforcementstatecheck`. Broader (the default Compute account becomes an invoker of two more services).
- Verification after either: `gcloud scheduler jobs run <job>` is a write-like trigger (it calls the function); instead wait for the next scheduled attempt and read `gcloud scheduler jobs describe` status code (0 or absent) plus the Cloud Run request log for status 200.
- Independent of V0. It is also a conscious-acceptance item from PI-M10: the canary and the enforcement check have not run successfully since at least 2026-10-22, so no health signal exists for those two functions.

## 5. Rollback drill proposal for V0 (dev project only)

Goal: one executed drill that proves each undo path before the flag is ever turned on. Times are estimates, not measurements.

| Step | Action | Undo | Estimated time | Checks after the step |
|---|---|---|---|---|
| 0 | Record the baseline: released ruleset id (`eefbc179-...`), function list (43 names, update times), scheduler states, `origin/phase1/main` = `03ea66e1`. | none | 5 min | Saved listing equals section 2.1. |
| 1 | Rules: release released-source + five carve-outs (section 1.4). | Re-point release `cloud.firestore` to ruleset `eefbc179-7f92-4199-a163-828a7424d503` (Rules REST `PATCH` of the release, or deploy the old file). Create nothing else. | release about 1 min; rollback about 1 min | `releases` shows the new ruleset id; emulator rules tests for the five names pass on the same file before release; an existing-client smoke (profile read, a `weight_entries` write by a test user) is unchanged; after rollback the release points to `eefbc179` again. |
| 2 | Functions: `firebase deploy --only functions:default:submitWorkoutCommands` through `scripts/deploy/guarded_deploy.mjs` (flag unset). | `gcloud functions delete submitWorkoutCommands --gen2 --region=europe-west1` or `firebase functions:delete submitWorkoutCommands --codebase default --region europe-west1` (operator-only: deletion of a deployed resource). Nothing else was deployed, so nothing else needs undoing. | deploy 3 to 6 min; delete 1 to 2 min | function list: 44 names, new one `ACTIVE`, `nodejs22`, update times of the other 43 unchanged; no new `ERROR` entries in Cloud Logging for the other services; a signed-in test call returns `failed-precondition` / `feature-disabled` and writes no document (check `users/{uid}/workout_*` stay absent). After delete: list back to 43. |
| 3 | Flag path (only if the operator wants the drill to cover it): set `WORKOUT_COMMANDS_ENABLED=true` on the dev service, make one test call, remove the variable. | Remove the variable (`gcloud run services update submitworkoutcommands --remove-env-vars=WORKOUT_COMMANDS_ENABLED`) or redeploy without it. A firebase CLI redeploy replaces the environment with the `.env` content, so it also resets the flag. | 1 to 2 min per change | Needs D-4 first (service account role); else the call fails with a permission error, which itself is a drill finding. After removal the call answers `feature-disabled` again. |
| 4 | Provenance ref: if `origin/phase1/main` was moved for the guard, move it back to `03ea66e1` at the end (old value must be passed to `update-ref`). | Move the ref forward again. | 1 min | `git rev-parse origin/phase1/main`. |

Order of undo is the reverse of the deploy: flag, function, rules. The function alone (flag off) writes nothing, so rules and function can be rolled back independently.

## 6. Go/no-go list for deploying V0 to the dev project

Each item names the decision first and the code second; the options carry their consequences.

| Id | Decision to take | Options and consequence | Recommendation |
|---|---|---|---|
| D-1 | Which Firestore rules to release for V0 | (a) the released ruleset plus only the five V0 carve-outs: existing clients are unaffected, but a hand-built rules file must be reviewed and kept until a later full release; (b) master's full rules file: one clean file, but about 700 lines of older changes reach every existing client at once (validators on food, weight, body scan, activity and profile writes; client debug-session create denied) | (a) for V0, plan (b) as its own release after the shipped build is confirmed |
| D-2 | Move the provenance ref `origin/phase1/main` from `03ea66e1` to master `4a5e6b6d` so the release guard can pass | Moving it unblocks the guarded deploy and is reversible (move it back); not moving it keeps the guard closed and the only other path is a consented bypass like on 2026-10-22 | move it, with the old value kept for rollback |
| D-3 | Deploy the function alone, or together with `exportAccountData` | Alone: the deployed data export lacks V0 data, acceptable while the flag is off; with the export: one more function changes (a code update to the account data export, which is a privacy surface) | alone now; redeploy the export before the flag is enabled for any real user |
| D-4 | Service account for `submitWorkoutCommands` before the flag is enabled | (a) grant `roles/datastore.user` to the default Compute account: fixes this function but also widens the eleven functions that already use it; (b) change `RARE`-based V0 callable to a dedicated account that already has the role (for example `fn-data`) or a new one: a code change plus review, least privilege; (c) accept that the flag stays off and the function is only a shell for now | (b) before enabling; deploy with flag off is fine without it |
| D-5 | Whether to turn the flag on in dev for the drill (step 3) | Yes: proves the real path and the rollback of the flag, needs D-4 and the rules; no: the drill covers rules and function only and the flag stays untested | no until D-4 is done |
| D-6 | The two scheduler 403s | Fix now (section 4, option 1), or accept with a written reason: until fixed there is no canary or enforcement-state signal for the project | fix with option 1, separate from V0 |
| D-7 | The line-ending `P1_SNAPSHOT_STALE` fix | Run the three sync scripts locally, or add the `.gitattributes` line: needed only when someone rebuilds the equipment-identity codebase, not for V0 | add the `.gitattributes` line in the next docs or infra PR |
| D-8 | Shipped app build | Name the version in users' hands: it decides whether the full rules release (D-1b) is safe | needed before D-1b |

Go conditions for the V0 deploy with the flag OFF: D-1 (a) chosen and its file reviewed, D-2 done, predeploy `build` and `test` green on the exact head, baseline from step 0 saved, operator present for the delete step of the drill. No-go if any of those is missing. Enabling the flag is a separate decision (D-4, D-5) and is not part of this go.

## Not verified

- The release guard itself was not run (needs `functions/node_modules`); its AI-set checks may block a single-function deploy.
- `npm test` of `functions` and the rules tests were not run; I ran only the three read-only `--check` scripts of the equipment-identity codebase.
- The shipped app build, and the behaviour of the eleven Compute-account functions on Firestore, were not checked.
- Rollback times are estimates.
- `core/PRODUCTION_MANIFEST.md` remains stale; this document does not replace it.
