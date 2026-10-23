# Change record: account export for V0 collections (2026-10-23)

Base: 631279b2. Updated after gate round 1 (receipts are no longer exported; the fence outcomes are).

## What changed
- functions/src/account_export.ts: two new paged sections, workoutTypedSessions (writerTokenHash withheld on every page) and workoutCommandOutcomes (the replay fence by shard: rows {id, entries:[{operationKey, code, sessionDigest}]}, payload-hash prefix withheld, malformed entries listed with null code). Both are read by boundedRead: 20 documents per batch, stop at the row limit or when serialized bytes would exceed MAX_EXPORT_BYTES, cursor = id of the last included row, a single oversized document is emitted alone.
- scripts/ci/data_lifecycle_policy.json: workout_typed_sessions BOTH (exported); workout_command_fence BOTH (exported as workoutCommandOutcomes); workout_command_receipts DELETE (90-day response cache, lifetime outcome is in the fence); workout_command_policy and workout_command_counters DELETE.
- scripts/ci/check_data_access_policy.js and test_check_data_access_policy.js: audited line pins for account_export.ts moved to 373, 376, 461.
- functions/src/__tests__/account_export_workout_commands.test.ts: 30 tests.

## Why (GPT-PM gate round 1, three MAJOR)
Receipts can reach 180,000 per account (2,000 per day, 90 days) while the mobile collector stops after 50 pages of 500, so a receipts export was silently incomplete; the fence keeps a permanent per-operation outcome that the owner could not export; the typed-session query read up to 501 full documents into memory before the byte budget applied.

## Affected contracts and paths
Account export output: two sections for the requesting account only. No rules, callable or mobile change.

## Verification state (test agent)
Jest 5/5 suites, 89/89 tests; check_data_lifecycle_coverage.js OK; test_check_data_access_policy.js all cases pass; check_data_access_policy.js reports the 5 known unresolved calls in body_scan/manage.ts and nutrition_cache.ts, identical on pristine master 631279b2. Not run: full suites, CI.
