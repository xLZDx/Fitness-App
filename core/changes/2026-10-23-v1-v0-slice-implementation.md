# Change record: V0 slice implementation (2026-10-23)

Base: 19be451a (on cb2008c4). Implements slice V0 from docs/v1/design/V0_SLICE_PLAN_2026-10-23.md: one CompleteSet APPEND, local durable commit, server apply, lost ack, identical replay.

## What changed
- Server: callable `submitWorkoutCommands` (flag WORKOUT_COMMANDS_ENABLED, off by default) in functions/src/workout_commands/ (canonical.ts hashVersion-2 canonical JSON, fence.ts compact fence of 256 shards, types.ts, apply.ts: receipts, counters, typed session in one transaction; writer proof before generation checks; reserved ids rejected; lone surrogates rejected). One export line in functions/src/index.ts.
- Rules: firestore.rules carve-outs for workout_command_fence, _receipts, _policy, _counters, workout_typed_sessions (client access denied).
- Policy: scripts/ci/data_lifecycle_policy.json classifies the five new collections (BOTH is a label only until account_export has a section).
- Protocol: OFFLINE_COMMAND_PROTOCOL.md section 4.2 step 6 gets step a0 (writer proof first).
- Mobile: mobile/lib/features/workouts/offline/ (canonical, command record, result codes, queue store interface with file and in-memory stores, atomic temp+rename journal, logical_sets.json marker, sender with injected CommandTransport, status provider, CompleteSet acceptor, providers).
- Shared fixture docs/v1/fixtures/workout_command_golden_vectors.json (39 vectors) and functions/scripts/verify_workout_command_vectors.mjs.
- Tests: functions/src/__tests__/workout_commands, __e2e__/workout_commands.e2e.test.ts, __rules__/workout_command_carveout_rules.test.ts, mobile/test/features/workouts/offline.

## Affected contracts and paths
New callable and five server-only collections; no existing route, feature or deletion behaviour changed; no deployment performed.

## Verification state (test agents, working tree before this commit)
Node and Python vector verifiers 39/39; jest 268; rules 44; e2e 71; data lifecycle check OK; mobile offline tests 295. Four independent reviews done and their findings fixed. Not run: analyze, full suites, CI (by operator rule). Remaining before activation: account_export section for the five collections, GPT-PM gate on this head.
