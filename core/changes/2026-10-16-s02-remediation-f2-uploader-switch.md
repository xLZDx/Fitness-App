# S02 remediation F2 (4/4): uploader single-flight state across an account switch

## What changed

`mobile/lib/features/activity/repository/activity_stream_uploader.dart`:

- `cancelQueued()` now also bumps a private `_epoch` and clears `_runInFlight`, `_entryInFlight` and `_failedThisStart`. After account A to B, `runPending()` starts a fresh run for B instead of returning A's cancelled future, and A's failed ids no longer suppress the same ids for B.
- The `whenComplete` cleanups of `runPending()` and `uploadEntry()` free the slot only when the finishing future still owns it (`identical`), so A's late completion cannot clear B's run.
- A run records `_failedThisStart` and writes `upload_failed` only when its epoch is still current; A's in-flight run still ends as `cancelled` and writes nothing (the existing `_uidOk` re-checks are unchanged).

No public signature changed. `activity_wiring.dart` needed no change for this item: it already calls `cancelQueued()` on an account change and `resume()` after the new bind.

## Why

Reviewer Flutter 2: single-flight state survived an account switch, so B got no upload run in that app start.

## Verification state

Not compiled and not run. Tests listed in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`.
