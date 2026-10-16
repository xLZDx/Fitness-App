# S02 test epic 1: summaryOverrides projection tests (U41) and findings

## What changed
- summary_overrides_test (U41): oracle rows G1-G46 of plan 1.16 at the pure level (data rows in mobile/test/support/golden_override_scenarios.dart plus inline literals), tolerant JSON of the record state, ring independence, purity.
- Production fix: summary_projection.dart adoptServerValue keeps an existing recalcCandidate (row G17).
- docs/phase2/s02/S02_TEST_FINDINGS_EPIC1.md records the plan/design corrections and all production fixes of the epic.

## Why
Phase 7 (Verify) of sprint S02: functional tests for test epic 1 (model, projection and corpus, stories S02-00 and S02-01), authored from docs/phase2/s02/S02_TEST_PLAN.md.

## Affected paths
- mobile/test/features/activity/data/summary_overrides_test.dart
- mobile/test/support/golden_override_scenarios.dart
- mobile/lib/features/activity/data/summary_projection.dart
- docs/phase2/s02/S02_TEST_FINDINGS_EPIC1.md

## Verification state
Command (from mobile/): flutter test --reporter failures-only test/features/activity/data/summary_overrides_test.dart -- +62: All tests passed!
