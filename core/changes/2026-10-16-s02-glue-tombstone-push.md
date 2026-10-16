# S02 glue: push local tombstones to the server

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/activity_sync_repository.dart`: new optional constructor parameter `tombstonePusher` (`ActivityTombstonePusher`). `syncAll` now, after a successful tombstone-list read, pushes local tombstones that the server does not list yet (at most 8 per pass; a failure is swallowed and retried at the next pass). Ids the server already tombstones are skipped, so repeated passes do not consume the daily `activityDelete` quota (100). When the server list could not be read nothing is pushed.
- `mobile/lib/features/activity/repository/cloud_functions_activity_tombstone_pusher.dart` (new): calls the `deleteActivity` callable with `{activityId}`.
- `mobile/lib/core/wiring/activity_wiring.dart`: passes the pusher to the repository.

## Why
Design 6.2: the sweep that removes local copies of server-tombstoned ids existed, but a local delete never reached the server, so other devices kept the activity.

## Affected contracts and paths
Additive and optional: without a pusher (all existing tests) `syncAll` behaves as before. The `ActivitySummaryBackend` seam is unchanged, so existing fakes still compile.

## Verification state
No tests, analyzer or build were run. Not verified: compilation; a behaviour test for the push (pusher called once per unknown tombstone, skipped for server-known ones, skipped when the list read fails).
