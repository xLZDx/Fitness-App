# C20: food scanning Cloud Functions

Plan: C20, SD-2, SD-10, SD-11, SD-15. Design: sections 7.5, 7.9, 17.3-17.6, D-27, D-28, D-63..D-67.

## What changed
New server modules under `functions/src/` (flat, next to the sibling `ai_*.ts` callables, as the design lists them in section 2.3; the coordinator brief said `functions/src/food/**`, see Deviations):

- Callables (all four exported from `functions/src/index.ts`, append only):
  - `analyze_meal_photo.ts` `analyzeMealPhoto` on `AI_METERED`; modes `photo` and `describe`; fixed prompt with caller text as quoted data only; `responseSchema` with the closed code enum; coercion, enrichment, recomputed totals.
  - `parse_nutrition_label.ts` `parseNutritionLabel` on `AI_METERED`; Gemini vision label read, deterministic post-step.
  - `nutrition_lookup.ts` `lookupBarcode` and `searchFoods` on `FOOD_LOOKUP`; cores `lookupBarcodeCore` and `searchFoodsCore` are exported for tests.
- Pure modules: `coerce_meal_analysis.ts` (parse, clamps, closed codes, recomputed totals, `itemMacros`, `sumMacros`), `nutrition_normalise.ts` (kJ to kcal, salt from sodium, Atwater sanity, OFF and USDA nutrient mapping), `label_normalise.ts`, `gtin_validator.ts`, `food_text.ts` (hostile-string sanitiser D-66 and prompt-char refusal), `food_types.ts` (closed code, source and match enums).
- Infrastructure: `nutrition_cache.ts` (`nutrition_cache/*`, expireAt compared in code, positive 30 d, negative 1 d, search 7 d), `nutrition_breaker.ts` (3 failures or one 429 opens for 5 min), `nutrition_config.ts` (`OFF_CONTACT`, `APP_VERSION`, `User-Agent`).
- Sources: `nutrition_sources/{open_food_facts,usda_fdc,search,enrich,match,types}.ts`. Every upstream call goes through the C02 `safeFetch`; OFF calls also take a slot from the C02 global budget; the USDA key is read from Secret Manager at runtime and sent in `X-Api-Key`.
- Release guard (D-63, SD-11): `AI_CALLABLES` 4 to 6, `AI_SOURCE_FILES`, the "4" strings in check names and details; `__tests__/release_guard.test.ts` names and source-path map; `__tests__/discover_callables.ts` sources; `monitoring/alert_definitions.ts` `APP_CHECK_KNOWN_CALLABLES` (+4 names, required by the existing parity test).
- `runbooks/food_lookup.md` (flags, USDA secret grants, monitoring follow-up).

## Flow and order
AI callables: auth, `noteAppCheck`, non-anonymous, `enforceAiGatewayEnabled`, `assertFeatureEnabled`, parse, quota; provider failure refunds. Lookup callables: auth, `noteAppCheck`, non-anonymous, `assertFeatureEnabled`, parse, cache read (a hit charges nothing), then on a miss: per-uid burst slot (5 per UTC minute, counter fields `offMissWindow`/`offMissCount` in the usage doc), daily quota, global OFF budget, upstream. An upstream failure refunds and is never negative-cached; a negative result IS charged and cached for one day.

## Deviations and decisions (recorded)
1. Layout: flat `functions/src/*.ts` plus `functions/src/nutrition_sources/` per design 2.3 and the plan C20 row, not `functions/src/food/`. The release guard paths, the coverage map file names and the sibling callables all assume the flat layout.
2. `lookupBarcode` and `searchFoods` do NOT call `enforceAiGatewayEnabled` (design 7.5 says "same order"): that kill switch guards paid Vertex calls, only `fn-ai-runtime` holds a grant on its secret, and on `fn-data` the call would fail closed forever. `FOOD_LOOKUP_ENABLED` and the global budget are their controls.
3. The USDA secret needs `secretAccessor` for BOTH `fn-ai-runtime` (enrichment) and `fn-data` (lookups); the design text named only the first. Operator step in the runbook.
4. The model response schema gains a boolean `packaged` per item so enrichment can route generic foods to USDA and packaged products to OFF (the design schema had no such signal). Absent means generic.
5. `searchFoods` with `scope: "generic"` and no USDA key answers `failed-precondition: source-not-configured` before charging anything (coverage FOOD-14); `both` skips USDA; enrichment never fails on a missing key.
6. Per-uid burst limit answers `unavailable: rate-limited` (retriable), not `resource-exhausted`, because the client treats `resource-exhausted` as "not until the next UTC day".
7. Enrichment does not apply the per-uid burst counter (it is covered by the `analyzeMealPhoto` daily quota and the global OFF budget).
8. Hostile-string sanitiser lives in `food_text.ts` and is used by the coercion, the sources and the search query, rather than inside `coerce_meal_analysis.ts` only. An item with no usable database match and no model values is returned with `per100g: null`, `source: llm_estimate`, codes `foodNotMatched` and `lowConfidenceItem` and zero macros.
9. No `core/ATTRIBUTIONS_NUTRITION.md` yet (the plan creates it with the client commit C24); attribution notes are in source comments (`coerce_meal_analysis.ts`, `open_food_facts.ts`, `usda_fdc.ts`) and returned in callable responses.

## Contracts affected
New callable contracts (see source for request/response shapes); `AI_CALLABLES` guarded set is 6; `APP_CHECK_KNOWN_CALLABLES` has 17 + 4 names; usage doc gains two numeric fields; `nutrition_cache` gains `off_*`, `q_*` documents.

## Verification state
NOT_RUN: nothing was compiled or tested (development rules v4). Not verified: TypeScript compilation of any new file, the Search-a-licious and legacy response field names (`hits[].nutriments`, `products[]`), the USDA `foodNutrients` per-100 g semantics for Branded foods, `@google/genai` accepting the `Schema` literal with the cast `Type` values, and the live Secret Manager access path.
