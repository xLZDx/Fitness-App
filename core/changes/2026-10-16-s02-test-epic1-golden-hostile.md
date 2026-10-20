# S02 test epic 1: golden summaries and hostile normalised tests (U30, U40)

## What changed
- summary_golden_test (U30) with the generated golden functions/src/__rules__/fixtures/s02_summaries_100.json (format: version, note, summaries[{id, summary}], timestamps as ISO-8601 UTC strings; the rules test R25 must convert them).
- hostile_corpus_normalised_test (U40) against the hand-written mobile/test/support/synthetic_hostile_expected.json.

## Why
Phase 7 (Verify) of sprint S02: functional tests for test epic 1 (model, projection and corpus, stories S02-00 and S02-01), authored from docs/phase2/s02/S02_TEST_PLAN.md.

## Affected paths
- mobile/test/features/activity/data/summary_golden_test.dart
- mobile/test/features/activity/data/hostile_corpus_normalised_test.dart
- mobile/test/support/synthetic_hostile_expected.json
- functions/src/__rules__/fixtures/s02_summaries_100.json

## Verification state
Command (from mobile/): flutter test --reporter failures-only test/features/activity/data/summary_golden_test.dart test/features/activity/data/hostile_corpus_normalised_test.dart -- +18: All tests passed!
