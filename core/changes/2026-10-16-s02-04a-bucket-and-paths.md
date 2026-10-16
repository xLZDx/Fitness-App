# S02-04a change record: stream bucket setting, path builders, bucket seam, storage rules note, runbook

Date: 2026-10-16. Story: S02-04a (design sections 5, 5.1, 5.2, 5.4; GPS-PRIV-064; test ids F12, S01-S03).

## What changed

- `functions/src/activity_streams/flags.ts`: `activityStreamBucketName()` / `activityStreamCloudEnabled()` read `ACTIVITY_STREAM_BUCKET` per call, same naming rule as Body Scan. Unset, invalid, or equal to `BODY_SCAN_BUCKET` means not configured (GPS-PRIV-064 isolation, F12).
- `functions/src/activity_streams/paths.ts`: id patterns (`^act_[0-9a-f]{40}$`, server-generated `^up_[0-9a-f]{32}$`, uid segment) and throwing path builders for `quarantine/{uid}/{activityId}/{uploadId}`, `streams/{uid}/{activityId}/{uploadId}.json.gz` and the activity and user prefixes. Built only from uid plus validated ids (design 5.4).
- `functions/src/activity_streams/bucket.ts`: structural `StreamBucket` / `StreamFile` interfaces and an injectable factory so tests use a fake bucket and count reads (generation pin, F49); `activityStreamBucket()` returns `undefined` when off; `deleteStreamObjects(prefix)` mirrors `deleteScanObjects` and is a no-op when off.
- `storage.rules`: comment only. The file stays the single deny-all (test S03 guards against any extra `allow`); the comment records that streams live in a separate private bucket.
- `runbooks/activity_stream_bucket.md`: operator runbook, status NOT_RUN (bucket, public access prevention, soft delete window, quarantine-only lifecycle rule, IAM, setting, rollback, honest limit).

## Why

Design 5 recommends option (b), a dedicated private bucket reachable only by signed URLs, so `storage.rules` stays deny-all and server-side validation can enforce the closed schema before promotion.

## Affected contracts and paths

`functions/src/activity_streams/{flags,paths,bucket}.ts`, `storage.rules` (comment), `runbooks/activity_stream_bucket.md`. No `firebase.json` change: it already deploys `storage.rules` and the new bucket needs no Firebase rules.

## Deviations and notes

- The runtime identity and IAM grants are left OPEN in the runbook: they depend on callables and the purge from S02-04b and S02-06.
- `firestore.indexes.json`, quota action names and `REDACTED_QUOTA_ACTIONS` belong to S02-04b and are not touched.

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify with F12, S01-S03.
