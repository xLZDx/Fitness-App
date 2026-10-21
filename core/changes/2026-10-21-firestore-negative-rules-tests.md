# 2026-10-21 Firestore negative-access rules tests

Branch: test/firestore-rules-negative-2026-10-21 (rebased onto master 075b1aac before merge). Tests only; no change to firestore.rules or any production file.

## Why

`match /users/{uid}/{coll}/{document=**}` grants the owner read/write on every sub-collection and carves protected ones out with `coll != '...'` lists (one list in the read rule, one in the write rule). An independent review found that a list of names cannot stop a client from using an unlisted or newly added sub-collection, and that the server-only collections lacked negative tests.

## What the new file asserts

File: `functions/src/__rules__/v1_negative_access_rules.test.ts` (own emulator project id `demo-fitness-negative-access`).

Expected policy and observed rules are kept apart:

- **Hard-coded expected policy (the authority).** Ten mandatory server-only-write collections: subscription, usage, receipts, recognised_models, equipment_identity_sessions, equipment_identity_latest_session, equipment_identity_telemetry, activity_streams, activity_settings, activity_tombstones. Of these, five are owner-read-denied today (usage, receipts, equipment_identity_sessions, equipment_identity_latest_session, equipment_identity_telemetry); the other five (subscription, recognised_models, activity_streams, activity_settings, activity_tombstones) are owner-readable. Both sets were derived once from firestore.rules on 2026-10-21 and are constants in the test. Their assertions run unconditionally, so a more permissive rule produces a failing assertion, not fewer assertions.
- **Parser (secondary).** The `coll != '...'` names are still parsed from `firestore.rules` at run time, only to (1) assert that every mandatory name is on the write exclusion list (and the five read-denied ones on the read exclusion list) and (2) add extra names the rules may gain later to the same tests. The parser is never the sole source of the protected inventory.

Groups:

- Drift guards: lists parse; read list is a subset of write list; the mandatory inventory has exactly ten unique names; each mandatory name is on the write exclusion list and classified server-only; each read-denied name is on the read exclusion list.
- (a) For each mandatory (plus parser-discovered) server-only collection: owner create, overwrite, update, delete and a nested-path write are denied. For each owner-read-denied name: owner get, collection list (`getDocs`), nested get and nested list are denied. For each owner-readable name: owner get and list succeed, owner write is denied. A collection-group query over every mandatory name is denied to the owner.
- (b) For EVERY excluded name (mandatory inventory plus read list plus write list, which includes the conditional-write collections profile, body_scans, body_scan_settings, weight_entries, nutrition_plan, nutrition_plan_reviews, food_entries, saved_foods, activities): another authenticated user and an unauthenticated client are denied get, create, overwrite, update and delete; denied a collection list; and denied get, list, create, overwrite, update and delete on a nested path (`users/{uid}/<coll>/seed/sub/n1`). The OWNER is also denied every write on that nested path, because the dedicated blocks match only one document level and the wildcard excludes the name.
- (c) `users/{uid}/workout_command_policy/current`: if the rules mention `workout_command_policy`, the owner client must be denied create/update/delete. If not (current state), the test pins the CURRENT behavior (owner can write it) under a name that documents the finding. Other user and signed-out client are denied in both cases.
- (d) `documents: unlisted owner sub-collection is writable (allow-list gap)`: a brand-new name under `users/{uid}` is writable/readable/deletable by the owner today; another user and signed-out client are still denied.

## Findings for the owner of the rules

1. Allow-list gap (proven at runtime by the test named in (d)): any sub-collection name not on the lists is fully owner read/write. Recommended fix: invert the wildcard to an explicit allow-list of owner-writable collections, or end the wildcard with a default deny and give each client-writable collection its own block.
2. `workout_command_policy/current` is not mentioned anywhere in the repository (grep of firestore.rules and the whole worktree finds no occurrence). If it is meant to be server-only, the owner can currently create, overwrite and delete it. No other command, admission or policy collection names exist in firestore.rules either.
3. `subscription` is protected only by absence: it is on the write list but has no dedicated block, so the protection depends on the wildcard exclusion alone.
4. The new list, nested-path and collection-group assertions all passed against the current rules; they exposed no additional gap.

## Verification state

Only the new file was run, against the local Firestore emulator (no real Firebase project, nothing deployed or pushed).

## Run result

- Runtime note: `functions/package.json` and `firebase.json` now target Node 22 (`nodejs22`). This run used the HOST Node v24.13.1, not Node 22; no Node 22 run is claimed. JDK 21.0.12 (D:/tools/jdk-21.0.12+8) for the emulator.
- Command (from `functions/`, emulator moved off default port 8080 because that port was not usable on this machine, and 18080 is taken by an unrelated local process):
  `FIREBASE_EMULATOR_CONFIG=<abs path of a temp firebase.json with firestore on 127.0.0.1:38427 and rules = this worktree's firestore.rules> FIRESTORE_EMULATOR_PORT=38427 node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-negative-access src/__rules__/v1_negative_access_rules.test.ts`
- Default command for a clean machine: `cd functions && node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-negative-access src/__rules__/v1_negative_access_rules.test.ts`
- Result (worktree head 722d4344 plus the uncommitted test and record changes): 1 suite passed, 140 tests passed, 0 failed, 0 skipped.
- Expected-policy inventory (hard-coded, ten names) matched the run-time parser output for the write list; `profile`, `body_scans` and the other excluded names have conditional client writes and are covered here for foreign/signed-out access, list, nested paths and owner nested writes; their owner-side behavior stays with firestore_rules.test.ts.
- Not covered: the full rules suite was not run (only this file); mutation checks were not run by operator policy; auth/e2e suites untouched.
