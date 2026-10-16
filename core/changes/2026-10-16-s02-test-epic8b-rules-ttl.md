# S02 test epic 8b: primarySourceId rule test and TTL override checker

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/__rules__/s02_activity_source_id_rules.test.ts` (new, Firestore emulator): A12. Accepted: `Watch4`, `health-connect.v2:abc`, a 64-character id and others; denied at create and at update: `173.25`, `home 51.5007,-0.1276`, a space, a comma, a 65-character id, non-ASCII, a trailing newline and the empty string. Every denial has an accepted control at the same id.
- `scripts/ci/check_ttl_overrides.js` (new): exits 1 and names each missing `fieldOverrides` entry with `ttl: true` (`activity_tombstones.expireAt`, `accountDeletionRetries.expireAt`, `nutrition_cache.expireAt`). Its mutated-copy proof lives in `functions/src/__tests__/s02_remediation_a_policy.test.ts` (next commit).

## Why
Remediation A6 and A12 need executable proof; the TTL was previously a prose-only claim.

## Affected contracts and paths
Test files and one CI script only; no product code changed.

## Verification state
Rules test run on the emulator with ports 18080/19299: 45 passed. Quoted in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
