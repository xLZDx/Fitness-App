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
| `fn-account-delete` | `roles/storage.objectAdmin` | this bucket only |

`fn-account-delete` is the identity of `deleteAccount` and `reconcileAccountDeletions`; both run `sweepAccountData`, which calls `deleteFiles` on the bucket. Without this grant account deletion fails with a 403 once the bucket is configured (the durable reconciler then retries forever). The shared `fn-data` identity gets NO access to this bucket.

## 3. Configure the functions

Set in the codebase-wide `functions/.env.<project>` (it reaches every function in the default codebase, including `sweepAccountData`):

```
BODY_SCAN_BUCKET=<project>-bodyscan-private
BODY_SCAN_PROVIDER=<registered estimator id, e.g. licensed-api>
```

Both are read through `functions/src/body_scan/flags.ts` only. With `BODY_SCAN_BUCKET` unset the body-scan callables answer `failed-precondition: feature-disabled` before charging any quota, and the storage step of `sweepAccountData` is a logged no-op.

## 4. Canary (go-live BLOCKER)

As BOTH `fn-bodyscan` and `fn-account-delete` (impersonate each in turn):

1. Write a test object under `users/canary-<random>/scans/canary/front.jpg`.
2. `deleteFiles` with prefix `users/canary-<random>/`.
3. Confirm the object is gone.

A failed canary means "configured but IAM-denied". That is a go-live BLOCKER for `BODY_SCAN_CLOUD` (not for the default build, where the bucket is unset): account deletion would fail for every user.

When `BODY_SCAN_BUCKET` is set, the release guard gains a flag-gated check (added with the callables in C12) that the bucket exists, public access prevention is enforced and both bindings above are present.

## 5. Default-bucket rules

`storage.rules` (deny-all) is deployed for the DEFAULT Firebase Storage bucket only; this private bucket is not governed by Firebase rules and is reachable only through V4 signed URLs minted by the callables and through the Admin SDK. Deploying `storage.rules` overwrites whatever is currently deployed for the default bucket (the repository had no `storage` block before, so the deployed rules are unknown): verify that nothing public depends on the default bucket first.

## 6. Rollback

Unset `BODY_SCAN_BUCKET` and redeploy: the callables refuse, the client flag stays off. Objects already stored are removed by the daily purge, by `deleteBodyScan` / `manageBodyScanData`, by account deletion, or by the 400-day lifecycle rule.
