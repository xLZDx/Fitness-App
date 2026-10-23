# Change record: run the V0 callable under the fn-data service account (2026-10-23)

Base: master 7df071c9. The deployed submitWorkoutCommands runs under the default Compute service account, which has no Firestore role: harmless with the flag off, a failure with the flag on (environment preparation report, decision on the service account).

## What changed
- functions/src/workout_commands/apply.ts: the callable options are now { ...RARE, serviceAccount: RUNTIME_SA.data }, the same pattern as account_export.ts. fn-data@fitness-app-korostelev.iam.gserviceaccount.com ("low-risk data functions") already holds roles/datastore.user (read-only check), so no IAM change and no new account.
- functions/src/__tests__/workout_commands/apply_pure.test.ts: one assertion on the callable's endpoint metadata (serviceAccountEmail is fn-data, not fn-ai-runtime; region europe-west1).

## Affected contracts and paths
One callable's runtime identity. The deployed function is NOT updated by this change; it needs a redeploy (a separate, operator-consented step).

## Verification state (test agent)
Node vector verifier 39/39; jest (workout_commands tests plus scaling.test.ts) 420 passed; rules 44; e2e 75. Not run: the rest of the functions suite, the Python vector cross-check, the data lifecycle checker, CI, a live call.
