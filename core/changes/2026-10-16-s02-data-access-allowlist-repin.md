# Repin the data-access allowlist line for delete_all_streams

Date: 2026-10-16. Kind: tooling fix, one line.

## What changed
- scripts/ci/check_data_access_policy.js: the allowlist entry for functions/src/activity_streams/delete_all_streams.ts moves from line 201 to line 203.

## Why
Remediation J3a added an import and a guard block above the pinned `.collection(...)` call, shifting it by two lines. The checker reported a violation and three tests were red.

## Affected contracts and paths
None. Same call, same allowlist reason.

## Verification state
Not run by the coordinator. The test agents re-run s02_remediation_a_policy.test.ts and activity/lifecycle_policy.test.ts.
