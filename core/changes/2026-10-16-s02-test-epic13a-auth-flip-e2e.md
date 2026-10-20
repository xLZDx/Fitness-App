# S02 test epic 13a: auth-flip end-to-end

Date: 2026-10-16. Area: tests only.

## What changed

- New `mobile/test/features/activity/e2e/s02_auth_flip_e2e_test.dart` (2 tests) over the real `FileActivityJournal`
  on a temp directory, the real `ActivitySyncRepository`, a cloud fake keyed by the signed-in uid at call time and a
  recording tombstone pusher.
- Test 1: `authUid` flips to B while the journal still holds A's entries: syncAll, syncEntry, syncBatch,
  resolveConflict and applyExplicitEdit return pending/empty, zero cloud calls, zero pushes, every file under the
  temp tree byte-identical (A and B); after B's rebind and `onAccountChanged` only B's own entry is written, under B,
  and A's ids never appear in a call; A's entry and tombstone are intact.
- Test 2: a retry timer scheduled under A does nothing after an unannounced flip to B; with matching uids the same
  callback runs (control).

## Verification state

`flutter test --timeout 60s test/features/activity/e2e/s02_auth_flip_e2e_test.dart`: `00:01 +2: All tests passed!`
(one import fix of mine first: `dart:async`).
