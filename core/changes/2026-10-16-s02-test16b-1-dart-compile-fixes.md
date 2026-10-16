# Dart test tree: compile fixes for remediation J2/J3b (epic 16b, 1/3)

Date: 2026-10-16. Kind: test maintenance.

## What changed
- mobile/test/support/stream_upload_world.dart: new helper `storeUid(store)` (live-uid supplier that follows the consent store's bound uid); `FakeStreamCloud.create/commit` take and record `expectedUid` (`CreateCall.expectedUid`, `CommitCall.expectedUid`).
- Settings client constructors in six test files now pass `currentUid: storeUid(store)`, so the old scenarios keep their meaning.
- `FakeStreamCloudStub` takes `expectedUid`.
- Tombstone pusher closures and fakes take two arguments `(id, expectedUid)` in ten files.
- activity_sync_pass_identity_test.dart (presenter test, group C): overrides `syncConflictUidProvider` with a uid, because J3 B4 makes a tap without a uid a no-op.

## Why
J2 made `currentUid` required and added `expectedUid` to the stream client and the tombstone pusher; J3b made a null-uid presenter tap a no-op. Without these edits the test tree did not compile.

## Affected contracts and paths
Test code only. No product file changed.

## Verification state
Run by the 16b test agent over all 15 touched files with `flutter test --timeout 60s`: one stale assertion (presenter, B4) was red and fixed. Results are in docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md section 16b.
