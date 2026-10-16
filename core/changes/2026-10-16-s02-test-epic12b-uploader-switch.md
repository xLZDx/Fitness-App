# S02 test epic 12b (3): uploader after an account switch

## What changed
- New `mobile/test/features/activity/repository/activity_stream_uploader_account_switch_test.dart` (7 tests): A's run blocked in `create`, switch to B with `cancelQueued()` and `resume()`: `runPending()` returns a different future and uploads B's entry; A's released run ends `cancelled` with no put, commit, mark or `upload_failed`; A's late completion does not free B's in-flight slot; `uploadEntry` single-flight does not hand B A's outcome; an id that failed for A is uploaded for B (with a same-account control that it is skipped); a run of an old epoch records no failure after `cancelQueued` + `resume` on the same uid.
- No production change: the uploader met every note on the first run (one test slip was mine: a fault hook ordering).

## Verification state
File plus `activity_stream_upload_test.dart`: `+36: All tests passed!`. Complete runs: docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md section Epic 12b.
