# Change record: C01 rules-and-indexes (Body Scan + Nutrition Coach, epic E0)

## What changed
- `firestore.rules`: the seven new per-user collections (`body_scans`, `body_scan_settings`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`) are carved out of the `users/{uid}/{coll}/{document=**}` wildcard in BOTH the read and the write condition, and each gets its own shape-validating block (design s6.1b): server-authored `body_scans` (client may only edit `weightKg`/`clientNote`, judged on `affectedKeys()`), the fixed `cloudConsent` rule (D-56), plan/review enums without `referProfessional` plus `planVersion` / `reviewUndo` / `basePlanVersion` (D-55, D-57), food/saved-food shape checks (D-68). `flagsAreStripped` accepts and zero-checks `nutritionGuidance` / `foodAllergens` null-safely (D-70). The profile write gains a null-tolerant `nutritionOk` check whose allowlist excludes `excludedFoods` (device-only, D-55). `nutrition_cache` and `body_scan_purge_state` are deny-all. The comment block above the wildcard names the new carve-outs.
- `storage.rules` (new): deny-all for the default bucket. `firebase.json`: `storage.rules` entry and a Storage emulator entry (port 9199) - test-infrastructure prerequisite TI-2.
- `firestore.indexes.json`: two COLLECTION_GROUP composite indexes on `body_scans` (`photosState, photosExpireAt`; `status, pendingExpiresAt`) and a TTL field override on `nutrition_cache.expireAt` (also covers the upstream-budget counters stored in the same collection).
- `functions/scripts/run_emulator_tests.js`: arguments after the project id are forwarded to the inner jest command (TI-1); behaviour without extra arguments is unchanged.
- `core/DECISION_LOG.md`: SD-2, rollout order, C01 deviations.

## Why
Without the wildcard exclusions the explicit blocks would be dead (Firestore allows a request if any matching rule allows it), and `body_scans` would be client-forgeable. The profile rules must accept the new flag/`nutrition` shape before the client emits it.

## Affected contracts and paths
Rules grants for the paths above; default Storage bucket becomes deny-all (verify nothing public depends on it before deploying); emulator test runner CLI. Parser constraints of `scripts/ci/lib/rules_parser.js` were respected (one `allow` per verb per block, single-line `match` headers, no braces or `allow` text inside match bodies).

## Deviations (also in DECISION_LOG)
Per-element numeric checks of `food_entries.items` are not in rules (expression budget); policy JSON rows stay in C25, so coverage-map T05/RULES-14 cannot pass at gate G0; forwarded jest args must not contain spaces.

## Verification state
Not run, per DEVELOPMENT RULES v4. Rules never compiled or exercised in the emulator.
