# C12 server tests: estimate, validate_estimate, registry

Date: 2026-10-15. Scope: functional tests for `estimateBodyScan`, `validateEstimate`, the estimator registry and the server flags (C12 = 5d2c356). Uses the shared fakes from `core/changes/2026-10-15-body-scan-server-tests.md`.

## What changed (test files only; no production code touched)

- `functions/src/__tests__/body_scan/estimate.test.ts` (59 tests): provider input from the stored subject; stored estimate shape; retention 30/90/365 and 0 (inline delete, failed delete, failed follow-up update, failed settings read); done replay (no provider, quota, writes, storage reads); request/state errors; quota exhausted; lease (two concurrent calls make one provider call, live lease, expired takeover, 60 s lease, lease failure); racing delete/erasure; read-time upload checks (missing poses, size bounds, content type, PNG bytes, storage failure); provider failure, EstimatorTerminalError, 25 s timeout and timer cleanup, invalid output, final-transaction failure; log contains no uid/path/metric.
- `functions/src/__tests__/body_scan/validate_estimate.test.ts` (closed lists, bounds, de-duplication, extra keys dropped, id/version bounds).
- `functions/src/__tests__/body_scan/registry.test.ts` (licensed-api reserved, test-fake only in a test runtime, flag parsing).

## Verification state

Command (in `functions/`): `npx jest src/__tests__/body_scan/validate_estimate.test.ts src/__tests__/body_scan/estimate.test.ts src/__tests__/body_scan/registry.test.ts`. Result: 3 suites passed, 131 tests passed (estimate 59, validate_estimate + registry 72). Test defects fixed while writing: an unhandled early rejection of the lease loser (handlers now attached at once), a default-parameter slip in the validate helper.
