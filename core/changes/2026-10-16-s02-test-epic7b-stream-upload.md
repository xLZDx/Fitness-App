# S02 test epic 7b: client stream upload tests (I15, I16, I17)

## What
`activity_stream_upload_test.dart` (29 tests): flag off sends nothing, consent unknown/withdrawn/not loaded sends nothing, create -> PUT -> commit order, `contentSha256` equals the hash of the PUT bytes, closed payload without heart rate (stream, lap average, field name, sentinel 173.25), the real sequence summary sync then upload, durable marker across restart, edits, wiring behind the flag.

## Why
Plan rows I15, I16, I17 and the suspect that a summary-synced entry was never uploaded.

## Affected paths
- `mobile/test/features/activity/repository/activity_stream_upload_test.dart`

## Verification state
29 passed alone; included in the final epic run recorded in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md`.
