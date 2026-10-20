# S02 test epic 4: two-device fake server, rev convergence, tombstone sync, override convergence (I13, I26, I31-I33, I37-I39, I43, I44)

## What
- `mobile/test/support/two_device_world.dart`: a fake Firestore server that enforces the rules (rev rule, immutable `startUtc`/`sport`, closed key shape and bounds, `startUtc` clamp, tombstone, account fence), records every accepted and refused write per device, and devices (own journal directory, own `ActivitySyncRepository`, per-device offline / dropped acknowledgement / hook between a read and the next write). Scenario builders `bothSynced` and `adopted` (the common setup of plan 1.16).
- `activity_rev_convergence_test.dart`: I31 (both orders, field values, restart, capped retry), I32 (lost acknowledgement, other device changed another field, restart), I33 (fresh device updates at rev 4, never a create over an existing id), I38 (same field stays `sync_conflict`, both orders, one retry per start), I39 (keep device / keep cloud / offline choice).
- `activity_tombstone_sync_test.dart`: I26 cases 1-5 plus re-import refusal, I37 (retry once, no hot loop), I13 (tombstone push survives a restart).
- `activity_override_convergence_test.dart`: I43 (restart, second edit on both devices in both orders, drop by equality / by changed value) and I44 (field the device cannot reproduce).
- No production change.

## Why
Test plan epic 4 (story S02-12), design 3.2 and 6.2. The loser of each race is shown to be refused by the fake before convergence is asserted.

## Affected paths
The four files above, all under `mobile/test/`.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/repository/activity_rev_convergence_test.dart test/features/activity/repository/activity_tombstone_sync_test.dart test/features/activity/repository/activity_override_convergence_test.dart`
Result: `All tests passed!` (see the final epic run in the findings document for counts).
