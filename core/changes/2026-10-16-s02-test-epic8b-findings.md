# S02 test epic 8b: findings and stale-test fixes

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`: epic 8b section with exact commands and results.
- `scripts/ci/test_check_data_access_policy.js` and `functions/src/__rules__/s02_activity_access_rules.test.ts`: two stale expectations updated (account_export residue lines; activity_account_state policy path).

## Why
The complete run exposed two expectations left behind by epic 6b. No product code changed.

## Verification state
Rules 289 passed, jest 191 passed, both policy self-tests exit 0 (see the findings file).
