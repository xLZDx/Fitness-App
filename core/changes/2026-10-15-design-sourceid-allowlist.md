# Design fix: llm_estimate in the FoodItem sourceId allowlist

- What: section 5.6 of the tech design listed sourceId as usda_fdc|open_food_facts|user|label_ocr; llm_estimate was missing although 17.3 and FOOD-09 require model-estimated items to carry it.
- Why: the C22 test agent found the mismatch (food_source_test pins it); the doc line was stale, the data layer is correct.
- Paths: core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md (one line).
- Contracts: no code or rules change; firestore.rules foodItemAt does not restrict sourceId.
- Verification: doc-only; the C22 food_source_test (246 C22 tests green) pins the wire ids.
