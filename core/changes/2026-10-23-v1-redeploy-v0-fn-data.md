# Change record: V0 callable redeployed under fn-data, flag still OFF (2026-10-23)

Records the redeployment of submitWorkoutCommands after PR 34 (master 2b5e4695). Documentation only in this commit; details, ids and rollback: docs/v1/design/DEPLOY_V0_DEV_2026-10-23.md (section "Redeploy under fn-data").

## Result
- Function: ACTIVE, nodejs22, europe-west1, revision submitworkoutcommands-00002-red (previous revision submitworkoutcommands-00001-gib), serviceAccountEmail fn-data@fitness-app-korostelev.iam.gserviceaccount.com. WORKOUT_COMMANDS_ENABLED is absent from its environment: the feature is off. The other 43 functions are unchanged; the rules release is still 07f56cec-b834-48db-bb38-8fcd3ad703bf. No ERROR log entries for the service in the first 30 minutes after the deploy (the callable was not invoked).
- origin/phase1/main moved 9e6aeaa3 to 2b5e4695 (fast-forward).

## Deviation, with operator consent (2026-10-23, one deploy)
The full predeploy `npm test` was skipped again (unreliable on this machine, see the first deploy record); the release guard (PASS) and `npm run build` ran. The unit tests of V0 and scaling.test.ts were green on this code (jest 420, rules 44, e2e 75).

## Next
Enabling the flag for test accounts is a separate operator decision.
