# Change record: recorder epoch fence and rollback retry (GPT round 3 MINOR-01 and MINOR-02)

## What changed
- `mobile/lib/features/form_check/debug/coach_recorder.dart`: an `_epoch` counter is bumped on every discard and every new recording; a save in flight captures it, and the post-write validation requires it unchanged. A recording abandoned by an A to B switch is therefore rolled back even if A signs back in before the write completes. `CoachRecordingStore.discard` retries up to three times (150 ms apart) before giving up with a log line.
- `mobile/test/features/form_check/coach_recorder_account_test.dart`: A to B to A during a parked save, and discard retry (one failure, three failures).

## Why
Non-blocking observations of the round 3 APPROVE on ac7f5a1: the same-uid return (A to B to A) could keep an abandoned recording, and a single transient filesystem error left an aborted recording behind.

## Affected contracts and paths
Debug/profile-only coach recorder and its `coach_recordings/<uid>` lifecycle.

## Verification state
Focused run by an e2e-runner agent: coach_recorder_account_test.dart 15 passed, local_data_wipe_test.dart 18 passed. Not run on a device.
