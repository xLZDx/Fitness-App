# E0 tests, functions part (T02, T06..T11)

## What
- New `functions/src/__tests__/feature_flags.test.ts` (T02): `assertFeatureEnabled`, food flags (exact `true` only), body-scan bucket/provider readers (bucket-name validity table), `nutrition_budget` (10/6 per UTC minute, doc ids, 1-day TTL, fail-closed), `safeFetch`/`buildUrl` (encoding, host allowlist, redirects, body cap, timeout, slug-only errors).
- New `functions/src/__tests__/firestore_indexes_body_scan.test.ts` (T11): both body_scans COLLECTION_GROUP indexes, nutrition_cache TTL override, untouched legacy entries, firebase.json storage wiring, and a cross-check that every purge query has an index.
- Extended `abuse_guard.test.ts` (T08): 8 new QUOTAS exact values, `REDACTED_QUOTA_ACTIONS`, uid-free refusal/failure/refund log events (and unchanged shape for old actions), anonymous share. A `beforeEach(jest.clearAllMocks)` was added because the logger mock accumulates across isolated registries.
- Extended `ai_gateway.test.ts` (T09): six operations, food operations logged, `responseSchema` passthrough and byte-for-byte unchanged request for old callers.
- Extended `monitoring/__tests__/ai_gateway_definitions.test.ts` (T10): four -> six operations, 6x3 = 18 series, quota-exhaustion bound to six actions, non-AI actions excluded.
- Extended `scaling.test.ts` (T07): BODY_SCAN and FOOD_LOOKUP profiles, `fn-bodyscan` identity, App Check fail-closed AI flag, and registration of the six functions the C12 commit added (surface count test updated: twenty -> twenty-six).
- Extended `release_guard.test.ts` (T06): guard-set parity with the gateway, flag-gated body-scan bucket check (skip when unset, OK, every FAILED and UNAVAILABLE branch). The six-callable guard expectation is a `test.todo` deferred to C20/E5 because the food callables do not exist yet.

## Defect found and fixed (E0 code)
`functions/src/nutrition_http.ts` (C02): `buildUrl` percent-encodes every segment, but a bare `..` or `.` segment is not changed by encoding and the URL parser collapses it (`/fdc/../x` became `/x`), contradicting the module's own "a path segment stays one segment" contract. Fix: refuse a `.`/`..` segment with a new closed slug `upstream-invalid-request` (appended to `UPSTREAM_ERROR_SLUGS`). Regression tests are in `feature_flags.test.ts`.

## Paths
functions/src/nutrition_http.ts, functions/src/__tests__/{feature_flags,firestore_indexes_body_scan,abuse_guard,ai_gateway,scaling,release_guard}.test.ts, functions/src/monitoring/__tests__/ai_gateway_definitions.test.ts

## Verification
Each file was run on its own with `npx --no-install jest <file>` from `functions/` (see the final E0 evidence record for the complete-set run, counts and head).
