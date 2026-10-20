# Attributions: nutrition, food diary and body check-in

Created 2026-10-15 (story C24, design `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` section 17.9).
Source of the rows: `FINDINGS.md` of the food-reference research (2026-10-15). Licences below were read
from the upstream repositories or documentation on that date; nothing here is legal advice.

The app is distributed privately (operator, friends, family). Third-party open-source licences are therefore not
a blocker, but an attribution is mandatory for anything bundled, queried or copied. The in-app
"Data sources and limits" page (`/nutrition/sources`, `mobile/lib/features/nutrition_plan/plan_sources_page.dart`)
shows the same list in plain language; keep both in step.

| Component | Source | Licence | What is used | Repo location | Code copied? | Date |
|---|---|---|---|---|---|---|
| USDA FoodData Central (Foundation Foods, SR Legacy) | https://fdc.nal.usda.gov/ | CC0 1.0 (public domain) | Per-100 g energy and macros for the bundled generic table and the `searchFoods` USDA source | `mobile/assets/nutrition/generic_foods_v1.json`, `scripts/nutrition/build_generic_foods.py`, `functions/src/nutrition_sources/usda_fdc.ts` | No (data only) | 2026-10-15 |
| Open Food Facts (database) | https://world.openfoodfacts.org/ , terms https://world.openfoodfacts.org/terms-of-use | ODbL 1.0 (database), DbCL 1.0 (contents). Product images are CC BY-SA and are NOT used. Attribute as "Open Food Facts". | Product name, brand, per-100 g values and serving size through `lookupBarcode` and `searchFoods`, cached privately in `nutrition_cache` | `functions/src/nutrition_sources/open_food_facts.ts`, `functions/src/nutrition_lookup.ts` | No (data only) | 2026-10-15 |
| `mobile_scanner` | https://pub.dev/packages/mobile_scanner | BSD-3-Clause | Dependency: camera barcode decoding (ML Kit on Android, Apple Vision on iOS) behind `BarcodePort` | `mobile/pubspec.yaml`, `mobile/lib/features/food_diary/state/barcode_port.dart` | No (dependency) | 2026-10-15 |
| `calorie-tracker` (thanhphuong080199) | https://github.com/thanhphuong080199/calorie-tracker | MIT | Ideas only: structured JSON schema with per-item grams and confidence, per-item database lookup with a source tag, overall confidence plus assumptions. Re-authored for a server-side Vertex call; its client-side API-key call is NOT adopted | `functions/src/analyze_meal_photo.ts`, `functions/src/coerce_meal_analysis.ts` | No code pasted | 2026-10-15 |
| `calorie-count` (RohamAbootorabian) | https://github.com/RohamAbootorabian/calorie-count | Ambiguous (README says MIT, the LICENSE file carries template text) | Idea only: server-side clamping of model output and "the user's note is authoritative" prompt idea | `functions/src/coerce_meal_analysis.ts` | **Nothing copied** | 2026-10-15 |
| OpenNutriTracker | https://github.com/simonoppowa/OpenNutriTracker | GPL-3.0 | Design reference only (barcode check digit, Search-a-licious plus legacy fallback, circuit breaker, retry). Everything re-implemented from the public GS1 algorithm and the OFF documentation | `mobile/lib/features/food_diary/data/gtin_validator.dart`, `functions/src/nutrition_sources/open_food_facts.ts` | **Nothing pasted** | 2026-10-15 |
| Mifflin-St Jeor and Deurenberg equations | Published formulae (Mifflin et al. 1990; Deurenberg et al. 1991) | Published formulae, not copyrightable | Resting energy; provisional body-fat estimate | `mobile/lib/features/nutrition_plan/data/`, `mobile/lib/features/body_scan/data/provisional_estimator.dart` | No | 2026-10-15 |
| Nutrition5k | https://github.com/google-research-datasets/Nutrition5k | CC BY 4.0 | Evaluation pointer only; no data or model is bundled or used | none | No | 2026-10-15 |

## Notes

- Open Food Facts share-alike (ODbL) applies to public redistribution of a derived database. The cache in
  `nutrition_cache` is private and the app is privately distributed. Re-check this row before any public release.
- Meal and label photos are processed by the Vertex AI gateway and are not stored by the app (design section 17.2);
  that is a privacy statement, not an attribution, and lives in `public/privacy.html`.
- Adding a data source, a package that ships data, or copying code from any project requires a new row here in the
  same commit.
