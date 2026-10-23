# Change record: V0 deployed to the dev project with the flag OFF (2026-10-23)

Records the deployment of slice V0 to fitness-app-korostelev (region europe-west1). Documentation only in this commit; the deployment itself was done by the operator-authorised steps below. Details, ids and rollback commands: docs/v1/design/DEPLOY_V0_DEV_2026-10-23.md.

## What was deployed
- Firestore rules: master's full firestore.rules, ruleset 07f56cec-b834-48db-bb38-8fcd3ad703bf (identical to master's file). Previous ruleset eefbc179-7f92-4199-a163-828a7424d503 (2026-08-29), kept for rollback.
- Function submitWorkoutCommands, ACTIVE, nodejs22, europe-west1, revision submitworkoutcommands-00001-gib, maxInstances 5; WORKOUT_COMMANDS_ENABLED is not set, so the feature is off. The other 43 functions are unchanged. No IAM or service-account change.
- origin/phase1/main moved 03ea66e1 to aff06975 to 9e6aeaa3 (rollback: back to 03ea66e1).

## Deviation, with operator consent (2026-10-23)
The predeploy `npm test` (3759 tests) was skipped for this one deploy: two attempts failed (first a validation test under load, a flake that passed in the next run; then guard_scripts.test.ts failed on a git fixture command on Windows after 1599 s). guarded_deploy.mjs has no supported skip option, so a throw-away config (not tracked, saved outside the repo) kept the release guard (PASS, standalone and inside the deploy) and `npm run build` and dropped only `npm test`. The function's own tests were green on this code (jest 269, e2e 75, rules 44).

## Verification (read-only)
Function list matches the baseline plus the new function; no ERROR log entries in the first 15 minutes; the callable was not invoked. Not verified: the full unit suite on the deployed head.

## Open
The default Compute service account has no Firestore role: the service account for the function must be decided before the flag is enabled. Scheduler 403s left as they are (operator decision).
