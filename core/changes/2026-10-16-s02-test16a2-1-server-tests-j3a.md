# S02 test epic 16a2 (1/2): server tests for remediation J3a

Date: 2026-10-16. Branch: phase2/s02-unified-activity. Base head: 7f15f7db.

## What changed

- `support/seven.ts`: the `getActivityStreamDownloadUrls` entry sends `expectedUid` via `withUid`; the `deleteAllActivityStreams` entry now passes its body (4th argument) with `expectedUid` (an undefined table body becomes `{ expectedUid: uid }`).
- Direct call sites updated for the key and the new argument order: `account_flow.test.ts`, `export_downloads_telemetry.test.ts`, `remediation_a_reconcile.test.ts`, `settings_consent.test.ts`, `sweeps_jobs.test.ts` (`lim(...)` moved to the 5th argument).
- `callable_hardening.test.ts`: the old assertion "deleteAll ignores the body" would now fail for the right reason (the body is refused); it now asserts `invalid_request` for a client body and keeps a control that the plain call still returns `done`.
- New `expected_uid_more_callables.test.ts`: for both handlers mismatch, mismatch beats invalid request and exhausted quota, anonymous gate first, malformed/missing key, non-object data, matching key, extra body key, onCall wrapper; plus the structural scan (every exported onCall handler except `sendDebugTelemetry` verifies before its first await) with a self-check on synthetic sources.

## Why

Remediation J3a bound the two remaining client-initiated callables to the initiating account; the tests had to follow and prove it.

## Affected contracts

Test code only. No product file changed.

## Verification state

Focused run green (7 suites, 321 tests). Broader run: see docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md, section "16a2 server (J3a)".
