# S02 test epic 3: merger operation-count budget, consent matrix, copy lint (U21, U22, U24, U33, U36)

## What
- `mobile/test/features/activity/data/activity_merger_perf_test.dart`: U21 (300 candidates x 3 600 GPS points), U22 (2 000 sessions without streams), U36 (the `onPairCompared` seam is behaviour-neutral). The comparison count is the only criterion; wall clock is printed, never asserted. First run measured 300 comparisons (U21) and 2 000 (U22); the design ceilings (100 000 / 4 000 000) are asserted together with calibrated ceilings frozen at 1 000 and 6 000, because n^2/2 = 45 000 would still pass the design ceiling for 300 candidates.
- `mobile/test/features/activity/data/cloud_upload_policy_test.dart` (U24): the design 9 matrix, cloud-stream and cloud-summary columns, over `ActivityStreamPayload.fromSession` / `ActivityCloudSummary.fromSession` (there is no separate policy class).
- `mobile/test/features/activity/copy_lint_test.dart` (U33): scanner with positive controls (English and Russian), applied to the `activity*` ARB keys of both locales and to the string literals of the S02 widgets and state.
- No production change.

## Why
Design 10 (budget by operation count), design 9 (consent matrix, no dedup promise), plan DQ-13 / DQ-14.

## Affected paths
The three test files above.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/data/activity_merger_perf_test.dart test/features/activity/data/cloud_upload_policy_test.dart test/features/activity/copy_lint_test.dart`
Result: `All tests passed!` (31 tests).
