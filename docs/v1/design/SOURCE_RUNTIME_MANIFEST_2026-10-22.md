# Source and runtime manifest (2026-10-22)

Closes review finding M-07 (current source and runtime baseline unverified). Every value below was read from a live API or from git on 2026-10-22; nothing is copied from older documents.

## Source
| Item | Value |
|---|---|
| Repository | xLZDx/Fitness-App, `origin/master` |
| Commit | `3d52738cf6c42c6f5b2533d5f807a23fe80f43d9` (2026-10-21 19:02 -04:00) |
| Tree | `108b4cef88c43fb556c25ce6cad38fc0fb36a02e` |
| `firebase.json` runtimes | both codebases (`default`, `equipment-identity`) pinned to `nodejs22` |
| `functions/package.json` engines | `22` |

The package's `18_CURRENT_INTEGRATION_BASELINE.md` (local integration candidate `13351959`, 2026-10-20) is a dated snapshot of an older state, not the current head.

## Deployed Cloud Functions (project `fitness-app-korostelev`, region `europe-west1`, 2nd gen)
- 23 functions, all `ACTIVE`, all `nodejs22` after the migration of 2026-10-22 (was `nodejs20`; Node.js 20 decommission date is 2026-10-30).
- 21 belong to the `default` codebase, 2 (`equipmentIdentityRecordTelemetry`, `equipmentIdentityResolveFromText`) to `equipment-identity`.
- Deployed code is NOT the code on `master`. The deployed functions run a mix of older source trees (functions last deployed 2026-08-28, 2026-08-29, 2026-09-16 and 2026-10-14; the Oct 14 tree differs from the Aug 28 tree in 6 to 15 compiled files). `master` exports 20 further functions that are not deployed at all: `analyzeMealPhoto`, `commitActivityStream`, `createActivityStreamUpload`, `createBodyScan`, `deleteActivity`, `deleteAllActivityStreams`, `deleteBodyScan`, `estimateBodyScan`, `getActivityStreamDownloadUrls`, `lookupBarcode`, `manageBodyScanData`, `parseNutritionLabel`, `purgeExpiredActivityStreams`, `purgeExpiredBodyScanPhotos`, `reconcileActivityStreams`, `searchFoods`, `sendDebugTelemetry`, `setActivityCloudSettings`, `sweepLateActivityStreams`, `sweepLateBodyScanUploads`.
- Consequence: a plain `firebase deploy --only functions` from `master` would also release those 20 functions and update the others to newer code. The runtime migration therefore did NOT use it.

## How the runtime was migrated (2026-10-22, local time 10:2x to 11:0x)
- Each function was redeployed from its OWN currently deployed source archive (downloaded by its recorded storage generation), changing only `engines.node` from `20` to `22` in `package.json` and passing `--runtime nodejs22` (`gcloud functions deploy ... --gen2`). No `master` code was deployed.
- Per function the before and after configuration was compared (memory, timeout, environment, secrets, service account, instance limits, triggers, Firebase labels): the only difference for the 21 `default` functions is the runtime. For the 2 `equipment-identity` functions `gcloud` also introduced a max-instances value of 20 where none was set; it was restored to the Cloud Run default of 100 with `gcloud run services update --max-instances=100`.
- Incident, corrected: the first deploy attempt for `equipmentIdentityRecordTelemetry` failed in the build ("lib/index.js does not exist") because `.gcloudignore` from the archive excluded `lib/`. It had already overwritten the live object `function-source.zip` in the sources bucket with a patched archive. The service kept serving revision `-00001` (nodejs20). The original object generation `1789564789713924` still existed (bucket versioning), and was copied back over the live object before the successful deploy. Later functions were downloaded by explicit generation and the script drops the archive's ignore files.
- Result checks: `gcloud functions list` shows 23 of 23 `nodejs22` and `ACTIVE`; Cloud Logging shows no `ERROR` entries for any Cloud Run revision in the 70 minutes covering the whole migration.
- Rollback until 2026-10-30: redeploy the same archives with `--runtime nodejs20` (archives are kept by generation in `gs://gcf-v2-sources-988522745882-europe-west1/<function>/function-source.zip`; the migration working copies are in `D:\tmp\deploy_node22\work\<function>\`).

## Findings from the check (not caused by the migration)
- `runProductionCanary` (Cloud Scheduler job `firebase-schedule-runProductionCanary-europe-west1`, every 30 minutes) has been failing with `PERMISSION_DENIED` (HTTP 403) at least since 2026-10-22 05:11 UTC, before the migration. `runEnforcementStateCheck` shows status code 7 as well. Likely cause: the scheduler's service account lacks the invoker role on the Cloud Run service; not investigated or changed. Fixing the IAM binding is a separate production change.
- The production manifest in `core/PRODUCTION_MANIFEST.md` (14 functions, 2026-08-12) is stale.

## Not verified
- Behavior of each function on Node 22 under real traffic beyond the absence of error logs and one successful scheduled run (`reconcileAccountDeletions`); callable functions need App Check and authentication and were not invoked.
- The Linux emulator image for rules and e2e runs still needs Node 22 (operator action from the runtime change record).
- The actual source commit of each deployed archive; only compiled output was compared.

## 6. Update after the master deployment (2026-10-22, later the same day)

The statements above that the deployed code is not the code on `master` describe the state at the time of the runtime migration. Later on 2026-10-22 the dev project was brought to master `03ea66e1c8fa5190104a262bc4db2858d1c479f9`. Facts, each read from a tool result in that session:
- A new runtime service account `fn-bodyscan@fitness-app-korostelev.iam.gserviceaccount.com` was created with `roles/iam.serviceAccountTokenCreator` (on itself), `roles/datastore.user` (project) and `roles/secretmanager.secretAccessor` on `ai-gateway-kill-switch`. No bucket, flag or new secret was created.
- The release guard blocked a deploy of the two functions `analyzeMealPhoto` and `parseNutritionLabel` because it requires the full AI set to exist already. With explicit operator consent for that one named action they were deployed once through the firebase CLI with a temporary config kept outside the repository (guard hooks removed, build step kept). Nothing else bypassed the guard.
- The four log-based metrics `ai_gateway_calls`, `ai_gateway_latency_ms`, `ai_gateway_quota_exhaustions` and `ai_gateway_total_tokens_per_call` were updated in place to the source definitions (six operations instead of four). The previous definitions are saved in `D:\tmp\deploy_node22\metrics_before\` (outside git).
- `origin/phase1/main` was fast-forwarded from `0eee9ca2` to `03ea66e1` so that the guard's provenance check passes (rollback: move the ref back to `0eee9ca2`).
- `node scripts/deploy/guarded_deploy.mjs --project fitness-app-korostelev --only functions:default` completed with the guard verdict PASS. The same command for both codebases failed in the equipment-identity predeploy (`P1_SNAPSHOT_STALE` and a Windows `%RESOURCE_DIR%` spawn error).
- Result: 43 functions, all `ACTIVE` and `nodejs22`; 41 were created or updated around 15:14 UTC; `equipmentIdentityRecordTelemetry` and `equipmentIdentityResolveFromText` still run the older source and keep Cloud Run `maxScale = 100`.
- Not re-checked after the deploy: the Cloud Scheduler 403 for the canary and enforcement-state jobs, behaviour of any new function (all feature flags are off by default), and whether the deployed configuration of each function matches its source. `core/PRODUCTION_MANIFEST.md` is still stale.
