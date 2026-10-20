# Change record: C02 functions-infra-and-flags (Body Scan + Nutrition Coach, epic E0)

## What changed
- `functions/src/scaling.ts`: `RUNTIME_SA.bodyScan` (`fn-bodyscan`, D-60); new profiles `BODY_SCAN` (maxInstances 10, fail-closed `APP_CHECK_ENFORCED_AI`, runs as `fn-bodyscan`) and `FOOD_LOOKUP` (maxInstances 10, fail-closed `APP_CHECK_ENFORCED_AI`, runs as `fn-data`, D-64).
- `functions/src/abuse_guard.ts`: `QUOTAS` gains eight names (`bodyScanCreate` 30, `bodyScanEstimate` 14, `bodyScanDelete` 60, `bodyScanManage` 30, `analyzeMealPhoto` 60, `parseNutritionLabel` 60, `barcodeLookup` 120, `foodSearch` 150). `REDACTED_QUOTA_ACTIONS` makes the quota log events (`QUOTA_EXCEEDED_EVENT`, `QUOTA_CHECK_FAILED_EVENT`, `QUOTA_REFUND_FAILED_EVENT`) omit the uid and replace `String(e)` with the error code for exactly those eight actions (D-67); log shape for every pre-existing action is unchanged.
- `functions/src/ai_gateway.ts`: `AI_GATEWAY_OPERATIONS` += `analyzeMealPhoto`, `parseNutritionLabel` (4 -> 6); `GenerateOptions.responseSchema?: Schema` pass-through to the model call (omitted by the four existing callables, so their request is unchanged).
- `functions/src/monitoring/ai_gateway_definitions.ts`: description/comment text updated (four -> six operations, 18 series). The label lists derive from the tuple, so no logic changed.
- NEW `functions/src/body_scan/flags.ts` (`bodyScanBucketName()`, `bodyScanCloudEnabled()`, `bodyScanProviderId()`: the one reader of `BODY_SCAN_BUCKET` / `BODY_SCAN_PROVIDER`, per-call, unset by default, malformed bucket name = not configured), NEW `functions/src/food_flags.ts` (`foodAiEnabled()`, `foodLookupEnabled()`: only the exact string `true` enables), NEW `functions/src/feature_flags.ts` (`assertFeatureEnabled(enabled)` throws `failed-precondition: feature-disabled`; to be called before any quota charge).
- NEW `functions/src/nutrition_http.ts` (`safeFetch`, D-65: `URL`/`URLSearchParams` encoding, host allowlist, same-host https redirects only, 5 s timeout, 1 MiB cap, closed `UpstreamError` slugs, injectable `fetch`) and NEW `functions/src/nutrition_budget.ts` (D-64: per-minute OFF read/search budget constants 10 and 6, document-id/expiry helpers, `takeUpstreamBudget` transaction on `nutrition_cache/budget_off_*`, fail-closed).
- NEW `runbooks/body_scan_bucket.md`: bucket, `fn-bodyscan` and `fn-account-delete` grants, env configuration, canary, rollback.
- `core/DECISION_LOG.md`: C02 entry.

## Why
Server-side groundwork that must exist before the callables (C12, C20): identities, ceilings, quota names, the flag readers and the single bucket-name source, the shared flag-before-quota guard, and the outbound/budget helpers that every food callable has to use.

## NOT touched on purpose (SD-11)
`release_guard.ts` and `__tests__/discover_callables.ts` (they would reference callables that do not exist yet; C12 and C20 update them), `index.ts` and `sweepAccountData` (storage step lands in C12 with `bodyScanBucketName()` already available here). Test files were not edited; existing tests that hard-code four AI operations or the old monitoring text (`ai_gateway.test.ts`, `ai_gateway_definitions.test.ts`) will fail until the test phase updates them (coverage-map T09, T10).

## Affected contracts
`RUNTIME_SA` shape (+1 key), `QUOTAS` (+8 keys), `AiGatewayOperation` union (+2), `GenerateOptions` (+1 optional field), new env vars `BODY_SCAN_BUCKET`, `BODY_SCAN_PROVIDER`, `FOOD_AI_ENABLED`, `FOOD_LOOKUP_ENABLED` (all default off). No function is added or redeployed with a new identity by this commit.

## Verification state
Not run, per DEVELOPMENT RULES v4. Not compiled: in particular the `Schema` import from `@google/genai` and the `fetch`/`Response` DOM types under the existing tsconfig are unverified (`node_modules` is not installed in this worktree).
