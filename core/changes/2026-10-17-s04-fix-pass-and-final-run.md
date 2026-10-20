# S04 fix pass and final test run

Date: 2026-10-17. Kind: code and tests.

## What changed
- pipeline: distance_accumulator.dart (new), smoothing, elevation, recorded_track, recorder_pipeline, recording_constants.
- tests: four KNOWN_DEFECT tests un-skipped, replay_expected re-recorded, DT-15-10 accepts the approved wording; new account_events_test and start_panels_test.
- docs/phase2/s04/S04_TEST_FINDINGS_FINAL.md and the F/G/J findings update.

## Why
Epic tests found tolerance misses and a segment-end distance loss.

## Affected contracts and paths
formulaVersion string unchanged although the distance rule changed (to review).

## Verification state
flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout: 1096 passed, 0 failed, 0 skipped. NOT_RUN: device rows, analyze, build, CI.
