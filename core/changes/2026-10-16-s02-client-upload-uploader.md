# S02 client stream uploader and retry policy

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- New `mobile/lib/features/activity/repository/activity_stream_uploader.dart`: `ActivityStreamUploader` with injectable seams (callable client for create/commit, HTTP PUT sender, clock, delay scheduler, consent view, flags). It builds the closed payload (heart rate hard-dropped inside `ActivityStreamPayload.fromSession`), gzips it, hashes the gzip bytes as `contentSha256`, creates the upload, PUTs to the signed URL, commits, and only then writes the journal `synced` marker via `markSynced`.
- Retry policy (design 5.2 item 4, test plan I27): at most 5 attempts per run, deterministic delays 1 s, 2 s, 4 s, 8 s without jitter, total budget 10 minutes of the injected clock. Every attempt is a fresh create+PUT+commit, so after an app kill the restart re-uploads (never resumes at commit, never resumes a half-done PUT). After the cap the entry is marked `upload_failed` through `updateSyncState` and is not retried again by the same uploader instance (no hot loop); the next app start retries it.
- Nothing is sent when the flag is off, consent is not granted, or the uploader was cancelled (I15, I17). `cancelQueued()` stops queued and in-flight runs before their next network step.
- `CloudFunctionsActivityStreamClient` calls `createActivityStreamUpload` and `commitActivityStream`; `unavailable`, `internal`, `deadline-exceeded`, `aborted` are transient, every other code is a permanent refusal (no retry, journal untouched).

## Why
Plan rows I15, I16, I17, I27 require client code that had not been written.

## Affected contracts and paths
`mobile/lib/features/activity/repository/activity_stream_uploader.dart` (new). No existing file changed; nothing is wired yet, so behaviour is unchanged.

## Verification state
No tests, analysis or builds were run (operator rule). The design has no separate stream-state field in the journal, so the existing sync state (`pending`/`synced`/`upload_failed`) is used as design 5.2 item 4 words it.
