# S02 test epic 8a: withdrawal no-op, grant cancels the delete job, recompute termination (A11, A13, A16)

## What
New `functions/src/__tests__/activity/remediation_a_settings.test.ts`: the withdrawal-only short circuit (no transaction, no Auth lookup, no write, not metered), the six job fields cleared by a changed grant in the same write, and the recompute final pass for rows in every state with an older generation.

## Why
Remediation A11, A13 and A16.

## Affected paths
- `functions/src/__tests__/activity/remediation_a_settings.test.ts`

## Verification state
See `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
