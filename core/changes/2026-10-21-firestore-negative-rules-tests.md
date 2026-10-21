# 2026-10-21 Firestore negative-access rules tests

Branch: test/firestore-rules-negative-2026-10-21 (base origin/master dc124bbc). Tests only; no change to firestore.rules or any production file.

## Why

`match /users/{uid}/{coll}/{document=**}` grants the owner read/write on every sub-collection and carves protected ones out with `coll != '...'` lists (one list in the read rule, one in the write rule). An independent review found that a list of names cannot stop a client from using an unlisted or newly added sub-collection, and that the server-only collections lacked negative tests.

## What the new file asserts

File: `functions/src/__rules__/v1_negative_access_rules.test.ts` (own emulator project id `demo-fitness-negative-access`).

The `coll != '...'` names are parsed from `firestore.rules` at run time (read list and write list separately). A collection is classed "server-only" when it has no dedicated `match` block, or every write verb in its block is `if false`. Nothing is hard-coded except a drift guard that the seven known server-only names (subscription, usage, receipts, recognised_models, equipment_identity_sessions, equipment_identity_latest_session, equipment_identity_telemetry) stay classified that way.

- Drift guards: lists parse, read list is a subset of write list, known server-only names remain server-only.
- (a) For each server-only collection: owner create, overwrite, update, delete and a nested-path write are all denied; owner read is denied where the read list excludes it and the block denies reads; `subscription` is still owner-readable but not writable.
- (b) For EVERY excluded name (read list union write list): another authenticated user and an unauthenticated client are denied get, create, overwrite, update and delete (a seeded document exists, seeded with rules disabled).
- (c) `users/{uid}/workout_command_policy/current`: if the rules mention `workout_command_policy`, the owner client must be denied create/update/delete. If not (current state), the test pins the CURRENT behavior (owner can write it) under a name that documents the finding. Other user and signed-out client are denied in both cases.
- (d) `documents: unlisted owner sub-collection is writable (allow-list gap)`: a brand-new name under `users/{uid}` is writable/readable/deletable by the owner today; another user and signed-out client are still denied.

## Findings for the owner of the rules

1. Allow-list gap (proven at runtime by the test named in (d)): any sub-collection name not on the lists is fully owner read/write. Recommended fix: invert the wildcard to an explicit allow-list of owner-writable collections, or end the wildcard with a default deny and give each client-writable collection its own block.
2. `workout_command_policy/current` is not mentioned anywhere in the repository (grep of firestore.rules and the whole worktree finds no occurrence). If it is meant to be server-only, the owner can currently create, overwrite and delete it. No other command, admission or policy collection names exist in firestore.rules either.
3. `subscription` is protected only by absence: it is on the write list but has no dedicated block, so the protection depends on the wildcard exclusion alone.

## Verification state

Only the new file was run, against the local Firestore emulator (no real Firebase project, nothing deployed or pushed).

## Run result

- Command (from `functions/`, emulator moved off default port 8080 because that run failed to start the emulator, and 18080 is taken by an unrelated local process):
  `FIREBASE_EMULATOR_CONFIG=<abs path of a temp firebase.json with firestore on 127.0.0.1:38427 and rules = this worktree's firestore.rules> FIRESTORE_EMULATOR_PORT=38427 node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-negative-access src/__rules__/v1_negative_access_rules.test.ts`
- Default command for a clean machine: `cd functions && node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-negative-access src/__rules__/v1_negative_access_rules.test.ts`
- Result: 1 suite passed, 62 tests passed, 0 failed, 0 skipped (JDK 21.0.12 from D:/tools, host Node v24.13.1 although functions/package.json pins engines node 20; gRPC did not block this firestore-only run).
- Server-only set derived from the rules at run time: subscription, usage, receipts, recognised_models, equipment_identity_sessions, equipment_identity_latest_session, equipment_identity_telemetry, activity_streams, activity_settings, activity_tombstones. `profile`, `body_scans` and the other excluded names have conditional client writes and are covered by (b) only here; their owner-side behavior stays with firestore_rules.test.ts.
- Not covered: the full rules suite was not run (only this file); mutation checks were not run by operator policy; auth/e2e suites untouched.
