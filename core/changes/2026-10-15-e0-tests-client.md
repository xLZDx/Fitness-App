# E0 tests, client part (T01, feature gates, data notice)

## What
- Added `mobile/test/core/config/body_scan_flags_test.dart` (T01, SCAN-40): defaults OFF, define-to-field mapping, copyWith, equality, provider override.
- Extended `mobile/test/features/subscription/feature_gates_test.dart`: exact enum order, `bodyScan` gated to non-free tiers, five other new entries open on every tier, full feature x tier table.
- Added `mobile/test/core/privacy/data_notice_test.dart` (PRIV-23 client half): key/version shape, store persistence, refused durable write, providers, sheet gate in EN/RU, food-AI paragraph only with `foodAi`, text scale 2.0.

## Why
Coverage map v1.1 section 9 (E0 files) and section 12 (new rows for feature_gates and data_notice).

## Paths
mobile/test/core/config/body_scan_flags_test.dart, mobile/test/features/subscription/feature_gates_test.dart, mobile/test/core/privacy/data_notice_test.dart

## Verification
Committed before the first run (coordinator request to commit early). Run results are recorded in the follow-up change record.
