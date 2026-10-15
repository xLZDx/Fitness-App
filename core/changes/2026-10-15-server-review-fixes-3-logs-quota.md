# Change record: server review fixes part 3 (export quota, log redaction)

## What changed
- `functions/src/account_export.ts`: continuation quota `PAGE_QUOTA_LIMIT` 400 -> 150 (P-7); failure logs no longer carry the uid or `String(err)`, they carry `errorCode` only (D-67).
- `functions/src/abuse_guard.ts`: `accountExport` and `accountExportPage` added to `REDACTED_QUOTA_ACTIONS` (D-67).
- `functions/src/ai_gateway.ts`: the generate-failed log carries an error code only, never `String(e)` (P-9).
- Tests updated: `account_export_paging.test.ts` (150/day), `abuse_guard.test.ts` (redacted set).

## Skipped
SF-F13: `writeCache` in `functions/src/nutrition_cache.ts` already catches every error and never throws, so a cache-write failure cannot fail or refund a successful lookup; no change.

## Why
Review findings P-7, P-9, D-67. Cloud Logging outlives `deleteAccount`, so logs must not name the user.

## Verification state
Not run (no tests, lint, tsc, build or CI executed).
