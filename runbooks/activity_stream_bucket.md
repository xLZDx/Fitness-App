# Activity stream private bucket: operator runbook

Status: NOT_RUN. Nothing in this runbook has been executed; the default build does not need it. The cloud stream path (server setting `ACTIVITY_STREAM_BUCKET`) stays off until every step below is done. Design: `docs/phase2/s02/S02_DESIGN.md` sections 5, 5.1, 5.1a, 5.2, 5.3 (D-16, GPS-PRIV-064, GPS-PRIV-078). Written by story S02-04a; the callables and their runtime identities arrive in S02-04b and the purge in S02-06.

## 1. Create the bucket

Name `<project>-activity-streams-private`. It MUST be a different bucket from `<project>-bodyscan-private` (GPS-PRIV-064). The server treats a value equal to `BODY_SCAN_BUCKET` as "not configured", so the feature stays off if the two are ever mixed up.

- Location: EU. Storage class: Standard.
- Uniform bucket-level access: ON.
- Public access prevention: ENFORCED. No `allUsers` / `allAuthenticatedUsers` binding, ever.
- Soft delete and object versioning: disabled, or windowed to the shortest period the operator accepts (GPS-PRIV-078). OPEN: the operator decides the window; a longer window means deleted GPS stays recoverable for that long and the privacy text must say so.
- Lifecycle rule on the `quarantine/` prefix only: delete objects older than 1 day (backstop for abandoned uploads, design 5.2). NEVER add an age rule on `streams/`: retention is a per-user setting derived at purge time (design 5.3), and an age rule would silently break "never".

Objects are only `quarantine/{uid}/{activityId}/{uploadId}` and `streams/{uid}/{activityId}/{uploadId}.json.gz`.

## 2. Runtime identity and IAM

OPEN until S02-04b/S02-06 name the runtime identity of the stream callables and the purge. Rules that already hold: `roles/storage.objectAdmin` on THIS bucket only for the stream runtime identity and for `fn-account-delete` (account deletion sweeps the bucket); `roles/iam.serviceAccountTokenCreator` on the runtime identity itself for V4 signed URLs; the shared `fn-data` identity gets NO access to this bucket.

## 3. Configure the functions

Set in the codebase-wide `functions/.env.<project>`:

```
ACTIVITY_STREAM_BUCKET=<project>-activity-streams-private
```

Read through `functions/src/activity_streams/flags.ts` only, per call. Unset (or invalid, or equal to `BODY_SCAN_BUCKET`) means the feature is off and the sweep is a logged no-op.

## 4. Storage rules

`storage.rules` stays the single deny-all for the DEFAULT bucket; this private bucket is not governed by Firebase rules and is reachable only through V4 signed URLs and the Admin SDK. Any `allow` for `streams/` or `quarantine/` in `storage.rules` is a defect.

## 5. Honest limit (privacy text input)

The server enforces a closed schema (no heart-rate kind, no unknown key, bounded shapes and ranges) and stores a canonical re-serialisation. It cannot detect heart-rate values relabelled as an allowed numeric stream (design 5.1a, accepted residual risk DQ-6). The privacy text must say so instead of claiming a guarantee against a modified client.

## 6. Rollback

NEVER unset or change `ACTIVITY_STREAM_BUCKET` while objects exist in the bucket: every erase path finds the bucket through that variable alone. Only after the bucket is verifiably empty may it be unset.
