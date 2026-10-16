# S02 test epic 8a: validator separator bound (A8)

## What
New `functions/src/__tests__/activity/remediation_a_validate_bound.test.ts`: comma filler beyond samples x 8 x kinds is rejected `too_many` before JSON.parse (spy), the bound itself passes the cheap check, large and normal valid payloads are accepted. The scaling-profile pin is owned by epic 8b.

## Why
Remediation A8 added the cheap pre-parse bound.

## Affected paths
- `functions/src/__tests__/activity/remediation_a_validate_bound.test.ts`

## Verification state
See `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
