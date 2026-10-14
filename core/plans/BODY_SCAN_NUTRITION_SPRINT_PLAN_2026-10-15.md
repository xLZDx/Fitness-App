# Body Scan + Nutrition Coach - sprint plan

**Status:** PLAN v1, ready for implementation by agents without further questions. Date 2026-10-15. Branch `feature/body-scan-nutrition-coach` (worktree `D:\Repo\Fitness_App_bodyscan`), base `master` `42d1b84`, planning HEAD `64adc51`. ONE sprint, ONE pull request.

**Governing documents (in this order of precedence for this sprint):**
1. `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` (the design; sections 0-31 and decisions D-1..D-36). Cited below as `design sN` / `D-n`.
2. `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` (everything NOT built here).
3. Operator scope changes of 2026-10-15: food scanning (meal photo, barcode, label OCR, text search, diary, "Check these" chips) is IN; the multi-sport/device FOUNDATION (design s31) and the nutrition-aware programme hook (design s30) are IN as minimal foundations; full versions are Phase 2.
4. DEVELOPMENT RULES v4 (workspace `CLAUDE.md` / `AGENTS.md` and the global contract). Where the repo `AGENTS.md` still says "run `flutter analyze` + `flutter test`", v4 overrides it for this sprint (section 6 below).

**Conventions.** `VERIFY` = the implementer reads the named file before coding and follows what it really contains (the design lists these). `NOT_RUN` = deliberately not executed. Sizes: S < 200 changed lines, M 200-600, L 600-1,500, XL > 1,500 (generated l10n output excluded). All git content (code, comments, docs, commit messages, change records) is English; l10n RU strings are product content, not git prose.

## 1. Sprint decisions (new here; design decisions D-1..D-36 stay as written)

Recorded in `core/DECISION_LOG.md` by the commit named in brackets.

| ID | Decision | Why |
|---|---|---|
| SD-1 | One PR, about 30 coherent commits ordered so every commit is self-consistent by reading (pure `data/` first, then state, then UI; a UI commit never references a symbol created in a later commit). | No analyzer or compiler is run while coding (v4), so ordering is the only guard against a broken intermediate tree. |
| SD-2 | Operator-blocked infrastructure is feature-flagged OFF in code (section 4). Flags are compile-time (`--dart-define`) on the client and environment variables on the server, default `false`; every flagged path degrades to a documented working fallback. Nothing in the default build depends on an operator action. [C02, C03] | Q-4/Q-5/Q-6/Q-10 are operator-only. |
| SD-3 | l10n keys (EN + RU ARB) are added in the SAME commit as the UI that uses them, so no commit references a missing key. E7 is the final parity/plural/a11y audit, not the place strings are first written. | Same reason as SD-1. |
| SD-4 | No new Dart package is added unless a `VERIFY` proves it absent AND no existing package can do the job. Fallbacks fixed in advance: `connectivity_plus` absent -> retry timer plus foreground resume (design s10 already allows it); `dio` absent -> existing HTTP client (`http` or `dart:io`) for the signed-URL PUT; `image` absent -> STOP and record as a blocker (blur cannot ship without it). `mobile_scanner` is already declared (design s17.4, VERIFY version). | Avoid dependency churn and `pubspec.lock` conflicts. |
| SD-5 | No generated code in new files (no `freezed`, no `json_serializable`, no Riverpod codegen); hand-written value classes with tolerant `fromJson`/`toJson`, as the neighbouring `data/` files do (VERIFY `core/CONVENTIONS.md`). | `build_runner` is a build step and is prohibited while coding. |
| SD-6 | `sweepAccountData` storage purge is a logged no-op when `BODY_SCAN_BUCKET` is not configured, and throws (so the durable reconciler retries) when it is configured and the delete fails. [C25] | Design s7.6 says "throws on failure"; an unconfigured bucket is not a failure, it means nothing could have been stored. |
| SD-7 | The programme hook (C09) is wired as an optional neutral-default parameter ONLY if the builder seam is a small change (design s30.4); otherwise the sprint ships the pure function and the provider, and the wiring is recorded as deferred to Phase 2 epic E9. The decision is taken by the implementer after the VERIFY and written in the C09 change record. | Design s30.4 already allows both. |
| SD-8 | `core/INDEX.md` is the document registry for this repo (hand-maintained; there is no generator and no `governance/DOCUMENT_REGISTRY.md`, see the design change record). New docs are registered there in the commit that creates them. | Repo convention. |
| SD-9 | The weekly review has ONE decision path (design s15); the post-scan "plan decision" calls the same pure function. The result screen reads it through `scanPlanDecisionProvider`, which C15 defines as returning `null` ("no plan decision yet") and C19 replaces with the real implementation. | Lets C15 land before C19 without a dangling reference. |
| SD-10 | Meal photos, label photos and describe text go to Vertex AI only when `FOOD_AI` is on; with it off the diary still works through bundled search, quick log, saved foods and (with `FOOD_LOOKUP`) barcode. | Q-6 posture covers photo, text and label alike. |

## 2. Repo facts the plan relies on

FACT (from design s2, read at base commit): the local scan stack under `mobile/lib/features/progress_photos/scan/` exists and is extended, not rewritten; health answers are device-only (`firestore.rules` `healthIsStripped` / `flagsAreStripped`, fail-closed on unknown keys); the `users/{uid}/{coll}/{document=**}` wildcard must be carved out for every new collection; account deletion is `sweepAccountData` + `recursiveDelete(users/{uid})`; export is `account_export.ts`; lifecycle governance is `core/DATA_INVENTORY_2026-08-11.{md,csv}` + `scripts/ci/data_lifecycle_policy.json`; the exhaustive `switch` in `onboarding/data/step_answered.dart` forces a case for every new `OnboardingStep`; there is no `storage.rules` today.

The design change record `core/changes/2026-10-15-body-scan-nutrition-design.md` and the DECISION_LOG entries for D-1..D-36 already exist (design commit). Implementation commits add entries only for NEW durable decisions (SD-n above, flag defaults, VERIFY outcomes that change the design).

## 3. Epics, stories, files, commits

Epic numbering is thematic; commit numbering (C01...) is the execution order. Every commit includes `core/changes/<date>-<slug>.md` (what, why, affected contracts/paths, verification state = "not run, per DEVELOPMENT RULES v4" until the test phase) and the commit message links it. `<date>` is the actual commit date. Every commit message ends with the attribution trailer required by the session. Each commit's paths are staged explicitly (never `git add -A`; concurrent sessions share checkouts).

### E0. Rules, infrastructure prerequisites and flags

| Commit | Content | Size |
|---|---|---|
| **C01** `rules-and-indexes` | `firestore.rules`: wildcard carve-outs in BOTH read and write conditions for `body_scans, body_scan_settings, weight_entries, nutrition_plan, nutrition_plan_reviews, food_entries, saved_foods`; the new blocks (design s6.1 table); `flagsAreStripped` extended with `nutritionGuidance`/`foodAllergens`; profile `nutrition` key allowlist (s6.1d); `nutrition_cache` deny-all; comment block above the wildcard updated. NEW `storage.rules` (deny-all); `firebase.json` (`storage` block + emulator entry); `firestore.indexes.json` (two collection-group composite indexes on `body_scans`, `nutrition_cache.expireAt` TTL field override). DECISION_LOG: SD-2, rollout order "rules before client". | M |
| **C02** `functions-infra-and-flags` | `functions/src/scaling.ts` (`BODY_SCAN`, `FOOD_LOOKUP` profiles, `RUNTIME_SA.data`); `abuse_guard.ts` `QUOTAS` (+7 names, design s7.5/5.8); `ai_gateway.ts` (`GenerateOptions.responseSchema?` pass-through, `AI_GATEWAY_OPERATIONS` += `analyzeMealPhoto`, `parseNutritionLabel`); `monitoring/ai_gateway_definitions.ts`, `release_guard.ts` callable list, `__tests__/discover_callables.ts` expectations updated by reading (not run); NEW `functions/src/body_scan/flags.ts` + `functions/src/food_flags.ts` (env readers: `BODY_SCAN_BUCKET`, `BODY_SCAN_PROVIDER`, `FOOD_AI_ENABLED`, `FOOD_LOOKUP_ENABLED`, all default off/unset) and a shared `assertFeatureEnabled(flag)` that throws `failed-precondition: feature-disabled`; NEW `runbooks/body_scan_bucket.md` (operator steps, design s6.3). | M |
| **C03** `client-flags-and-gates` | NEW `mobile/lib/core/config/body_scan_flags.dart` (`BodyScanFlags {cloudPhotos, foodAi, foodLookup}` from `bool.fromEnvironment('BODY_SCAN_CLOUD'|'FOOD_AI'|'FOOD_LOOKUP')`, exposed through a Riverpod provider that tests override); `subscription/data/feature_gates.dart` gets one entry per feature (body-scan keeps the existing gate, all others ungated, D-26 / Q-2 default). VERIFY the file shape and the config folder naming first. | S |

Stories: E0-S1 rules cannot be bypassed by the wildcard; E0-S2 default Storage bucket denies all client access; E0-S3 server quotas/profiles/operations registered; E0-S4 every operator-blocked capability has a flag, a default, and a fallback.
DoD E0: rules text matches design s6.1 row for row; flags default off; no code path other than the flag readers reads an env var.

### E1. Pure-Dart domain (no Flutter imports; host-testable)

| Commit | Content (paths under `mobile/lib/features/`) | Size |
|---|---|---|
| **C04** `profile-model-nutrition-prefs` | `profile/data/profile_models.dart`: `NutritionPrefs`, `SexAtBirth`, `DietaryPreference.pescatarian`, `UserProfile.nutrition` (default `NutritionPrefs.empty`), tolerant `fromJson` (unknown enum -> null) / `toJson` / `copyWith`; the Firestore repository `_fromMap`/`_toMap` (VERIFY both, and VERIFY that `saveDraft` preserves `completedAt`); `safety/data/health_flags.dart`: `NutritionGuidanceNeed`, `FoodAllergen` (EU-14), `HealthFlags.nutritionGuidance`/`foodAllergens` incl. `isUnanswered`/`isEmpty`/`==`/`hashCode`/`toJson`/`fromJson`/`copyWith`. This commit lands AFTER C01 so profile saves are never refused. | M |
| **C05** `nutrition-maths-and-eligibility` | `nutrition_plan/data/`: `nutrition_inputs.dart`, `weight_entry.dart` (weight series helpers), `series_math.dart` (shared irregular-interval EWMA and Theil-Sen slope primitives; `body_scan/data/scan_trend.dart` imports it in C07, which is the dependency direction allowed by design s4: `body_scan -> nutrition_plan/data`), `energy_math.dart`, `safety_clamps.dart` (every constant named, design s13.6 table), `plan_calculator.dart` (`PlanBounds`, `NutritionPlan`, macros, steps goal, realistic-pace helper used by onboarding), `nutrition_eligibility.dart` (design s14 order), `missing_inputs.dart` (`missingNutritionInputs(profile)`). | L |
| **C06** `weekly-review-logic` | `nutrition_plan/data/weekly_review.dart` (`ReviewInput`, `WeeklyReviewDecision decide(...)`, closed `ReviewReason` codes, ownership application, `clampToBounds` last). | M |
| **C07** `body-scan-data-layer` | `body_scan/data/`: `body_fat_estimate.dart`, `body_scan_entry.dart`, `scan_trend.dart` (irregular EWMA tau 21 d, winsorise +-4, noise threshold, 4-week label), `scan_result_math.dart`, `plausibility.dart`, `check_items.dart` (closed `CheckCode`), `face_region.dart` (head box, crown fallback, fail-closed verdict), `body_scan_job.dart` (status + backoff), `body_scan_flow_machine.dart` (design s10 table, pure), `body_scan_repository.dart` (interface only). | L |
| **C08** `activity-foundation` | NEW `activity/data/`: `sport_type.dart`, `activity_session.dart`, `activity_summary.dart`, `sample_stream.dart` (strictly increasing offsets, canonical SI units), `lap.dart`, `source_record.dart`, `device_source.dart` (`DeviceSource`, `SourceKind`, `SourceCapabilities`, `SourcePermission`, `LiveSample`), `merge_policy.dart`, `activity_merger.dart` (design s31.3 rules 1-6, deterministic, order-independent), `fake_device_source.dart` (lives under `activity/data/` because tests import it; no Flutter imports). Tolerant JSON with unknown-field passthrough. No UI, no persistence, no adapters. | L |
| **C09** `nutrition-aware-programme-hook` | `nutrition_plan/data/nutrition_training_state.dart` (design s30.2-30.3, rules 1-9, closed `TrainingNutritionReason`); `nutrition_plan/state/nutrition_training_advice_provider.dart` is created in C18 (needs plan providers) - C09 contains only the pure file plus, per SD-7, the optional neutral-default parameter on the programme builder (VERIFY `features/programmes/` and `suggestion_builder.dart`; combine with `AgeBand.intensityCap`, screening ceiling and injury filter by taking the MORE conservative value; injury filter untouched). | M |

Stories: E1-S1 nutrition maths + clamps (BMR, factors, TDEE, rates, floor, deficit/surplus caps, BMI guards, range and bounds); E1-S2 macros and steps goal; E1-S3 eligibility verdict and neutral behaviour contract; E1-S4 weekly review decision; E1-S5 trend smoothing, noise threshold, plausibility, check codes; E1-S6 scan flow state machine and job backoff; E1-S7 face-region geometry; E1-S8 activity model + merger + capability interfaces; E1-S9 training-from-nutrition advice.
DoD E1: no file imports `package:flutter`; every number is a named constant with its provenance tag (PUB/OWN/OBS) in a doc comment matching design s29; unit-level seeds of design s28 are all expressible against these APIs without mocks.

### E2. Onboarding diff, complete-your-nutrition-profile flow, migration-safe defaults

| Commit | Content | Size |
|---|---|---|
| **C10** `onboarding-nutrition-step` | `onboarding/data/step_answered.dart` (`OnboardingStep.nutrition`, `kOnboardingOrder` after `lifestyle` and before `healthFlags`, `isOnboardingStepAnswered` case, `onboardingResumeIndex` untouched logic); NEW `onboarding/steps/step_nutrition.dart` (sex at birth, goal direction with derived default, target body-fat / target weight with realistic-pace message from `plan_calculator`, typical steps bucket, optional `HealthSyncCard`, allergens, excluded foods, meals per day, ownership; every field optional); `steps/step_health_flags.dart` (+ `nutritionGuidance` question; widen the existing guidance wording to name breastfeeding - VERIFY current EN/RU `healthStepProfessionalGuidance`); `steps/step_lifestyle.dart` (+ pescatarian chip); `state/questionnaire_notifier.dart` (`updateNutrition`, allergens through the `HealthFlags.copyWith` path); ARB keys `onbNutrition*` EN + RU (SD-3). | L |
| **C11** `nutrition-profile-flow` | NEW `nutrition_plan/nutrition_profile_flow_page.dart` (three sheets driven by `missingNutritionInputs`, reuses the C10 widgets and notifier methods, saves through the profile repository); routes `/nutrition/profile` in `core/router/app_router.dart` (route table also gets the other `/nutrition*` and `/body-scan*` paths pointing at pages created in later commits ONLY as each page lands: this commit adds just `/nutrition/profile`). ARB keys. | M |

Stories: E2-S1 new users answer only what is missing, skippable, defaults visible; E2-S2 existing completed users are never routed back to `/onboarding`; E2-S3 old profile JSON round-trips without `nutrition`/new flag keys; E2-S4 unanswered safety questions lock the coach, not assume clear.
DoD E2: `redirectFor` untouched; resume index consistent with the new step; no analytics SDK added; step state stays "touched" only.

### E3. Body scan on the existing progress_photos/scan stack

| Commit | Content | Size |
|---|---|---|
| **C12** `body-scan-functions` | `functions/src/body_scan/{estimator,provisional_estimator,validate_estimate,create,estimate,delete,purge}.ts` (design s7.1-7.4, s8; `FakePhotoEstimator` test-only under `functions/src/__tests__/helpers/`), wired in `functions/src/index.ts` exports; every callable first calls `assertFeatureEnabled` only where a flag applies (the provisional path needs none; the signed-URL path requires `BODY_SCAN_BUCKET`); structured log event without uid or metrics. | L |
| **C13** `scan-record-v2-and-capture` | `progress_photos/scan/scan_models.dart` (`ScanRecord` v2, tolerant of v1: legacy scans never auto-uploaded, D-6), `scan_store.dart` (unchanged format, new fields), `ui/scan_ports.dart` (`ScanCamera.luminance`), `ui/scan_capture_screen.dart` (pop with scan id, skeleton overlay, luminance, `manualOverride`, four-row status panel); NEW `body_scan/widgets/skeleton_overlay.dart`, `setup_status_panel.dart`. VERIFY the camera luminance source (`core/camera/frame_brightness.dart`) and the landmark mapper/projection helpers. ARB keys. | L |
| **C14** `body-scan-state-and-pipeline` | `body_scan/state/`: `body_scan_providers.dart`, `body_scan_job_runner.dart` (foreground/connectivity resume, one scan at a time, `accountChanged()` fence), `blur_service.dart` (isolate, pixelate + box blur, re-encode, `<= 3 MB`), upload port + implementation, `BodyScanApi` callable client, Firestore `BodyScanRepository` implementation + in-memory fake, `bodyScanSettingsProvider`, `weightEntriesProvider` + weight repository (Firestore + fake), `scanTrendProvider`. The cloud upload branch is reachable only when the server reports `requiresPhotos` AND `BodyScanFlags.cloudPhotos` is on. | L |
| **C15** `body-scan-flow-and-result` | `body_scan/body_scan_flow_page.dart`; widgets `intro_view`, `weight_prompt_sheet`, `analysis_progress_view` (named stages, elapsed time, live region, Cancel first in focus order), `result_view` (range, provisional banner, plain-language limit, change label, points to goal, fat/lean mass, weight trend, strength sessions card), `trend_chart` (dots + smoothed line + data-table alternative), `check_items_card`, `cloud_consent_sheet` (shown only when provider needs photos); `scanPlanDecisionProvider` returning `null` (SD-9); routes `/body-scan`, `/body-scan/result/:scanId`. ARB keys. | XL |
| **C16** `body-scan-history-compare-privacy` | `widgets/scan_history_list.dart` (baseline marker, trend label), `progress_photos/scan/ui/scan_compare_screen.dart` (initial selection `?mode=baseline|previous`, second-scan prompt when only baseline exists), delete-this-scan's-photos (`deleteBodyScan(photosOnly)` then existing `confirmAndDeleteScan`; offline -> `pendingRemoteDelete`), edit recorded weight (updates only `weightKg`, re-derives fat/lean on the client), `retention_settings_view.dart` + `/body-scan/privacy` + `/body-scan/history`. ARB keys. | L |
| **C17** `scan-reminder-weekly-and-entry-cards` | `progress_photos/scan/scan_reminder.dart` (weekday/time rule, default Sunday 08:00, next fire strictly after `max(now, newestScan + 5 days)`, `body_scan_settings/main.reminder` plus the v1 SharedPreferences bool as fallback, same notifier and `kScanReminderId`), reminder editor (weekday chips + time picker), `body_scan/widgets/body_scan_entry_card.dart`, mounted on `progress/progress_page.dart` and a compact Home card in `home/`; `scan_entry_card.dart` routes into the new flow. Notification-tap routing: VERIFY `LocalNotificationService`; if absent, opening the app is the documented limit. ARB keys. | M |

Stories: E3-S1 guided three-pose capture with live Distance/Lighting/Position/Pose checks and gated auto shutter; manual shutter always available and recorded; E3-S2 consent (only if provider needs photos) and on-device face blur fail-closed; E3-S3 staged analysis with cancel, retry, backoff, resume after kill, offline queue; E3-S4 result with range, noise-aware change label, provisional banner; E3-S5 history/compare/delete/edit weight; E3-S6 weekly reminder; E3-S7 entry cards.
DoD E3: with the provisional provider no photo leaves the device and no cloud consent is shown; every displayed estimate carries range + model id/version + limit text; server-authored fields cannot be written by the client (rules from C01); `ScanRecord` v1 files still load.

### E4. Nutrition plan UI and weekly review

| Commit | Content | Size |
|---|---|---|
| **C18** `nutrition-plan-state` | `nutrition_plan/state/`: `nutrition_providers.dart` (`nutritionInputsProvider`, `nutritionEligibilityProvider`, `nutritionPlanProvider`, `weeklyReviewProvider`), `plan_repository.dart` (Firestore `nutrition_plan/main` + `nutrition_plan_reviews/{isoWeek}`, in-memory fake, bounds re-validated on every read and write), `review_scheduler.dart` (once per ISO week on first Plan/Home display and right after a scan reaches `done`; idempotent by week key), `nutrition_training_advice_provider.dart` (C09 function over live inputs), real `scanPlanDecisionProvider` override target. HealthService is read only through the existing seam (14-day median steps; manual fallback). | M |
| **C19** `nutrition-plan-ui` | `nutrition_plan/nutrition_plan_page.dart`, widgets `kcal_range_slider` (two thumbs, step 10, bounds announced), `macro_ranges_card`, `ownership_selector`, `auto_adjust_toggles`, `professional_notice`, `review_card` (why-card, 7-day undo for coached); `plan_sources_page.dart` (data sources and limits, attribution list), `plan_explainer_page.dart`; routes `/nutrition`, `/nutrition/sources`, `/nutrition/how-it-adapts`; `NutritionEntryCard` on Progress/Home (hidden numbers for `referProfessional`); result screen plan-decision + next-week actions wired via `scanPlanDecisionProvider` (hidden for `referProfessional` reasons 3-5). ARB keys. | XL |

Stories: E4-S1 plan computed, bounded, editable inside bounds, ownership semantics (design s18); E4-S2 weekly review keeps or proposes bounded change and always explains; E4-S3 neutral professional notice with no numbers anywhere; E4-S4 data-sources and explainer pages; E4-S5 post-scan plan decision uses the same function.
DoD E4: slider cannot produce a value outside recomputed bounds; manual ownership never auto-changes; exceeding the range uses neutral wording (no red, no "over budget").

### E5. Food scanning (Functions callables + Flutter UI + diary + "Check these" chips)

| Commit | Content | Size |
|---|---|---|
| **C20** `food-functions` | `functions/src/`: `nutrition_normalise.ts`, `label_normalise.ts`, `coerce_meal_analysis.ts`, `nutrition_sources/{open_food_facts,usda_fdc}.ts` (fixed hosts, `User-Agent` from config, 5-minute breaker, legacy OFF search fallback), `nutrition_lookup.ts` (cache `nutrition_cache/*` with TTL), `analyze_meal_photo.ts`, `parse_nutrition_label.ts`, plus `lookupBarcode`/`searchFoods` callables (GTIN check digit re-implemented), `index.ts` exports. Flags: `analyzeMealPhoto` and `parseNutritionLabel` call `assertFeatureEnabled(FOOD_AI_ENABLED)`; `lookupBarcode`/`searchFoods` call `assertFeatureEnabled(FOOD_LOOKUP_ENABLED)`; with `USDA_FDC_API_KEY` unset enrichment skips USDA and falls back to the model values tagged `llm_estimate`. Reads Secret Manager binding only if the secret exists (no deploy-time failure when unset). | XL |
| **C21** `generic-foods-table` | NEW `scripts/nutrition/build_generic_foods.py` (written, NOT run in CI; the operator machine or an agent runs it once offline: output is committed) and `mobile/assets/nutrition/generic_foods_v1.json` (about 2,000-2,500 rows, USDA Foundation + SR Legacy, nutrient ids 1008/1003/1005/1004) plus own-authored `generic_foods_ru.json` (first ~400 foods; Q-9 default), `pubspec.yaml` asset registration, `food_diary/data/generic_foods.dart` (pure loader/search), `nutrition_plan/data/food_suggestions.dart` (diet/allergen/exclusion filter, uncertain tags default restrictive). If the USDA dataset cannot be fetched by the agent (network or licence page), commit the script plus a 150-row hand-seeded fixture asset and record the gap as an operator item (see Q-9 note). | L |
| **C22** `food-diary-data` | `food_diary/data/`: `food_entry.dart` (`FoodEntry`, `FoodItem`, `MacroRange`), `portion_math.dart`, `day_totals.dart` (RSS ranges, per-meal split 30/35/35), `check_these.dart` (closed codes + resolutions), `gtin_validator.dart`, `label_scale.dart`, `food_source.dart`. | M |
| **C23** `food-diary-state-and-ui` | `food_diary/state/`: `diary_providers.dart`, `food_api.dart` (callable client behind an interface + fake; returns `feature-disabled` mapped to a calm "not available yet" state), Firestore diary/saved-foods repositories + fakes; UI `food_diary_page.dart`, `add_food_page.dart` (tiles hidden when the corresponding flag is off), `food_detail_sheet.dart` (portion editors, ranges, slot picker, Save), search (explicit submit, 600 ms debounce, 3-char minimum, last-results cache), manual quick-log, `meal_slot_section`, `day_summary_ring`, `macro_bars`, `check_these_chips`, `portion_editor`, `source_badge`; routes `/nutrition/diary`, `/nutrition/add`, `/nutrition/add/search`. Diary hidden for `referProfessional`. ARB keys. | XL |
| **C24** `meal-barcode-label-capture` | `meal_scan_page.dart` (resize to 1024 px, describe mode, user note; optional encrypted local thumbnail with the existing cipher, deleted with the entry), `barcode_scan_page.dart` + `state/barcode_port.dart` (wraps `mobile_scanner`; Android `useUnbundled` flag only after the VERIFY on a device is recorded, else left default), `label_scan_page.dart` (resize 1280 px, always an editable confirmation sheet, saves a `saved_food` only after confirm); routes `/nutrition/add/photo|barcode|label`; NEW `core/ATTRIBUTIONS_NUTRITION.md` (rows from design s17.9, registered in `core/INDEX.md`); the in-app sources page lists the same. ARB keys. | L |

Stories: E5-S1 meal photo and describe-in-text recognition with ranges, source tags and "Check these" chips (flag `FOOD_AI`); E5-S2 barcode lookup with central cache and not-found fallbacks (flag `FOOD_LOOKUP`); E5-S3 label OCR with mandatory user confirmation (flag `FOOD_AI`); E5-S4 search over bundled table (always) and server search (flag); E5-S5 diary by meal slot, per-day totals vs plan, per-meal targets, neutral wording; E5-S6 quick log; E5-S7 attribution.
DoD E5: with all flags off the diary still works (bundled search, quick log, saved foods); no meal or label photo is ever stored server-side; macros are always recomputed server-side from `per100g x grams`; no provider free text is displayed; no secrets, keys or API hosts from the reference app appear anywhere.

### E6. Privacy, deletion, export, data inventory

| Commit | Content | Size |
|---|---|---|
| **C25** `privacy-deletion-export-inventory` | `functions/src/index.ts` `sweepAccountData` (storage prefix purge, SD-6); `functions/src/account_export.ts` (+7 collections each bounded by `MAX_ROWS + 1`, capped 24 h signed photo links for `photosState == stored` only, D-15); device-local: per-uid SharedPreferences keys and `meals/` thumbnails added to the existing wipe list (VERIFY the `account_deletion` feature); in-flight scan/diary writers adopt the `accountBeingDeletedUidProvider` fence; `core/DATA_INVENTORY_2026-08-11.{md,csv}` rows (each Firestore path, the bucket, device-local stores); `scripts/ci/data_lifecycle_policy.json` rows (BOTH retention class, `clientAccess` matching the rules table, `nutrition_cache` EXEMPT); `public/privacy.html` rewritten to match actual behaviour (on-device blur, retention default 0, one-tap deletion, provider, meal/label photos not stored, no analytics SDK receives photos or body metrics). DECISION_LOG: privacy wording status (Q-10). | L |

Stories: E6-S1 account deletion erases all new Firestore data and any Storage objects; E6-S2 export includes all new data; E6-S3 inventory and policy rows exist for every new path; E6-S4 privacy page is accurate for the default (flags-off) behaviour and states what changes when the operator enables each flag.
DoD E6: every new collection appears in inventory, policy and export; `public/privacy.html` has no sentence that is false for the shipped default.

### E7. l10n EN + RU and accessibility

| Commit | Content | Size |
|---|---|---|
| **C26** `l10n-a11y-audit` | Audit-only changes: every new key present in EN and RU ARB files with identical placeholders and ICU plurals (RU has three plural forms: weeks, kilograms, points), no hard-coded user-visible string in the new features, `Semantics` labels and live regions per design s24 (skeleton overlay excluded from semantics; chart summary sentence; range slider thumb labels; 48 dp targets; 200 % text scale scrolls without clipped fixed-height cards), RU expansion check of chips and status panel, closed-code keys (`checkCode*`, `reviewReason*`, `foodCheck*`, `trainingReason*`) complete, medical-safe wording pass (no diagnosis words, no "should/must" about health). | M |

Stories: E7-S1 parity and plurals; E7-S2 a11y semantics and scaling; E7-S3 wording pass.
DoD E7: a key-set diff of EN vs RU ARB for the new prefixes is empty (checked by reading/grep in the review phase, plus the focused parity test in section 6).

### E8. Documentation and registry

| Commit | Content | Size |
|---|---|---|
| **C27** `docs-codemap-index-decisions` | `core/CODEMAP.md` (three new features + `activity/` foundation, routes, functions, assets, scripts), `core/INDEX.md` (sprint plan, coverage map placeholder row, attribution file, runbook), `core/CURRENT_STATE.md` (honest status: provisional estimator, flags, NOT_RUN list), `core/DECISION_LOG.md` (SD-n not yet recorded, final flag defaults, VERIFY outcomes), `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` touched only if a VERIFY changed its premises. | S |

The requirements-to-test coverage map (`core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md`) is authored by `functional-test-reviewer` at the start of the verification phase (commit T1), from design s28 and the story IDs above; this plan only fixes the story IDs it must cover.

### Commit order and dependency summary

`C01 -> C02 -> C03 -> C04 -> C05 -> C06 -> C07 -> C08 -> C09 -> C10 -> C11 -> C12 -> C13 -> C14 -> C15 -> C16 -> C17 -> C18 -> C19 -> C20 -> C21 -> C22 -> C23 -> C24 -> C25 -> C26 -> C27`

Hard dependencies: C01 before C04 (rules before the client emits new keys); C04 before C05/C10; C05 before C06/C09/C10/C18; C07 before C13-C16; C12 before C14 (callable contracts); C13 before C15; C15 before C19 (`scanPlanDecisionProvider`); C18 before C19; C20 before C23/C24 (callable contracts); C21 before C23 (search) and before food suggestions UI; C22 before C23; C25 after every collection exists; C26 after all UI. Independent tracks that may be implemented in parallel by separate agents WITHOUT changing the commit order: Functions (C02, C12, C20) vs Dart (C03-C11, C13-C19, C21-C24); the coordinator still commits in the order above and reads each diff before staging.

## 4. Feature flags and operator-blocked items (SD-2)

| Flag (client / server) | Default | Gates | Blocked by | Fallback when off |
|---|---|---|---|---|
| `BODY_SCAN_CLOUD` / `BODY_SCAN_BUCKET` set + `BODY_SCAN_PROVIDER` | off / unset (provider `provisional-anthropometric`) | any photo upload, cloud consent sheet, signed-URL path, storage purge | Q-1, Q-5 | provisional estimator (height/weight/age/sex only); no photo leaves the device; capture, local storage, compare, history, trend, plan all work |
| `FOOD_AI` / `FOOD_AI_ENABLED` | off | `analyzeMealPhoto` (photo and describe), `parseNutritionLabel` | Q-6 | bundled search, quick log, saved foods, manual entry |
| `FOOD_LOOKUP` / `FOOD_LOOKUP_ENABLED` (+ `USDA_FDC_API_KEY`, OFF contact) | off | `lookupBarcode`, `searchFoods`, USDA/OFF enrichment | Q-4 | barcode tile hidden, server search hidden, bundled search only |

Server callables behind a flag throw `failed-precondition: feature-disabled`; the client maps it to a calm unavailable state and never retries it. Enabling a flag later is an operator action (set env/secret, redeploy, build with `--dart-define`) and needs no code change.

## 5. Operator-owned items (defaults chosen so work is not blocked)

| ID | Question | DEFAULT used in this sprint | Status |
|---|---|---|---|
| Q-1 | Which real body-composition provider | Stay on the provisional estimator behind the provider interface (design s8); permanent banner, half-width 5.0 placeholder, no accuracy claimed | Default applied; real provider is a later server-config + adapter swap |
| Q-2 | Tier gating per feature | Gate only the scan exactly as today (`scanAccessProvider`); everything else ungated; entries exist in `feature_gates.dart` so each is a one-line change | Default applied |
| Q-3 | Photo retention | Delete after analysis (`retentionDays = 0`); options 30/90/365 | Default applied (moot while provisional) |
| Q-4 | OFF `User-Agent` contact + free USDA FDC API key as a secret | None supplied | BLOCKED on operator; `FOOD_LOOKUP` off |
| Q-5 | Provision private bucket + IAM + secret accessor grant (`runbooks/body_scan_bucket.md`) | None provisioned | BLOCKED on operator; cloud photo path off |
| Q-6 | Vertex AI data-retention posture to state on the privacy page | Privacy text says provider handling follows Google Cloud terms and nothing is stored by us | BLOCKED on operator; `FOOD_AI` off |
| Q-7 | Minimum age for nutrition | 18 (`lowestAgeAt >= 18`; unknown age = no plan) | Default applied |
| Q-8 | Imperial units | Metric only this sprint | Default applied |
| Q-9 | Russian food names | Own Russian translation of the first ~400 generic foods, English fallback for the rest | Default applied (agent-authored; operator may proofread later) |
| Q-10 | `public/privacy.html` wording owner | Agents write accurate text for the flags-off default in C25; operator sign-off required before flipping any flag | BLOCKED on operator sign-off for enabling; text itself ships |
| Q-11 | Confirm design s3 against reference frames | `product-ux-reviewer` confirms during the one review pass; if frame extraction is unavailable the doubt is recorded, not blocking | Non-blocking |

Other operator items surfaced by the design and not blocking: deploy order (rules, then functions, then client); App Check/DeviceCheck for iOS; readiness-threshold calibration on the operator's phone (NOT_RUN); `useUnbundled` scanner flag device check; release signing (`wear/` is untouched).

## 6. Verification plan under DEVELOPMENT RULES v4

### 6.1 Phases (strict order)

1. **Coding phase (C01-C27).** NO tests, analyzer, lint, build, `pub get`, `build_runner`, CI or emulator runs. Self-review is by reading the diff of the exact paths before each commit. Findings from reading are fixed before committing.
2. **Focused functional tests.** `functional-test-reviewer` writes and `e2e-runner` runs ONLY the files listed below, each file individually or as a short explicit list (never `flutter test` or `jest` without file arguments). Exact script names come from `mobile/pubspec.yaml`/`functions/package.json` (VERIFY by reading). Fix bugs, re-run only the affected files until green. Test files and the coverage map are committed as T1 (tests + `core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md` + change record); fixes as T2..Tn, each with its own change record.
3. **Specialist reviewers** (Sonnet 5.5 medium or GPT-5.6 Luna low/medium only; no Sol, no substitution): `silent-failure-hunter`, `security-reviewer` (rules, signed URLs, blur fail-closed, prompt-injection surface), `database-reviewer` (rules/indexes/lifecycle/export), `flutter-reviewer`, `code-reviewer` (TypeScript), `python-reviewer` (only for `build_generic_foods.py`), `a11y-architect` and `product-ux-reviewer` (E3/E4/E7 surfaces). Round 1 independent, deduplicate, fix all valid BLOCKER/MAJOR in one batch (R1 commits with change records), re-open only contested findings or regressions.
4. **Final GPT-PM gate** on the exact final head with test results and reviewer consensus as evidence. A new commit afterwards invalidates the approval.
5. **Push and ONE PR only after GPT APPROVE**, after verifying the outbound range. PR description in English with the session attribution line.

While phase 2 starts, next-sprint documentation preparation (Phase 2 backlog review) may be delegated in parallel per rule 7; it must not delay closure.

### 6.2 Focused test files per epic (paths are created in T1; none exists yet)

| Epic | Dart (`mobile/test/features/...`) | Functions (`functions/src/...`) |
|---|---|---|
| E0 | `core/config/body_scan_flags_test.dart` | `__tests__/feature_flags.test.ts`; `__rules__/firestore_rules.test.ts` (extended, cases 1-10), NEW `__rules__/storage_rules.test.ts` (case 11); `__rules__/data_access_policy.test.ts` (extended); `__tests__/discover_callables` expectations |
| E1 | `nutrition_plan/data/{energy_math,safety_clamps,plan_calculator,nutrition_eligibility,weekly_review,missing_inputs,nutrition_training_state}_test.dart`; `body_scan/data/{scan_trend,scan_result_math,plausibility,check_items,face_region,body_scan_flow_machine,body_scan_job}_test.dart`; `activity/data/{activity_models,activity_merger}_test.dart`; `profile/{nutrition_prefs_json,health_flags_json}_test.dart` | - |
| E2 | `onboarding/{step_nutrition_answered,onboarding_order}_test.dart`; `nutrition_plan/nutrition_profile_flow_test.dart` (widget, fakes) | - |
| E3 | `progress_photos/scan/{scan_models_v2,scan_reminder_weekly}_test.dart`; `body_scan/state/{blur_service,body_scan_job_runner}_test.dart`; `body_scan/widgets/{setup_status_panel,skeleton_overlay_smoke,result_view,analysis_progress_view}_test.dart` | `__tests__/body_scan_{create,estimate,delete,purge}.test.ts`, `provisional_estimator.test.ts`, `validate_estimate.test.ts` |
| E4 | `nutrition_plan/state/{plan_repository,review_scheduler}_test.dart`; `nutrition_plan/widgets/{kcal_range_slider,professional_notice}_test.dart` | - |
| E5 | `food_diary/data/{portion_math,day_totals,check_these,gtin_validator,label_scale,generic_foods}_test.dart`; `nutrition_plan/data/food_suggestions_test.dart`; `food_diary/widgets/check_these_chips_test.dart` | `__tests__/{coerce_meal_analysis,nutrition_normalise,label_normalise,lookup_barcode,search_foods,analyze_meal_photo,parse_nutrition_label}.test.ts` (OFF fixture barcode 3017620422003, EN + RU label fixtures, flag-off behaviour) |
| E6 | - | `__tests__/{delete_account,account_deletion_reconcile,account_export}.test.ts` (extended: storage call, no-op when unconfigured, new collections, capped links) |
| E7 | `l10n/new_keys_parity_test.dart` (EN/RU key sets and plural forms for the new prefixes) | - |
| E8 | - (documents are reviewed, not tested) | - |

Rules tests run on the Firebase emulator via the project's existing rules-test script limited to the named files. Behavioural assertions that must exist (so a broken guard turns the test red): wildcard carve-out proof (design s6.4 case 9), `flagsAreStripped` refusal of the two new keys, estimator range/threshold behaviour with the provisional half-width, every row of the eligibility table in order, deficit/floor/bounds boundaries, review two-consecutive-`behind` rule and cooldown, flow-machine transitions and cancel from every state, v1 scan never uploaded, blur pixel test (inside changed, outside unchanged, EXIF absent), merger order-independence (shuffled inputs), flag-off callables throwing `feature-disabled`.

### 6.3 Evidence record (verification-contract)

The T1 coverage map and the final report use the table `Claim | Evidence | Command/artifact | Head | Result | Not covered`. Statements limited to what ran: nothing is claimed for iOS, real devices, the licensed estimator (none), real OFF/USDA/Vertex calls (not run), threshold calibration, or deployed rules/functions.

## 7. Definition of Done

### 7.1 Per commit
Coherent single unit; paths staged explicitly; diff read; change record `core/changes/<date>-<slug>.md` included and linked from the commit message; DECISION_LOG entry in the same commit when a durable decision is made; ARB EN + RU keys in the same commit as the UI (SD-3); no test/analyzer/build run; English only; attribution trailer present.

### 7.2 Per epic
The epic DoD lines above, plus: every story ID has at least one named test file in section 6.2 (or is documentation-only); no file outside the epic's path list changed except through a noted VERIFY outcome.

### 7.3 Sprint (the PR is allowed to open only when ALL hold)
1. All 27 commits present; every change record accurate; document registry (`core/INDEX.md`) updated.
2. Focused functional tests green on the final head for every file in 6.2; failures fixed at root cause; the exact command and head recorded.
3. Specialist review consensus reached; no valid BLOCKER/MAJOR open; remaining MINOR items listed in the PR description.
4. Safety acceptance checks proven by tests: floors, maximum weekly rates, protein range, under-18 and unanswered-question lockout, no numbers for `referProfessional`.
5. Privacy acceptance checks proven by tests or review: no photo upload with the provisional provider, blur fails closed, server-authored scan fields not client-writable, deletion and export cover every new path.
6. Flags default off, fallbacks work with all flags off, `public/privacy.html` accurate for that default.
7. Final GPT-PM APPROVE for the exact head; then push and ONE PR; the final report states: provisional estimator limitation, operator-blocked items (Q-4/Q-5/Q-6/Q-10), iOS NOT_RUN gaps, threshold calibration NOT_RUN.

## 8. Risks specific to executing this plan

| Risk | Mitigation |
|---|---|
| No compiler or analyzer while coding (v4) lets syntax/type errors accumulate across 27 commits | SD-1 ordering, small pure files first, reading every diff, and the test phase is the first compile: budget for a real fix cycle (T2..Tn) |
| Design VERIFY items turn out different (camera luminance source, programme builder seam, notification tap, `saveDraft` and `completedAt`, `mobile_scanner` version) | Each is bounded by a pre-agreed fallback (SD-4, SD-7, C13, C17); outcome recorded in the commit's change record and DECISION_LOG |
| Wildcard carve-out or `flagsAreStripped` mistake bricks all profile saves | C01 first and read twice; rules emulator cases 2, 8, 9 are mandatory tests; deploy rules before client (operator note) |
| Provisional estimator misread as a measurement | Permanent banner, range, noise threshold; reviewed by product-ux-reviewer |
| Scale: about 27 commits, XL UI commits (C15, C19, C23) | Parallel Functions/Dart tracks; screens split by widget file; XL commits may be split into sequential sub-commits without reordering dependencies |
| `generic_foods_v1.json` source unavailable to the agent | C21 fallback seed asset plus operator item; diary still works |
| Concurrent sessions touch the same files (`app_router.dart`, ARB, `pubspec.yaml`, `functions/src/index.ts`) | `git status` and diff of exact paths before every commit; never stage others' hunks; hand-merge router/ARB/index additions rather than regenerating |
| Hand-written l10n drift between EN and RU | SD-3 plus C26 audit plus the parity test |
| Privacy text lagging behavior | C25 owns `privacy.html`; DoD item 6 |

## 9. Out of scope (unchanged)

"Future You" or any generated body image, social sharing of body photos, exercise-calorie credit (D-29), imperial units (Q-8), a validated body-fat model, any sport UI/adapters/persistence for the activity model, vendor clouds, BLE, watch apps, and everything in the Phase 2 backlog. Reverse engineering of proprietary apps is refused (D-35). No change to unrelated features, no deletion of existing user data, no schema change that breaks current users (all new fields default safely).
