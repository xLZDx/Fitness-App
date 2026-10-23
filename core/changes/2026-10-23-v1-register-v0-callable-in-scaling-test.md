# Change record: register the V0 callable in the scaling test (2026-10-23)

Base: master aff06975. Slice V0 added the callable submitWorkoutCommands without registering it in functions/src/__tests__/scaling.test.ts, so the predeploy `npm test` of master failed and blocked the function deploy.

## What changed
- scaling.test.ts: submitWorkoutCommands added to ENTRYPOINTS; the test title now says "forty-two" (it said "thirty" while the list already held 41 entries). The function uses the RARE profile (europe-west1, maxInstances 5, no concurrency, no minInstances), so it meets every invariant the file enforces.

## Affected contracts and paths
Test registry only; no production code.

## Verification state (test agent)
scaling.test.ts: 150/150 pass. Not covered: discover_callables.ts scans a fixed file list that does not include workout_commands/apply.ts, so its App Check note does not cover this callable (it does not fail either).
