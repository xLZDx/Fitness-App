# Change record: account export for V0 collections (2026-10-23)

Base: 631279b2.

## What changed
- functions/src/account_export.ts: two new paged sections, workoutTypedSessions and workoutCommandReceipts, same paging, cursor and byte-budget behaviour as the existing paged sections; typed-session rows drop writerTokenHash (typedSessionRow, TYPED_SESSION_WITHHELD_FIELDS).
- scripts/ci/data_lifecycle_policy.json: typed sessions and receipts are BOTH and exported; fence, policy and counters are DELETE and not exported; reasons describe the real behaviour.
- scripts/ci/check_data_access_policy.js and test_check_data_access_policy.js: audited line pins for account_export.ts moved (234, 237, 323 to 253, 256, 343).
- functions/src/__tests__/account_export_workout_commands.test.ts: 24 tests (owner data, paging cursors, withheld field never leaks, tenant isolation, empty sections, byte budget, policy consistency).

## Affected contracts and paths
Account export output gains two sections for the requesting account only. No rules, callable or mobile change.

## Verification state (test agent)
Jest 5/5 suites, 83/83 tests; check_data_lifecycle_coverage.js OK; test_check_data_access_policy.js all cases pass. check_data_access_policy.js reports 5 unresolved calls in body_scan/manage.ts and nutrition_cache.ts, identical on pristine master 631279b2 (pre-existing, unrelated). Not run: full suites, CI.
