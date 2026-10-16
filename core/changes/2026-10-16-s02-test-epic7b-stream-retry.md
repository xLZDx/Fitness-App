# S02 test epic 7b: client retry policy tests (I27)

## What
`activity_stream_upload_retry_test.dart` (22 tests): at most 5 attempts, delays 1/2/4/8 s without jitter, 10 minute budget on the injected clock, every attempt a new upload, upload_failed after the cap, no retry for an hour within one start, retry at the next start, stale generation and sync_conflict not overwritten, restart after a killed run (after PUT, mid-PUT, after create) re-uploads and never commits an old upload id.

## Why
Plan row I27 and design 5.2 item 4.

## Affected paths
- `mobile/test/features/activity/repository/activity_stream_upload_retry_test.dart`

## Verification state
22 passed alone; included in the final epic run in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md`.
