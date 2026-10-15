# C12 server tests: guard preamble of the four callables

Date: 2026-10-15. Test file: `functions/src/__tests__/body_scan/guard.test.ts` (40 tests; one table run against createBodyScan, estimateBodyScan, deleteBodyScan, manageBodyScanData) plus a stricter schedule/options assertion in `purge.test.ts` (31 tests).

Covers per callable: control call reaches its own logic; no auth (unauthenticated, kill switch not read); anonymous (permission-denied before the kill switch); kill switch off and unreadable (unavailable, fail closed); bucket unset and malformed (feature-disabled); order kill switch before flag; every refusal leaves zero usage documents, zero Firestore writes and zero storage calls (flag-off charges no quota); App Check note under the callable's own name without a uid; endpoint options (fn-bodyscan identity, europe-west1, 10 instances; purge 300 s, 256 MiB, 1 instance, concurrency 1).

Verification: `npx jest src/__tests__/body_scan/guard.test.ts src/__tests__/body_scan/purge.test.ts` in `functions/`: 2 suites, 71 passed (guard 40, purge 31), 0 failed. No production code changed.
