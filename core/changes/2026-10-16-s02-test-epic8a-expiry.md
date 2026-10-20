# S02 test epic 8a: commit expiry race and download expiry (A7)

## What
New `functions/src/__tests__/activity/remediation_a_expiry.test.ts`: the expiry falling due between commit transactions 1 and 2 (callable and reconciler repair path, never-stored and stored rows), and the download URL answer for a stored row whose derived expiry is due.

## Why
Remediation A7 added the transaction 2 refusal and the download expiry check.

## Affected paths
- `functions/src/__tests__/activity/remediation_a_expiry.test.ts`

## Verification state
See `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
