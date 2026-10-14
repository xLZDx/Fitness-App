# Change record: coach recorder save fenced against account change and deletion

## What changed
- `mobile/lib/features/form_check/debug/coach_recorder.dart`: `_stop()` validates the account (same uid as the recording AND not flagged by `accountBeingDeletedUidProvider`) before the write and again after `CoachRecordingStore.save` returns. If the account changed or was deleted during the write, the new `CoachRecordingStore.discard(uid, file)` removes the written file (and the uid folder when empty) under the original uid only, and nothing is shown. Validation reads through the ProviderContainer so it also works after the widget is disposed.
- `mobile/test/features/form_check/coach_recorder_account_test.dart`: deferred-save tests (account deleted with the real local wipe during the write, account switch during the write, unchanged control) and `discard` unit tests.

## Why
Round 2 of the final GPT-PM gate (HEAD e58f7c4) found one remaining MAJOR: an identity check before `save()` cannot stop a write already in flight, so A's movement-derived recording could be recreated after account deletion and the local wipe.

## Affected contracts and paths
Debug/profile-only coach recorder; the data lifecycle for `coach_recordings/<uid>` (inventory unchanged: still wiped on deletion, now also never recreated by an in-flight save).

## Verification state
Focused run by the e2e-runner agent: coach_recorder_account_test.dart (9 tests plus 3 discard tests) and local_data_wipe_test.dart (16): 30 passed, 0 failed. Not verified on a device.
