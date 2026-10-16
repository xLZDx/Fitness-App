# S02 test epic 1: corpus, round trip and migration tests (U01-U04, U12, U27, U28)

## What changed
- Deterministic seeded valid corpus (100 sessions) and hostile set under mobile/test/support, with committed digests.
- Tests U01, U02, U03, U04, U12, U27, U28.
- Production fixes (tolerant reader must not throw on NaN/Infinity): activity_session.dart (utcOffsetMinutes, schema), lap.dart (index, timing, strokeCount), sample_stream.dart (offsets). Found by the U12 fuzz.

## Why
Phase 7 (Verify) of sprint S02: functional tests for test epic 1 (model, projection and corpus, stories S02-00 and S02-01), authored from docs/phase2/s02/S02_TEST_PLAN.md.

## Affected paths
- mobile/test/features/activity/data/synthetic_corpus_test.dart
- mobile/test/features/activity/data/activity_migration_test.dart
- mobile/test/features/activity/data/activity_roundtrip_100_test.dart
- mobile/test/support/firestore_rules_parser.dart
- mobile/test/support/s02_fixtures.dart
- mobile/test/support/s02_paths.dart
- mobile/test/support/synthetic_activity_corpus.dart
- mobile/test/support/synthetic_corpus_digest.txt
- mobile/test/support/synthetic_hostile_corpus.dart
- mobile/lib/features/activity/data/activity_session.dart
- mobile/lib/features/activity/data/lap.dart
- mobile/lib/features/activity/data/sample_stream.dart

## Verification state
Command (from mobile/): flutter test test/features/activity/data/synthetic_corpus_test.dart test/features/activity/data/activity_migration_test.dart test/features/activity/data/activity_roundtrip_100_test.dart -- result: all passed (see the epic closing run in the final record).
