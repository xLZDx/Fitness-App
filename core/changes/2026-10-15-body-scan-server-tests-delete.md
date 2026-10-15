# C12 server tests: deleteBodyScan

Date: 2026-10-15. Test file only: `functions/src/__tests__/body_scan/delete.test.ts` (23 tests).

Covers: scanId and photosOnly validation (no default that could erase a scan), bodyScanDelete quota (limit 60), photosOnly keeps the estimate and marks photos deleted, the scrubbed 48 h `cancelled` tombstone (exact surviving key set, no metric/note left), tombstone written before the object delete (timeline order), a never-seen scan id still tombstoned and a later create refused, idempotent repeat, per-user and per-scan prefix isolation (trailing slash), object-delete failure (tombstone stays, log carries the error code only, retry finishes) and Firestore failure (objects untouched).

Verification: `npx jest src/__tests__/body_scan/delete.test.ts` in `functions/`: 23 passed, 0 failed. No production code changed.
