# Change record: server review fixes part 2 (tests for part 1, bucket runbook)

## What changed
- `runbooks/body_scan_bucket.md`: section 7 rewritten (rollback = `BODY_SCAN_ACCEPT_UPLOADS=false`, never unset the bucket while objects exist); new section 8 (deploy storage rules separately, DB-F9); section 3 documents the new switch.
- `functions/src/__tests__/body_scan/guard.test.ts`: erase callables ignore the kill switch; `BODY_SCAN_ACCEPT_UPLOADS=false` gates only create/estimate.
- `purge.test.ts`: new cases for the path guard (P-1), failed-scan purge (DB-F1/P-3), erase with intake off (P-2), mid-page deadline token (DB-F3), abandoned count (DB-F4).
- `estimate.test.ts`: consent re-check (P-4), attempt cap (P-8), failed marker release must not refund (SF-F7); the inline-delete update-failure case now fails the second update.
- `create.test.ts`: reissue extends `pendingExpiresAt` and is capped at 5 (DB-F8, P-5); reset clears counters.

## Why
Tests for the behaviour changed in `core/changes/2026-10-15-server-review-fixes-1.md`.

## Verification state
Not run. Separate test agents execute them.
