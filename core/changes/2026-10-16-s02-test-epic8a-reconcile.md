# S02 test epic 8a: reconciler deadline, bulk-delete fairness, silent skips, abort re-read (A2, A3, A4, A14, A15)

## What
New `functions/src/__tests__/activity/remediation_a_reconcile.test.ts` (21 tests): continuation pass deadline and page budget, attempt-stamp ordering and stamps, start/done field handling, oldest bulk-delete age, unrecognised row ids, silent-skip counters, scan-cycle progress, and the abort path re-read of the pending row.

## Why
Remediation batch A changed these reconciler and bulk-delete paths; the notes list the behaviour each test asserts.

## Affected paths
- `functions/src/__tests__/activity/remediation_a_reconcile.test.ts`

## Verification state
See `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
