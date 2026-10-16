# S02 test epic 1: cloud summary, payload, merge, ownership and schema pin tests (U05-U09, U13, U31, U32, U37-U39)

## What changed
- Tests: activity_cloud_summary_test (U05, U07, U13, U38), summary_allowlist_parity_test (U06, parses firestore.rules), activity_stream_payload_test (U08, U09, U32), workout_model_ownership_test (U31), summary_three_way_merge_test (U39), stream_schema_pin_test (U37).
- New shared fixture functions/src/__tests__/activity/fixtures/stream_schema_keys.json (mirrors schema.ts; also read by the functions test F53/F91).
- Production fix: activity_stream_payload.dart drops heart-rate-named entries from fieldsContributed (the name heartRate was leaving the device inside the cloud payload; U08 oracle says the payload must not contain heartRate).

## Why
Phase 7 (Verify) of sprint S02: functional tests for test epic 1 (model, projection and corpus, stories S02-00 and S02-01), authored from docs/phase2/s02/S02_TEST_PLAN.md.

## Affected paths
- mobile/test/features/activity/data/activity_cloud_summary_test.dart
- mobile/test/features/activity/data/summary_allowlist_parity_test.dart
- mobile/test/features/activity/data/activity_stream_payload_test.dart
- mobile/test/features/activity/data/workout_model_ownership_test.dart
- mobile/test/features/activity/data/summary_three_way_merge_test.dart
- mobile/test/features/activity/data/stream_schema_pin_test.dart
- functions/src/__tests__/activity/fixtures/stream_schema_keys.json
- mobile/lib/features/activity/data/activity_stream_payload.dart

## Verification state
Command (from mobile/): flutter test --reporter failures-only <the six files above> -- +197: All tests passed!
