# Food scanning: operator steps (flags are OFF by default)

Plan: C20, SD-2, SD-10, SD-15. Design: `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` sections 7.5, 17.3-17.6, D-63..D-67.

Nothing here is needed for the default build: with the flags unset every food callable answers
`failed-precondition: feature-disabled` and charges no quota.

## 1. Flags (server environment, `functions/.env.<project>`)

| Variable | Default | Turns on |
|---|---|---|
| `FOOD_AI_ENABLED=true` | off | `analyzeMealPhoto`, `parseNutritionLabel` (paid Vertex AI calls). Go-live gate: Q-6 privacy posture and data-notice text. |
| `FOOD_LOOKUP_ENABLED=true` | off | `lookupBarcode`, `searchFoods` (Open Food Facts and USDA). Go-live gate: Q-4 (below). |
| `OFF_CONTACT` | `contact-not-configured` | Contact in the mandatory Open Food Facts `User-Agent: FitnessApp/<version> (<contact>)`. Set a real mailbox or URL BEFORE enabling `FOOD_LOOKUP_ENABLED`. |
| `APP_VERSION` | `1.0` | Version token in that `User-Agent`. |

Only the exact string `true` enables a flag.

## 2. USDA FoodData Central key (Secret Manager)

1. Register a free key at https://fdc.nal.usda.gov/api-key-signup (about 1,000 requests per hour). The public `DEMO_KEY` is never used.
2. Create the secret `USDA_FDC_API_KEY` with the key as its value (never in code, config or a query string).
3. Grant `roles/secretmanager.secretAccessor` on THAT secret only to both identities that read it:
   - `fn-ai-runtime` (`analyzeMealPhoto` enrichment; the one recorded widening of D-63),
   - `fn-data` (`lookupBarcode`, `searchFoods`).
4. The code reads the secret at runtime (`projects/<project>/secrets/USDA_FDC_API_KEY/versions/latest`); an absent or unreadable secret is "USDA not configured": enrichment falls back to model values tagged `llm_estimate`, `lookupBarcode` uses Open Food Facts only, and `searchFoods` with `scope: "generic"` answers `failed-precondition: source-not-configured`.

## 3. Firestore

`nutrition_cache/{key}` is Admin-SDK-only (rules: deny all) and expires through the TTL policy on `expireAt` (C01, `firestore.indexes.json`). Budget counters `budget_off_read_<minute>` and `budget_off_search_<minute>` live in the same collection. The code compares `expireAt` itself, so a late TTL sweep is harmless.

## 4. Release guard

`analyzeMealPhoto` and `parseNutritionLabel` run as `fn-ai-runtime` and are part of the guarded AI set (6 callables). Deploy them by name only after the guard passes; `lookupBarcode` and `searchFoods` run as `fn-data` and are outside the AI guard set.

## 5. Monitoring follow-up

The `appcheck_attestation` log-based metric filter is generated from `APP_CHECK_KNOWN_CALLABLES`; the four new names were added to the source list. Re-apply that metric definition when deploying, otherwise the new callables are silently excluded from the attestation ratio.

## 6. Rollback

Unset the flag(s) and redeploy (or deploy without the functions). No data migration is involved; cache documents can be left to expire.
