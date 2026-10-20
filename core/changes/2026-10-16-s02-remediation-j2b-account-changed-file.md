# Move the account-changed outcome to its own file (remediation J2b)

Date: 2026-10-16. Kind: production refactor, no behavior change.

## What changed
- New mobile/lib/features/activity/repository/account_changed.dart holds `ConsentAccountChangedException` and `isAccountChangedRefusal`.
- activity_cloud_settings_client.dart imports it and re-exports both symbols (existing importers, including tests, are unaffected).
- activity_stream_uploader.dart, activity_sync_repository.dart and cloud_functions_activity_tombstone_pusher.dart import the new file instead of the settings client library.

## Why
Remediation J2 made the uploader, the sync repository and the tombstone pusher import the settings client library, which already imports the uploader: an import cycle between two repository libraries that no existing test guards.

## Affected contracts and paths
None. Same exception type, same helper, same behavior.

## Verification state
Not run. The test agents of epic 16 compile and run the activity tests after this commit.
