# S02 test epic 14b: deletion flag tests

What: new test file activity_sync_deletion_flag_test.dart (10 tests), new helper mobile/test/support/stale_view_world.dart (Gate, RecBackend, HookJournal), and one production line in activity_sync_repository.dart (syncAll logs the skip when the identity goes stale after the tombstone listing).

Why: remediation H5 oracles (S02_REMEDIATION_H_TEST_NOTES.md H-B item 1, design 17 item 24 b).

Affected paths: mobile/test/features/activity/repository/activity_sync_deletion_flag_test.dart, mobile/test/support/stale_view_world.dart, mobile/lib/features/activity/repository/activity_sync_repository.dart.

Verification: flutter test --timeout 60s test/features/activity/repository/activity_sync_deletion_flag_test.dart -> 00:06 +10: All tests passed!
