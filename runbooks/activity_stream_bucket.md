# Activity stream private bucket: operator runbook

Status: NOT_RUN. Nothing in this runbook has been executed; the default build does not need it. The cloud stream path (server setting `ACTIVITY_STREAM_BUCKET`, client flag `ACTIVITY_CLOUD_STREAMS`) stays off until every step below is done. Design: `docs/phase2/s02/S02_DESIGN.md` sections 5, 5.1, 5.1a, 5.2, 5.3, 6, 6.1, 6.2, 6.3, 8.1 (D-16, GPS-PRIV-064, GPS-PRIV-078). Completed by story S02-08.

## 1. Create the bucket

Name `<project>-activity-streams-private`. It MUST be a different bucket from `<project>-bodyscan-private` (GPS-PRIV-064). The server treats a value equal to `BODY_SCAN_BUCKET` as "not configured", so the feature stays off if the two are ever mixed up.

- Location: EU. Storage class: Standard.
- Uniform bucket-level access: ON.
- Public access prevention: ENFORCED. No `allUsers` / `allAuthenticatedUsers` binding, ever.
- Soft delete and object versioning (GPS-PRIV-078): set the soft-delete retention to the shortest window the operator accepts (`gcloud storage buckets update gs://<bucket> --soft-delete-duration=<seconds>`, 0 disables) and keep object versioning disabled. OPEN operator decision: the window. While soft delete is on, a deleted or expired GPS object stays recoverable by the project owner for that whole window, so the privacy text must state the window (see `docs/phase2/s02/S02_PRIVACY_TEXT_REQUEST.md`). Record the chosen value in the release evidence.
- Lifecycle rule on the `quarantine/` prefix only: delete objects older than 1 day (backstop for abandoned uploads, design 5.2). NEVER add an age rule on `streams/`: retention is a per-user setting derived at purge time (design 5.3), and an age rule would silently break "never".

Objects are only `quarantine/{uid}/{activityId}/{uploadId}` and `streams/{uid}/{activityId}/{uploadId}.json.gz`.

## 2. Runtime identity and IAM

FACT (code, `functions/src/activity_streams/*.ts`): none of the activity callables or scheduled jobs sets a dedicated `serviceAccount`; they run with the profile defaults of `functions/src/scaling.ts` (the project's default runtime service account). `deleteAccount` and `reconcileAccountDeletions` run as `fn-account-delete` (`RUNTIME_SA.accountDelete`). Grants, on THIS bucket only:

| Identity | Role | Scope |
|---|---|---|
| the runtime service account of the activity functions (default runtime identity unless the operator moves them to a dedicated one) | `roles/storage.objectAdmin` | this bucket only |
| the same identity | `roles/iam.serviceAccountTokenCreator` | on itself (V4 signed URLs for upload PUT and download GET; same one-time step as `runbooks/video_bundle_import.md`) |
| `fn-account-delete` | `roles/storage.objectAdmin` | this bucket only (`sweepActivityStreamObjects` runs inside `sweepAccountData`; without it account deletion fails with a 403 once the bucket is configured and the reconciler retries until the cap) |
| `fn-data` and every other identity | none | no access to this bucket |

Because the default runtime identity is shared by other functions, granting it `objectAdmin` on this bucket widens what those functions could reach. OPEN operator decision: create a dedicated `fn-activity` identity (then the activity functions must declare it in code, a small follow-up change) or accept the default identity. Until decided, the default-identity route is the one the code supports.

Canary after granting (go-live BLOCKER for `ACTIVITY_CLOUD_STREAMS`, not for the default build): as BOTH identities, write, read and delete a throw-away object under `quarantine/canary/` and confirm a listing of the bucket root is allowed only for those two. A failed canary means "configured but IAM-denied", which would make account deletion fail for every user.

## 3. Configure the functions

Set in the codebase-wide `functions/.env.<project>`:

```
ACTIVITY_STREAM_BUCKET=<project>-activity-streams-private
```

Read through `functions/src/activity_streams/flags.ts` only, per call. Unset (or invalid, or equal to `BODY_SCAN_BUCKET`) means the feature is off and the sweep is a logged no-op. Granting cloud-stream consent answers `feature-disabled` while it is unset; retention changes, withdrawal and deletion keep working.

## 4. Storage rules

`storage.rules` stays the single deny-all for the DEFAULT bucket; this private bucket is not governed by Firebase rules and is reachable only through V4 signed URLs and the Admin SDK. Any `allow` for `streams/` or `quarantine/` in `storage.rules` is a defect.

## 5. Tombstone TTL policy (operator step, RELEASE PREREQUISITE)

The repository does not create Firestore TTL policies for this feature. Without this policy the delete markers in `users/{uid}/activity_tombstones` grow without bound. Create it in the console (Firestore, TTL) or with:

```
gcloud firestore fields ttls update expireAt --collection-group=activity_tombstones --enable-ttl --project=<project>
```

The field is `expireAt`, written by `deleteActivity` as deletion time plus 400 days (design 6.2; the 400 days are a proposal, OPEN). Owner: the operator until a person is named. Verify with `gcloud firestore fields ttls list`. TTL deletion is asynchronous (typically within 24 hours of expiry); a marker living a little longer is harmless.

Also required before release and also external: the two collection-group indexes of design 4 are in `firestore.indexes.json` and are deployed with it (`activity_streams`: `state` + `expiresAt`; `activity_settings`: `recomputePending`). A missing index shows up as `FAILED_PRECONDITION` on the purge or recompute query (signal in section 8).

## 6. Deploy order

1. Deploy the functions (callables, `purgeExpiredActivityStreams`, `reconcileActivityStreams`, `sweepLateActivityStreams`, `sendDebugTelemetry`, the `deleteAccount` changes) and `firestore.indexes.json`. With `ACTIVITY_STREAM_BUCKET` unset they are inert for streams.
2. Telemetry (design 8.1), in this order, each step separately revertible: (a) the `sendDebugTelemetry` callable; (b) the client build with the new sink (DEBUG builds only); (c) ONLY THEN the `debug_sessions` rule `create: false`. Doing (c) first makes old debug builds get permission-denied (the sink swallows it, but their telemetry is lost). Reverting (c) returns to Phase 1 behaviour and is not part of the permanent rules floor.
3. The activity rules (`activities`, `activity_streams`, `activity_settings`, `activity_tombstones` exclusions and blocks) are a PERMANENT FLOOR: deploy them with the first release that contains the summary sync and never revert them (reverting reopens client writes through the wildcard, design 12.1). Roll back by FLAG only.
4. Summary sync and the journal ship first with `ACTIVITY_CLOUD_STREAMS` OFF (no geometry in the cloud).
5. Create the bucket (section 1), IAM and canary (section 2), TTL policy (section 5), alerts (section 8).
6. Privacy text approved and published (`docs/phase2/s02/S02_PRIVACY_TEXT_REQUEST.md`), then set `ACTIVITY_STREAM_BUCKET` and turn `ACTIVITY_CLOUD_STREAMS` on. In that order: server setting, then client flag.

## 7. Fence and late sweep semantics (what the operator will see)

- `deleteAccount` writes the top-level server-only document `activity_account_state/{uid}` after the Stripe cancel and token revocation and immediately before the first sweep (a failed cancel never leaves a live account fenced). From then on all seven activity callables refuse and the summary rules refuse client writes; the document survives `recursiveDelete(users/{uid})`. `authDeletedAt` is recorded after the Auth deletion (Step 3b, non-fatal).
- `sweepLateActivityStreams` (every 5 minutes) sweeps `streams/<uid>/` and `quarantine/<uid>/`, does a final recursive delete of the user's activity collections, sets `lateSweepDone`, and removes the fence document at `max(lateSweepDone + 1 h, authDeletedAt + 70 min)`. It never removes the fence while the Auth user still exists (stuck state is reported).
- A fence document that stays more than one hour past `lateSweepAt` with `lateSweepDone` unset is a stuck job: check the `activity_late_sweep_event` log entries for the bare `lastErrorCode`, fix the cause (usually bucket IAM) and the next run completes it; every cleanup is idempotent.
- Do not delete `activity_account_state` documents by hand: until they are gone the rules and callables refuse writes for that uid, and removing one early lets a still-valid token replay a write.

## 8. Signals and alerts (design 6.3)

Every scheduled job writes ONE structured Cloud Logging entry per run (including a zero-count run, so a stopped job is visible as a missing sample): counts, ages and bare codes only, never a uid, id, path or coordinate. Event names emitted by the code: `activity_upload_event`, `activity_commit_event`, `activity_delete_event`, `activity_delete_all_event`, `activity_download_event`, `activity_settings_event`, `activity_purge_event`, `activity_reconcile_event`, `activity_late_sweep_event`, `debug_telemetry_event`, `debug_telemetry_dropped`. Define a log-based metric per row below on `jsonPayload.message` (or `jsonPayload.event`) equal to the event name and the stated field, and an alert policy with the stated condition. The exact field names are in the constants and payloads of the files named in the design; if a name here and the code diverge, the code wins and this table is corrected. Owner role for every row: backend on-call (security reviewer for validator rejections); the operator holds both roles until a person is named.

| Signal | Event | Alert condition |
|---|---|---|
| Oldest `pending` row age | `activity_reconcile_event` | oldest pending > 1 h |
| Quarantine object count and oldest age | `activity_reconcile_event` | oldest > 1 day (lifecycle backstop failed) |
| Sweep / late sweep failures by bare code | `activity_late_sweep_event`, `activity_reconcile_event`, account deletion events | any failure on 2 consecutive runs; any `accountDeletionRetries` row older than 1 day |
| Purge failures, capped rows, oldest overdue age | `activity_purge_event` | overdue > 2 days; any capped row |
| Recompute backlog count and age | `activity_purge_event` | age > 1 h |
| Validator rejections by code (`forbidden_kind`, `unknown_key`, `bomb`, `sha_mismatch`, `generation_changed`) | `activity_commit_event` | spike against the daily baseline |
| Fence and tombstone refusals | callable events | informational; spike |
| Telemetry rejections, quota refusals, dropped counter | `debug_telemetry_event`, `debug_telemetry_dropped` | spike against the baseline |
| Missing composite index (`FAILED_PRECONDITION`) | `activity_purge_event` | any |
| Stuck fence or late job | `activity_late_sweep_event` | stuck count > 0 |

Forced-failure check per row: see design 6.3 and test F71. The alert policies are applied by the operator from this table; nothing here has been applied.

## 9. Honest limit (privacy text input)

The server enforces a closed schema (no heart-rate kind, no unknown key, bounded shapes and ranges, a coordinate-like string denial) and stores a canonical re-serialisation. It cannot detect heart-rate values relabelled as an allowed numeric stream (design 5.1a, accepted residual risk DQ-6). The privacy text must say so instead of claiming a guarantee against a modified client.

## 10. Rollback

Roll back by flag: turn `ACTIVITY_CLOUD_STREAMS` and the server setting off; summaries stay valid and stream objects remain until the purge or a user delete. NEVER unset or change `ACTIVITY_STREAM_BUCKET` while objects exist in the bucket: every erase path finds the bucket through that variable alone. Only after the bucket is verifiably empty may it be unset. Never revert the activity rules floor (section 6, step 3).
