# Body Scan private bucket: operator runbook

Status: NOT_RUN. Nothing in this runbook has been executed; the default build does not need it. The cloud photo path (`BODY_SCAN_CLOUD` on the client, `BODY_SCAN_BUCKET` on the server) stays off until every step below is done and the canary passes. Design: `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` sections 5.10, 6.3, 7.6 (D-16, D-60, D-63).

## 0. Preconditions

- The post-blur face check adapter (D-69), a real photo provider and the re-reviewed privacy text exist (sprint plan SD-15). Without them do not enable the flag, even if the bucket is created.
- `fn-bodyscan` is a NEW runtime identity (`RUNTIME_SA.bodyScan` in `functions/src/scaling.ts`). It must exist before any function that uses it is deployed.

## 1. Create the bucket

Name `<project>-bodyscan-private`, same convention as `<project>-videos-private`.

- Location: EU. Storage class: Standard.
- Uniform bucket-level access: ON.
- Public access prevention: ENFORCED. No `allUsers` / `allAuthenticatedUsers` binding, ever.
- Lifecycle rule: delete objects older than 400 days (absolute backstop only; the user-controlled retention is enforced by the daily purge job).

Objects are only `users/{uid}/scans/{scanId}/{front|side|back}.jpg`.

## 2. Create the runtime identity and grant it

Create the service account `fn-bodyscan@<project>.iam.gserviceaccount.com`, then:

| Principal | Role | Scope |
|---|---|---|
| `fn-bodyscan` | `roles/storage.objectAdmin` | this bucket only |
| `fn-bodyscan` | `roles/iam.serviceAccountTokenCreator` | on itself (V4 signed URLs; same one-time step as `runbooks/video_bundle_import.md`) |
| `fn-bodyscan` | `roles/datastore.user` | project (Firestore access for the scan documents, quota counters and the purge state) |
| `fn-bodyscan` | `roles/secretmanager.secretAccessor` | secret `ai-gateway-kill-switch` only (every body-scan callable runs `enforceAiGatewayEnabled`; without it they fail closed with `unavailable`) |
| `fn-account-delete` | `roles/storage.objectAdmin` | this bucket only |

The scheduled purge `purgeExpiredBodyScanPhotos` runs as `fn-bodyscan` (the "purge service account"), so the rows above already cover it; it needs no separate identity or grant. Do not give `fn-bodyscan` any write-capable Secret Manager role.

`fn-account-delete` is the identity of `deleteAccount` and `reconcileAccountDeletions`; both run `sweepAccountData`, which calls `deleteFiles` on the bucket. Without this grant account deletion fails with a 403 once the bucket is configured (the durable reconciler then retries forever). The shared `fn-data` identity gets NO access to this bucket.

## 3. Configure the functions

Set in the codebase-wide `functions/.env.<project>` (it reaches every function in the default codebase, including `sweepAccountData`):

```
BODY_SCAN_BUCKET=<project>-bodyscan-private
BODY_SCAN_PROVIDER=<registered estimator id, e.g. licensed-api>
```

Both are read through `functions/src/body_scan/flags.ts` only. With `BODY_SCAN_BUCKET` unset every body-scan callable answers `failed-precondition: feature-disabled` before charging any quota, and the storage step of `sweepAccountData` is a logged no-op. `BODY_SCAN_ACCEPT_UPLOADS` (default on when the bucket is set; `false`/`0`/`off`/`no` turns it off) gates only `createBodyScan` and `estimateBodyScan`; see section 7.

## 4. Canary (go-live BLOCKER)

As BOTH `fn-bodyscan` and `fn-account-delete` (impersonate each in turn):

1. Write a test object under `users/canary-<random>/scans/canary/front.jpg`.
2. `deleteFiles` with prefix `users/canary-<random>/`.
3. Confirm the object is gone.

A failed canary means "configured but IAM-denied". That is a go-live BLOCKER for `BODY_SCAN_CLOUD` (not for the default build, where the bucket is unset): account deletion would fail for every user.

After the canary passes, record it in `core/state/g4_release_evidence.json` as `"bodyScanBucketCanary": { "status": "closed", "date": "<YYYY-MM-DD>", "by": "<operator>" }` and commit it.

When `BODY_SCAN_BUCKET` is set (process env or `functions/.env.<project>`), `functions/src/release_guard.ts` adds a flag-gated check "Body scan private bucket exists, is private, has the required IAM, and the canary is acknowledged". It blocks the release (FAILED/UNAVAILABLE) unless: the bucket describes OK, public access prevention is `enforced`, uniform access is on, no `allUsers`/`allAuthenticatedUsers` binding exists, `fn-bodyscan` and `fn-account-delete` both hold `roles/storage.objectAdmin` on it, and `bodyScanBucketCanary.status` is `"closed"`. With no bucket configured the guard emits no extra check. The body-scan callables run as `fn-bodyscan`, outside the 4-callable AI guard set (D-63): the functions-inventory check only counts functions running as `fn-ai-runtime`, so they never appear as "extra".

## 5. Default-bucket rules (deny-all) check

`storage.rules` (deny-all) is deployed for the DEFAULT Firebase Storage bucket only; this private bucket is not governed by Firebase rules and is reachable only through V4 signed URLs minted by the callables and through the Admin SDK (which bypasses rules). Deploying `storage.rules` overwrites whatever is currently deployed for the default bucket (the repository had no `storage` block before, so the deployed rules are unknown).

BEFORE deploying `storage.rules`, verify that no public asset depends on the currently deployed default-bucket rules:

1. Read the deployed rules (Firebase console, Storage, Rules) and note any `allow read: if true` or auth-only read paths.
2. List the default bucket's objects (`gcloud storage ls gs://<project>.firebasestorage.app/**` or the `appspot.com` name) and check whether any are referenced by the app, `public/` hosting pages, emails or published links via `firebasestorage.googleapis.com` URLs.
3. Grep the repository for `firebasestorage.googleapis.com` and `firebase_storage` (the mobile app is expected not to use the plugin).
4. If anything public depends on it, move it (e.g. to Hosting or the signed-URL path) or adjust `storage.rules` first. Only then `firebase deploy --only storage`.

## 6. Go-live blockers for `BODY_SCAN_CLOUD` (SD-15)

All three are required before the client flag is turned on; none blocks the default build:

1. The post-blur face check adapter (D-69) exists and is wired.
2. The bucket IAM canary (section 4) passed for both identities and is recorded in the release evidence.
3. The re-reviewed privacy text is published (plus a real photo provider configured via `BODY_SCAN_PROVIDER`).

## 7. Rollback

NEVER unset or change `BODY_SCAN_BUCKET` while objects exist in the bucket: every erase path (`deleteBodyScan`, `manageBodyScanData`, the daily purge, the account-delete storage sweep) finds the bucket through that variable alone, so unsetting it strands stored photos with no way to delete them.

To stop intake, set `BODY_SCAN_ACCEPT_UPLOADS=false` in `functions/.env.<project>` and redeploy. `createBodyScan` and `estimateBodyScan` then answer `failed-precondition: feature-disabled`; deletion, export, the purge and account deletion keep working, and they do not depend on the AI kill switch either. Keep the client `BODY_SCAN_CLOUD` flag off in the next build. Stored objects are then removed by the daily purge, by `deleteBodyScan` / `manageBodyScanData`, by account deletion, or by the 400-day lifecycle rule.

Only after the bucket is verifiably empty (no objects under `users/`) may `BODY_SCAN_BUCKET` be unset.

## 8. Deploying storage rules

`firebase.json` contains a `storage` block, so a plain `firebase deploy` also deploys `storage.rules`. Deploy functions with `--only functions` and the storage rules separately with `--only storage`, after the check in section 5.
