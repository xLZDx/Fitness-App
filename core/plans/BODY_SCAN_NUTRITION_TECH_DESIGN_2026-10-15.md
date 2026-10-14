# Body Scan + Nutrition Coach - technical design

**Status:** DESIGN v1 for the one-time review (architect, security-reviewer, database-reviewer, product-ux-reviewer, a11y-architect). Not implemented. Date 2026-10-15. Branch `feature/body-scan-nutrition-coach`, base `master` `42d1b84`.

**Inputs:** operator brief of 2026-10-15 (scope, delivery rules), the scope change of the same day (food scanning is now IN scope), `core/plans/PHASE2_BODY_SCAN_COACH_REFERENCE_REVIEW_2026-10-09.md` (draft input, not approved scope), and the repository at the base commit (inspected files are cited inline as `path:symbol`).

**Clean-room rule.** Only behaviour and UX structure of the third-party reference app (`com.body.fat`) were used. No code, decompiled output, assets, icons, fonts, copy text, promo codes, API hosts or keys are copied. All strings and visuals are our own, localised EN + RU through the existing ARB setup. Open-source nutrition data and code that IS copied or bundled is listed in the attribution file defined in section 17.6.

**Conventions used in this document.** `FACT` = observed in the repo at the base commit. `VERIFY` = an assumption the implementer must confirm in the named file before coding. `DECISION D-n` = a choice made here; all of them are repeated in section 27 and in `core/DECISION_LOG.md`. `OPEN Q-n` = a question for the operator (section 26). Nothing here was run: no tests, analyzer, build or CI.

## Table of contents

0. Reading guide and scope
1. Goals, non-goals, scope delta
2. Repo recon: what exists, what is extended, what is new
3. Behaviour notes from the reference material (clean-room)
4. Architecture and module layout
5. Data model: Firestore, Storage, device-local
6. Security rules diffs and required emulator tests
7. Cloud Function contracts
8. Estimator provider interface and the PROVISIONAL estimator
9. Face blurring, upload pipeline, retention
10. Scan state machine, offline queue, resume
11. Live capture checks and gating
12. Result math: ranges, noise threshold, smoothing
13. Nutrition maths and safety clamps
14. Exclusions and the neutral "talk to a professional" behaviour
15. Weekly review: client-side decision logic
16. Onboarding diff and the "complete your nutrition profile" flow
17. Food scanning, diary, nutrition data (scope delta)
18. Plan ownership (Coached / Shared / Manual)
19. Weekly scan reminder
20. Privacy flow, account deletion, data export, lifecycle policy
21. Routes, entry points, state management
22. Subscription gating
23. l10n key plan (EN + RU)
24. Accessibility
25. iOS parity, extension points
26. Risks and open questions
27. Decisions (to be copied into `core/DECISION_LOG.md`)
28. Requirement-to-test seeds (input for the coverage map)
29. Numeric parameter provenance table (observed / published / own choice)
30. Nutrition-aware programme level (data contract, pure decision function, sprint vs Phase 2)
31. Sport-agnostic activity model and device sources (foundation; sprint vs Phase 2)

## 0. Reading guide and scope

Two pillars, built as ADDITIONS to the existing app:

- **A. Weekly body scan** - 3 poses (front, side, back), body-fat estimate with a range, trend, comparison, history.
- **B. Nutrition Coach** - daily calorie RANGE, macro ranges, protein minimum, steps goal, adaptive weekly review, food guidance, plus (scope delta) a food diary by meal slot with AI meal recognition, barcode, label OCR, describe and search.

Everything numeric is a pure-Dart function with no Flutter imports (`data/` layer convention in `core/CONVENTIONS.md`), so the focused functional tests run on the host.

Out of scope, unchanged: "Future You" or any generated body image, social sharing of body photos, anything from the reference app's code/assets/copy, changes to unrelated features, full-suite test runs. An extension point for Future You is documented in section 25 only.

## 1. Goals, non-goals, scope delta

### 1.1 Goals (acceptance criteria, checkable)

| ID | Criterion |
|---|---|
| G1 | A signed-in adult (>= 18) who accepted the consents can run a weekly 3-pose scan from Progress or the Home card and get a body-fat result with a likely range, change vs previous with a noise-aware "no meaningful change" label, points to goal, fat/lean mass, a chart with noisy dots + smoothed trend, a plan decision and next-week actions. |
| G2 | Every estimate shows a range, a model id/version and a plain-language limit; low confidence yields specific "Check these" items. Nothing is presented as medical advice. |
| G3 | Capture shows live Distance/Lighting/Position checks and a 3-2-1 countdown; automatic capture is gated on all checks green; manual capture remains available and is recorded. |
| G4 | The scan pipeline survives cancel, retry, app kill and offline (resumable queue). |
| G5 | Photos are private by default; any cloud copy is face-blurred ON DEVICE before upload; the user controls retention, can delete a scan's photos in one tap; an explicit consent screen precedes the first upload. Account deletion and data export cover all new data. |
| G6 | A nutrition plan (kcal range, protein minimum, macro ranges, steps goal) is computed from profile + trend with enforced safety clamps; excluded groups see a neutral "talk to a professional" message and no plan. |
| G7 | A weekly review keeps or adjusts the plan within bounded steps and always states why. |
| G8 | Onboarding collects what B needs through skippable steps with defaults; users who already finished onboarding are never forced again and get a "complete your nutrition profile" flow. |
| G9 | Food diary by meal slot with AI meal photo recognition, describe-in-text, search, barcode and label OCR; confidence ranges on portions and macros; "Check these" chips; per-day totals against plan targets. |
| G10 | Health Connect is read-only through the existing `HealthService` seam, with manual fallback. Android first; nothing blocks iOS. |

### 1.2 Non-goals

Future You / generated imagery; social sharing; medical advice or diagnosis; exercise-calorie "credit" added back to the kcal budget (D-29); a validated body-fat model (the estimator ships PROVISIONAL, section 8); iOS verification on device.

### 1.3 Scope delta received during authoring

The operator moved AI meal scanning (photo, describe, search), barcode and nutrition-label OCR, a food diary by meal slot, "Check these" chips and per-day totals INTO scope (still out: Future You, social sharing, any reference-app code/assets/copy). The app is private (operator, friends, family), so third-party open-source licences are not a blocker, but an attribution list is mandatory for anything copied or bundled. The follow-up list therefore shrinks to section 25.3.

## 2. Repo recon

### 2.1 FACTS that shape the design

1. **A local guided-scan stack already exists** under `mobile/lib/features/progress_photos/scan/` (routes `/photos/scan`, `/photos/compare`): `readiness_evaluator.dart` (Distance / Lighting / Position / Orientation from pose landmarks + luminance, `ReadinessConfig` opening thresholds "not measured on a device fleet"), `auto_shutter_machine.dart` (hold 1000 ms, 3-2-1 countdown, 3000 ms cooldown, cancel on any lost readiness), `body_alignment.dart` (similarity transform for compare), `scan_models.dart` (`ScanRecord` v1, `ScanShot` = photo id + landmarks, `ScanLandmark`), `scan_store.dart` (AES-GCM sidecar `scans/<id>.scan`), `scan_repository.dart` (`scanRepositoryProvider`, `scanHistoryProvider`), `scan_access.dart` (`ScanAccess`: signed-in, age known and >= 18 via `PersonalInfo.lowestAgeAt`, supporter tier, existing photo consent), `scan_reminder.dart` (14-day one-shot reminder), UI: `scan_capture_screen.dart`, `scan_compare_screen.dart` (side-by-side, slider, ghost), `scan_entry_card.dart`, `scan_gate_view.dart` (delete one/all scans).
2. **Photos are device-local and encrypted** (`progress_photos/data/photo_store.dart`, `aes_photo_cipher.dart`, per-uid directory and key). `ProgressPhoto` doc comment: nothing writes photos to Cloud Storage today. There is NO `storage.rules` file and no `storage` block in `firebase.json`. `public/privacy.html` promises on-device handling (see section 20).
3. **Health answers are device-only by design** (`profile/data/sensitive_profile.dart`, `firestore.rules` `healthIsStripped` / `flagsAreStripped` with `hasOnly` key lists - a new key under `health.flags` that is not added to the rules makes the write FAIL CLOSED). No Cloud Function reads the profile.
4. **`firestore.rules`**: the wildcard `match /users/{uid}/{coll}/{document=**}` grants owner read/write to EVERY subcollection not excluded by name. A narrower `match` for a collection does nothing unless the collection is also excluded from the wildcard (Firestore allows if ANY rule allows). Server-authored collections (`usage`, `receipts`, `profile` writes, `recognised_models`, ...) are excluded by name.
5. **Cloud Functions** (`functions/src`, region `europe-west1`): AI callables follow one pattern - `onCall(AI_METERED, ...)`, `noteAppCheck`, `enforceNonAnonymousForAi`, `enforceAiGatewayEnabled`, strict input validation (`image_validation.ts`), per-uid daily quota in `users/{uid}/usage/{day}` (`QUOTAS`, `quotaFor`, `refundQuota`), one shared executor `ai_gateway.ts generate()` (Vertex AI via ADC, model `gemini-3.6-flash`, `maxOutputTokens` required, structured log event per call, operation names in the closed tuple `AI_GATEWAY_OPERATIONS` that also drives monitoring definitions). Signed URLs without key files: `video_urls.ts` (`getStorage().bucket(...).file(...).getSignedUrl({version: "v4", ...})`, runtime SA with `serviceAccountTokenCreator` on itself). Runtime identities: `RUNTIME_SA` in `scaling.ts`.
6. **Account deletion** (`index.ts sweepAccountData`): `recursiveDelete(users/{uid})` + shared-record sweep; the doc comment above `deleteAccount` states that whoever builds photo storage MUST add its cleanup in the same change. **Export**: `account_export.ts` (`exportAccountData`, quota `QUOTAS.accountExport`).
7. **Data lifecycle governance**: `core/DATA_INVENTORY_2026-08-11.{md,csv}` (columns `layer,location,holds,uid_field,deleted_by_deleteAccount,in_export,gate`) and `scripts/ci/data_lifecycle_policy.json` (one row per collection: retention class DELETE/EXPORT/BOTH/EXEMPT plus `clientAccess` per path) are checked by `check_data_lifecycle_coverage.js` / `check_data_access_policy.js`; a collection missing from them fails those checkers. (Not run here: prohibited checks.)
8. **Onboarding**: `OnboardingStep` enum + `kOnboardingOrder` + `isOnboardingStepAnswered` + `onboardingResumeIndex` in `onboarding/data/step_answered.dart`; the `switch` over the enum is exhaustive, so a new step MUST get a case. Steps live in `onboarding/steps/`, state in `questionnaire_notifier.dart` (`QuestionnaireDraft`, `update*` methods). The router redirect uses `profile.hasCompletedOnboarding` (`app_router.dart redirectFor`), so users with `completedAt != null` are never sent back to `/onboarding`.
9. **Profile model** (`profile/data/profile_models.dart`): `PersonalInfo` (birthYear, `gender` enum incl. nonBinary/preferNotToSay, heightCm, weightCurrentKg, weightTargetKg, `ActivityLevel` 4 values), `Lifestyle` (diet multi-select: vegetarian, vegan, glutenFree, dairyFree, halal, kosher, none; `sleepHoursPerNight`), `FitnessGoals` (`primary: ProgrammeGoal`, `weightLoss`, `muscleGain`), `HealthHistory.flags: HealthFlags` (restrictions, bloodPressure, surgery, clinicianAdvice, `professionalGuidance` - F014: a generic "reported" flag that blocks workout prescription, deliberately stores no medical detail). `UserProfile.toJson` is the single serializer shared with the data export.
10. **Health**: `core/health/health_service.dart` `HealthService` (read-only snapshots per day: steps, activeMinutes, sleepScore, hrv, resting HR; `requestAuthorization`, `platformSetupRequired`), `core/health/widgets/health_sync_card.dart` (existing permission UI).
11. **Notifications**: `core/notifications/notification_service.dart` - `scheduleAt(id, fireAt, title, body)` one-shot with `ReminderOutcome`, `cancelReminder`, permission requested lazily by schedule calls; strings passed in already localised.
12. **`body_comp/data/body_comp_estimate.dart`** holds only `navyBodyFatPercent(...)` (US Navy circumference formula, no production caller). `goal_photo/data/goal_photo_request.dart` is a documented MVP request shape that is not wired (and touches the out-of-scope generative area; untouched).
13. **Tests**: `functions/src/__tests__`, `__rules__` (emulator rules suites), `__e2e__`; app tests in `mobile/test`.

### 2.2 Files EXTENDED (existing)

| File | Change |
|---|---|
| `progress_photos/scan/scan_models.dart` | `ScanRecord` v2: optional `weightKg`, `capture` flags (per pose `manualOverride`), `analysis` job block (section 10). Reader stays tolerant of v1. |
| `progress_photos/scan/ui/scan_capture_screen.dart` | accept `onSaved` result (pop with scan id), mount the skeleton overlay, read luminance from the camera port (section 11). No rewrite. |
| `progress_photos/scan/ui/scan_ports.dart` | `ScanCamera` gains `ValueListenable<double?> luminance`. |
| `progress_photos/scan/scan_reminder.dart` | weekly weekday/time schedule (section 19), same notifier and id. |
| `progress_photos/scan/ui/scan_compare_screen.dart` | accepts initial selection (baseline-vs-latest / previous-vs-latest). |
| `progress_photos/scan/ui/scan_entry_card.dart` | secondary entry; primary entry becomes the new `BodyScanEntryCard`. |
| `profile/data/profile_models.dart` | `UserProfile.nutrition: NutritionPrefs` (new nested object, defaults empty), `SexAtBirth` enum on `NutritionPrefs`, `DietaryPreference.pescatarian`. |
| `safety/data/health_flags.dart` | `HealthFlags.nutritionGuidance`, `HealthFlags.foodAllergens` (+ `isUnanswered`/`isEmpty`/`==`/`hashCode`/`toJson`/`fromJson`/`copyWith`). |
| `firestore.rules` | carve-outs + new blocks + `flagsAreStripped` key list (section 6). |
| `onboarding/data/step_answered.dart`, `steps/step_health_flags.dart`, `steps/step_lifestyle.dart`, `state/questionnaire_notifier.dart` | new step and updates (section 16). |
| `core/router/app_router.dart` | new routes (section 21). |
| `progress/progress_page.dart`, `home/` | entry cards. |
| `functions/src/index.ts` (`sweepAccountData`), `account_export.ts`, `abuse_guard.ts` (`QUOTAS`), `ai_gateway.ts` (`AI_GATEWAY_OPERATIONS`), `monitoring/ai_gateway_definitions.ts`, `scaling.ts`, `release_guard.ts` expectations | new callables wired in (section 7). |
| `core/DATA_INVENTORY_2026-08-11.{md,csv}`, `scripts/ci/data_lifecycle_policy.json`, `core/CODEMAP.md`, `core/INDEX.md`, `public/privacy.html`, ARB files | documentation and policy rows (section 20). |

### 2.3 NEW code

`mobile/lib/features/body_scan/`, `mobile/lib/features/nutrition_plan/`, `mobile/lib/features/food_diary/` (section 4); `functions/src/body_scan/*`, `functions/src/analyze_meal_photo.ts`, `coerce_meal_analysis.ts`, `parse_nutrition_label.ts`, `label_normalise.ts`, `nutrition_lookup.ts` (barcode + search), `nutrition_normalise.ts`, `nutrition_sources/{open_food_facts,usda_fdc}.ts`; `storage.rules`; bundled asset `mobile/assets/nutrition/generic_foods_v1.json` (built by a script, section 17.5).

## 3. Behaviour notes from the reference material (clean-room)

Derived from the operator's description of the two recordings in the brief (frame-by-frame re-inspection of `scratchpad/ref1` and `ref2` was NOT repeated during authoring - **TODO for product-ux-reviewer: confirm against frames**). Behaviour only; every string, layout and visual is our own.

Weekly scan flow:
1. Intro screen: consistent clothing, lighting and distance week to week; three guided poses; photos private; about one minute.
2. Optional sheet before capture: "log weight first" or "scan without updating".
3. Live camera with on-device skeleton overlay, pose label (front, side, back), countdown 3-2-1, a status panel with three live checks (distance, lighting, position) each in a fixed/ok state; capture only when all are ok.
4. After capture: a staged progress screen with named stages and elapsed time (photos secured, body composition, plausibility, trend verification, result saved).
5. Result: body-fat value with a likely range, points to goal, change versus last scan with an explicit "no meaningful change" outcome when inside noise, start and goal values, side cards (weight trend, fat mass, lean mass, training sessions this week), a chart where dots are single noisy readings and the line is a smoothed trend, a plain disclosure that single readings vary by about 1-2 points.
6. A plan decision for the week and a short next-week action list; actions: compare photos, edit recorded weight, delete this scan's photos, done, see plan.
7. History list (date, weight, body fat, trend label, baseline marker) and a compare screen that asks for a second scan when only the baseline exists.

Nutrition and diary behaviour: daily energy ring with remaining amount, macro bars; add-food via photo, barcode, label, describe, search; uncertainty chips ("check these") instead of silent guesses; diary by meal slot; plan tab with an editable calorie RANGE, protein minimum, steps goal, ownership (coach / shared / manual), per-metric auto-adjust toggle and a weekly review explanation; profile reminder (weekly, default Sunday morning); data-sources and privacy pages (photos face-blurred, retention control, deletion).

What we deliberately do NOT copy: the "exercise credit" added to the calorie budget (D-29), any generative preview, any wording or iconography.

## 4. Architecture and module layout

Three new features, each in the standard layout (`data/` pure Dart with a ticket doc-comment, `state/` Riverpod providers, `widgets/`, `*_page.dart`). Dependencies point one way: `body_scan` and `food_diary` depend on `nutrition_plan/data` (for targets) and on `progress_photos/scan` (capture reuse); `nutrition_plan/data` depends on `profile`, `safety` only.

```
mobile/lib/features/
  body_scan/
    body_scan_flow_page.dart        host for intro -> weight prompt -> capture -> progress -> result
    data/   (NO Flutter imports)
      body_fat_estimate.dart        BodyFatEstimate value (value, low, high, confidence, modelId, modelVersion, provisional, checkCodes)
      body_scan_entry.dart          BodyScanEntry (server doc view: scanId, takenAt, weightKg, estimate, photosState, ...)
      body_scan_flow_machine.dart   pure state machine (section 10)
      body_scan_job.dart            job status + backoff policy (pure)
      plausibility.dart             profile-consistency checks (section 12.4)
      scan_trend.dart               EWMA, Theil-Sen, noise threshold, change label (section 12)
      scan_result_math.dart         fat/lean mass with ranges, points to goal
      check_items.dart              closed CheckCode enum + mapping to actions
      face_region.dart              head-region geometry from landmarks (section 9)
      body_scan_repository.dart     interface; Firestore + callable implementation in state/
    state/  body_scan_providers.dart, body_scan_job_runner.dart (resume on foreground), blur_service.dart (isolate, uses `image`)
    widgets/ intro_view, weight_prompt_sheet, skeleton_overlay (CustomPainter), setup_status_panel, analysis_progress_view,
             result_view, trend_chart, scan_history_list, check_items_card, cloud_consent_sheet, retention_settings_view
  nutrition_plan/
    nutrition_plan_page.dart, nutrition_profile_flow_page.dart, plan_sources_page.dart, plan_explainer_page.dart
    data/   (pure)
      nutrition_inputs.dart         NutritionInputs (resolved from profile + weight entries), SexForBmr
      nutrition_eligibility.dart    NutritionEligibility verdict (section 14)
      energy_math.dart              Mifflin-St Jeor, activity factors, TDEE
      plan_calculator.dart          PlanBounds + NutritionPlan (kcal range, macros, steps)
      safety_clamps.dart            every clamp as named constants (section 13.5)
      weekly_review.dart            decision logic (section 15)
      food_suggestions.dart         diet/allergen/exclusion filtered suggestions from the bundled table
      weight_entry.dart             WeightEntry + series helpers
    state/  nutrition_providers.dart, plan_repository.dart (Firestore), review_scheduler.dart
    widgets/ kcal_range_slider, macro_ranges_card, ownership_selector, auto_adjust_toggles, professional_notice, review_card
  food_diary/
    food_diary_page.dart, add_food_page.dart, meal_scan_page.dart, barcode_scan_page.dart, label_scan_page.dart, food_detail_sheet.dart
    data/   (pure)
      food_entry.dart               FoodEntry / FoodItem / MacroRange (low, mid, high)
      portion_math.dart             grams range x per-100g -> macro ranges
      day_totals.dart               per-day totals vs targets
      check_these.dart              closed CheckThese codes + resolution actions
      gtin_validator.dart           GTIN check digit (re-implemented from the public GS1 algorithm)
      label_scale.dart              per-serving <-> per-100g scaling of confirmed label values
      generic_foods.dart            bundled-table loader/search (pure parse; asset read lives in state)
      food_source.dart              FoodSource enum, attribution ids
    state/  diary_providers.dart, food_api.dart (callables analyzeMealPhoto, lookupBarcode, searchFoods, parseNutritionLabel behind one interface), barcode_port.dart (wraps mobile_scanner)
    widgets/ meal_slot_section, day_summary_ring, macro_bars, check_these_chips, portion_editor, source_badge
```

State management: Riverpod `Notifier`/`FutureProvider`, providers never created inside `build()`, `setState` only for local widget state (`core/CONVENTIONS.md`). Ports for everything touching a device or the network (camera, speaker, haptics already exist in `scan_ports.dart`; new: `BlurPort`, `UploadPort` (HTTP PUT with `dio`), `BodyScanApi` (callables), `BarcodePort` (wraps `mobile_scanner`), `FoodApi`, `Clock`, `Connectivity`) so widget and machine tests use fakes.

## 5. Data model

All per-user paths live under `users/{uid}/...` ON PURPOSE: `deleteAccount`'s `recursiveDelete(users/{uid})` then erases them, and no new orphan collection is added to the data inventory (same reasoning as `abuse_guard.ts` `usage`). Timestamps are Firestore `Timestamp`; all documents carry `schema: 1`. New fields always default safely; no existing document shape changes except the additive `nutrition` map on the profile document and two additive keys under `health.flags` (device-only, stripped on the server).

### 5.1 `users/{uid}/body_scans/{scanId}` (server-authored, owner-readable)

`scanId` = the client's local scan id (`scan_<microseconds>`, regex `^[A-Za-z0-9_-]{8,64}$`), which makes every callable idempotent.

| Field | Type | Writer | Notes |
|---|---|---|---|
| `schema` | int | server | 1 |
| `status` | string | server | `pending` (created, awaiting upload/estimate), `done`, `failed`, `cancelled` |
| `createdAt` | Timestamp | server | |
| `takenAt` | Timestamp | server | = client-reported capture time, clamped to [createdAt - 7 d, createdAt] |
| `pendingExpiresAt` | Timestamp or absent | server | createdAt + 48 h while `pending`; removed on `done`; the purge job cancels expired pending scans and deletes their objects |
| `subject` | map | server | `{sexAtBirth: "female"|"male"|"unspecified", ageYears: int, heightCm: int, weightKg: double}` as sent and validated at create time (snapshot used by the estimate; NOT health data) |
| `weightKg` | double | server at create, CLIENT-editable | the recorded weight shown on the result; editing it re-derives fat/lean mass on the client only (estimate unchanged) |
| `capture` | map | server | `{manualOverride: {front: bool, side: bool, back: bool}, poses: ["front","side","back"]}` |
| `provider` | map | server | `{id, version, provisional: bool, requiresPhotos: bool}` |
| `estimate` | map or absent | server | `{bodyFatPct, rangeLowPct, rangeHighPct, confidence: "low"|"medium"|"high", checkCodes: [string], modelId, modelVersion, estimatedAt}` - immutable after `done` |
| `photosState` | string | server | `none` (provider did not need photos), `awaiting_upload`, `stored`, `deleted` |
| `photosExpireAt` | Timestamp or absent | server | set when `stored`: now + retention (0 = delete after analysis: now + 24 h grace for retries) |
| `photosDeletedAt` | Timestamp or absent | server | |
| `isBaseline` | bool | server | true for the user's first `done` scan |
| `clientNote` | string <= 200 | CLIENT-editable | optional user note |

Indexes: single-field on `createdAt`/`takenAt` is automatic. The purge job queries the COLLECTION GROUP `body_scans` with `where photosState == 'stored' AND photosExpireAt <= now` and `where status == 'pending' AND pendingExpiresAt <= now`: add two composite collection-group indexes to `firestore.indexes.json` (`body_scans`: `photosState ASC, photosExpireAt ASC`; `status ASC, pendingExpiresAt ASC`, scope COLLECTION_GROUP). History reads order by `takenAt DESC` with `limit(120)` (single-field index, no composite).

### 5.2 `users/{uid}/body_scan_settings/main` (client rw, shape-validated)

`{schema: 1, cloudConsent: {version: int, acceptedAt: Timestamp} | absent, retentionDays: 0|30|90|365 (default 0 = delete after analysis), reminder: {enabled: bool, weekday: 1..7 (default 7), minutes: 0..1439 (default 480)}}`. Absent document = defaults. `cloudConsent.version` starts at 1 and is bumped when what is consented to changes (the existing photo consent does the same with its `v1` key).

### 5.3 `users/{uid}/weight_entries/{yyyy-MM-dd}` (client rw, shape-validated)

`{schema: 1, kg: double (30..300), at: Timestamp, source: "manual"|"scan"}`. Day-keyed so a re-weigh the same day overwrites (idempotent edits; last write wins). Local date of the entry decides the key. Read window for the plan: last 60 days.

### 5.4 `users/{uid}/nutrition_plan/main` (client rw, shape-validated)

```
schema: 1
status: "active" | "referProfessional" | "needsProfile"
ownership: "coached" | "shared" | "manual"            (default coached)
autoAdjust: { steps: bool (default true), kcal: bool (default true) }   (kcal auto-adjust only effective for coached)
goalDirection: "lose" | "maintain" | "gain"
ratePctPerWeek: double                                  (the chosen weekly pace, within bounds)
kcalRange: { low: int, high: int }                      (the user-visible range, inside bounds)
kcalBounds: { min: int, max: int }                      (stored for audit; recomputed on every read)
protein: { minG: int, targetG: int, maxG: int }
fat: { minG: int, maxG: int }
carbs: { minG: int, maxG: int }
stepsGoal: int
inputsDigest: { weightKg, heightCm, ageYears, activityFactor, tdee, bmr, sexBasis }   (what the plan was computed from)
computedAt: Timestamp
lastKcalAdjustAt: Timestamp | absent
driftFromInitialKcal: int                               (cumulative review adjustment, section 15)
```

The plan is always RECOMPUTABLE from profile + weight entries + this document; the stored numbers are the user's current choice, and `kcalBounds` is recomputed and enforced on every read and every write path in Dart (the document is not the source of safety - the clamps are, section 13).

### 5.5 `users/{uid}/nutrition_plan_reviews/{isoWeek}` (client rw)

Key `yyyy-Www`. `{schema, decidedAt, decision: "keep"|"adjustKcal"|"adjustSteps"|"needMoreData"|"referProfessional", deltaKcal: int, deltaSteps: int, reasonCodes: [string], inputs: {weightSlopeKgPerWeek, intendedKgPerWeek, bfTrendPts?, dataPoints}}`. Keeps the "always explain why" record; readable history of the last 12 is shown.

### 5.6 `users/{uid}/food_entries/{entryId}` (client rw, shape-validated)

```
schema: 1
day: "yyyy-MM-dd"           local date of the meal
slot: "breakfast" | "lunch" | "dinner" | "snack"
loggedAt: Timestamp
name: string (<= 80)
source: "photo" | "describe" | "search" | "barcode" | "label" | "manual"
confidence: "low" | "medium" | "high"
items: [ FoodItem ] (1..30)
totals: { kcal: Range, proteinG: Range, carbsG: Range, fatG: Range }   Range = {low, mid, high} doubles >= 0
checkThese: [ { code: string, resolved: bool } ] (<= 8)
model: { id, version } | absent      (when AI-assisted)
```
`FoodItem = {foodRef: "gen:<id>" | "off:<barcode>" | "user:<id>" | "label", name (<= 80), grams: Range, per100g: {kcal, proteinG, carbsG, fatG}, matchQuality: "exact"|"close"|"weak"|"none", sourceId: "usda_fdc"|"open_food_facts"|"user"|"label_ocr"}`. `entryId` is a client UUID (idempotent retries). Day totals query: `where('day', '==', d)` (equality only, no composite index; sorted client-side).

### 5.7 `users/{uid}/saved_foods/{foodId}` (client rw)

User-created foods from label OCR / barcode fallback / manual entry: `{schema, name, per100g {...}, servingG?, barcode?, createdAt}`; <= 500 per user enforced client-side and by a rules `size` check on the document, not on the collection count (rules cannot count; documented limit).

### 5.8 `users/{uid}/usage/{day}` (existing, server-only)

Gains counters `bodyScanCreate`, `bodyScanEstimate`, `bodyScanDelete`, `analyzeMealPhoto`, `parseNutritionLabel`, `barcodeLookup`, `foodSearch` through the existing `enforceDailyQuota`. No schema change.

### 5.9 Top-level `nutrition_cache/{key}` (server-only, NOT user data)

Central cache of public nutrition-database responses, needed because Open Food Facts rate-limits per IP and Functions share egress IPs (FINDINGS): keys `off_<barcode>` (product, 30 d; negative 1 d), `usda_<fdcId>` (30 d), `q_<sha1(lang|query|scope)>` (search results, 7 d); `{schema, fetchedAt, expireAt (TTL field), found: bool, source, payload: {name, brand, per100g{...}, servingG?, completeness}}`. Contains no uid. Added to the data-lifecycle policy as EXEMPT ("shared reference data, no personal data"). Rules: `allow read, write: if false`. TTL policy on `expireAt` added to `firestore.indexes.json` `fieldOverrides` (same mechanism as `accountDeletionRetries`).

### 5.10 Cloud Storage

New PRIVATE bucket `<project>-bodyscan-private` (location EU, uniform bucket-level access, public access prevention ENFORCED, no `allUsers`), same naming convention as `<project>-videos-private`. Objects: `users/{uid}/scans/{scanId}/{front|side|back}.jpg` only (JPEG, face-region blurred, EXIF stripped, long edge <= 1280 px, <= 3 MB). Bucket lifecycle rule: delete objects older than 400 days (absolute backstop; the user-controlled retention is enforced by the purge job). Meal photos are NOT stored (D-27). `storage.rules` (default Firebase bucket protection) is specified in section 6.3.

### 5.11 Device-local (encrypted, existing store)

`scans/<id>.scan` AES-GCM sidecar (existing) gains the v2 fields (section 10); the original photos stay in the existing encrypted photo store. Meal thumbnails (optional, default on): `<docs>/progress_photos/<uid>/meals/<entryId>.jpg.enc` encrypted with the same cipher, deleted with the entry; never uploaded. Local preference keys: `body_scan.cloud_consent_prompted.v1.<uid>`, reminder prefs (section 19).

## 6. Security rules diffs and required emulator tests

### 6.1 `firestore.rules` - exact intent

**(a) Wildcard carve-outs.** In BOTH the `allow read` and `allow write` conditions of `match /users/{uid}/{coll}/{document=**}` add `&& coll != 'body_scans' && coll != 'body_scan_settings' && coll != 'weight_entries' && coll != 'nutrition_plan' && coll != 'nutrition_plan_reviews' && coll != 'food_entries' && coll != 'saved_foods'`. Without this, the explicit blocks below would be dead (Firestore allows a request if any matching rule allows). The explicit blocks re-grant exactly what is intended, so each read/write pair lives in one self-contained block (same posture as `recognised_models`). Extend the comment block above the wildcard with the new names.

**(b) New blocks** (all use `isOrdinaryUser()` so the canary identity gets nothing, CR-05):

| Path | read | create | update | delete | Shape / intent |
|---|---|---|---|---|---|
| `users/{uid}/body_scans/{scanId}` | owner | `false` (server only) | owner, ONLY `weightKg` and `clientNote` change: `request.resource.data.diff(resource.data).affectedKeys().hasOnly(['weightKg','clientNote'])`, `weightKg` number in [30, 300], `clientNote` string <= 200 | `false` (callable `deleteBodyScan` only) | The estimate, provider id, status and photo state are server-authored and a client can neither forge nor erase them. |
| `users/{uid}/body_scan_settings/{docId}` | owner | owner | owner | owner | `docId == 'main'`; `keys().hasOnly(['schema','cloudConsent','retentionDays','reminder'])`; `retentionDays in [0,30,90,365]`; `reminder.weekday` int 1..7, `reminder.minutes` int 0..1439, `reminder.enabled` bool; if `cloudConsent` present: `keys().hasOnly(['version','acceptedAt'])`, `version` int >= 1, `acceptedAt == request.time`. |
| `users/{uid}/weight_entries/{day}` | owner | owner | owner | owner | `day.matches('^[0-9]{4}-[0-9]{2}-[0-9]{2}$')`; `keys().hasOnly(['schema','kg','at','source'])`; `kg` number in [30, 300]; `source in ['manual','scan']`. |
| `users/{uid}/nutrition_plan/{docId}` | owner | owner | owner | owner | `docId == 'main'`; key allowlist per 5.4; `status`, `ownership`, `goalDirection` enum membership; HARD FLOOR backstop `kcalRange.low >= 1200`, `kcalRange.high <= 6000`, `low <= high`; `stepsGoal` int 2000..30000. The real, profile-dependent clamps live in Dart (section 13); this is the last line of defence against a forged or corrupted write, not the policy. |
| `users/{uid}/nutrition_plan_reviews/{week}` | owner | owner | `false` (history is immutable) | owner | `week.matches('^[0-9]{4}-W[0-9]{2}$')`; key allowlist per 5.5; `decision` enum; `reasonCodes` list size <= 8. |
| `users/{uid}/food_entries/{entryId}` | owner | owner | owner | owner | key allowlist per 5.6; `day` pattern; `slot in [...]`; `source in [...]`; `name` string <= 80; `items` list, `1 <= size <= 30`; `checkThese` list size <= 8; `totals` map with exactly `kcal, proteinG, carbsG, fatG`. Bounds the shape, not the bytes (rules cannot measure document size - stated limit). |
| `users/{uid}/saved_foods/{foodId}` | owner | owner | owner | owner | key allowlist per 5.7; `name` string <= 80; `per100g.*` numbers in [0, 1000]. |
| `nutrition_cache/{key}` | `false` | `false` | `false` | `false` | Admin SDK only. |

**(c) Health flags (device-only data stays device-only).** In `flagsAreStripped(f)`: add `'nutritionGuidance'` and `'foodAllergens'` to the `hasOnly` key list and add `&& f.get('nutritionGuidance', null) == null && f.get('foodAllergens', []).size() == 0`. The client's `stripSensitive` already blanks `health`; `HealthFlags.toJson` will now emit the two new keys, so WITHOUT this change every profile save from the new client is refused (fail-closed). **Rollout order: deploy rules first, then ship the client.** An old client never emits the keys, so the order is safe in that direction.

**(d) Profile document.** `users/{uid}/profile/{docId}` write gains `&& (!('nutrition' in request.resource.data) || request.resource.data.nutrition.keys().hasOnly(['schema','sexAtBirth','goalDirection','targetBodyFatPct','typicalDailySteps','mealsPerDay','excludedFoods','planOwnership','healthConnectChoice','completedAt']))`. Nothing in `nutrition` is health data by construction (allergens and the guidance answer are in `health.flags`).

### 6.2 Policy files (not run; updated in the same change)

`scripts/ci/data_lifecycle_policy.json`: one row per new collection with retention class BOTH (DELETE via `recursiveDelete(users/{uid})`, EXPORT via section 20.3) and `clientAccess` entries matching the table above (`CONDITIONAL` cells for `body_scans` update and `body_scan_settings`/`nutrition_plan` writes must name the emulator test that proves them); `nutrition_cache` = EXEMPT with reason. `core/DATA_INVENTORY_2026-08-11.csv/.md`: rows for each Firestore path, the new Storage bucket (`deleted_by_deleteAccount = yes`, `in_export = metadata only`), and the device-local stores.

### 6.3 Storage

There is no `storage.rules` today. Add `storage.rules` with a single deny-all rule (`match /{allPaths=**} { allow read, write: if false; }` under `service firebase.storage`) and a `"storage": { "rules": "storage.rules" }` block plus a `storage` emulator entry in `firebase.json`. Intent: no client can use the Firebase Storage SDK against the default bucket; the app does NOT add the `firebase_storage` plugin (VERIFY it is absent in `mobile/pubspec.yaml`). The body-scan bucket is a SEPARATE private bucket that is not governed by Firebase rules at all: it is reachable only through V4 signed URLs minted by the callables (and the Admin SDK), with public access prevention enforced. IAM provisioning for that bucket (operator step, NOT_RUN in this sprint): create the bucket; uniform bucket-level access; public access prevention enforced; grant the runtime SA `roles/storage.objectAdmin` on this bucket only; grant it `roles/iam.serviceAccountTokenCreator` on itself (same one-time step as `runbooks/video_bundle_import.md`); lifecycle delete at 400 days. Documented in a new `runbooks/body_scan_bucket.md`.

### 6.4 Required emulator tests (extend `functions/src/__rules__/firestore_rules.test.ts` and `data_access_policy.test.ts`; new `storage_rules.test.ts`)

1. Owner can read own `body_scans`; another uid cannot; canary token cannot.
2. Owner CANNOT create or delete a `body_scans` doc; CAN update `weightKg`/`clientNote`; CANNOT update `estimate`, `status`, `provider`, `photosState`, `photosExpireAt` (each asserted separately); a write mixing an allowed and a forbidden key is refused.
3. `weight_entries`: valid doc ok; bad day id, `kg` 10 or 400, unknown key, `source: "x"` refused.
4. `nutrition_plan`: valid ok; `kcalRange.low: 900` refused; `high < low` refused; unknown key refused; another user refused.
5. `nutrition_plan_reviews`: create ok, update refused, delete ok.
6. `food_entries`: valid ok; 31 items refused; unknown `slot`/`source` refused; unknown key refused; oversize `name` refused.
7. `body_scan_settings`: `retentionDays: 7` refused; `cloudConsent.acceptedAt` not equal to `request.time` refused.
8. Profile: write with `health.flags.nutritionGuidance = "reported"` REFUSED; with `foodAllergens: ["peanuts"]` REFUSED; with both empty ACCEPTED; with an unknown `nutrition` key REFUSED; with a valid `nutrition` map ACCEPTED.
9. Wildcard carve-out proof: a write to `users/{uid}/body_scans/x` that would pass the generic wildcard is refused (proves the exclusion list, not just the explicit block).
10. `nutrition_cache` unreadable/unwritable by clients.
11. Storage emulator: owner and anonymous read/write on any path refused.

## 7. Cloud Function contracts

New files under `functions/src/`: `body_scan/create.ts`, `body_scan/estimate.ts`, `body_scan/delete.ts`, `body_scan/purge.ts`, `body_scan/estimator.ts` (interface + registry), `body_scan/provisional_estimator.ts`, `body_scan/validate_estimate.ts`, plus the food files listed in section 2.3. All callables are `europe-west1`, require `request.auth`, call `noteAppCheck`, apply `enforceNonAnonymousForAi` (a persistent account is required - this is also the "why an account" story on the consent screen), and use a new capped profile `BODY_SCAN` in `scaling.ts`: `maxInstances: 10`, `enforceAppCheck: APP_CHECK_ENFORCED_AI` (the fail-closed flag - photo features follow the AI posture), `serviceAccount: RUNTIME_SA.data` (D-14; bucket IAM per 6.3). `analyzeMealPhoto` and `parseNutritionLabel` use the existing `AI_METERED` profile (they pay for Vertex calls); `lookupBarcode` and `searchFoods` use a capped `FOOD_LOOKUP` profile (`maxInstances: 10`, `enforceAppCheck: APP_CHECK_ENFORCED`, `serviceAccount: RUNTIME_SA.data`). Error codes are `HttpsError` with stable machine-readable `message` slugs the client maps to l10n; messages never contain user data.

### 7.1 `createBodyScan` - signed upload URL issuance

Request: `{ scanId: string, takenAtMs: number, subject: { sexAtBirth: "female"|"male"|"unspecified", ageYears: int 18..100, heightCm: int 120..230, weightKg: number 30..250 }, capture: { manualOverride: { front: bool, side: bool, back: bool } } }`.
Validation: strict types; `scanId` matches `^[A-Za-z0-9_-]{8,64}$`; `takenAtMs` within `[now - 7 d, now + 5 min]`; unknown keys ignored.
Order: auth -> App Check note -> non-anonymous -> validate -> `enforceDailyQuota(uid, "bodyScanCreate", quotaFor(30, provider))` -> existing doc lookup.
Idempotency: `done` -> return the stored entry unchanged; `pending` -> re-issue URLs; `failed` -> reset to `pending`; `cancelled` -> `failed-precondition: scan-cancelled`.
If `provider.requiresPhotos`: require `body_scan_settings/main.cloudConsent.version >= BODY_SCAN_CLOUD_CONSENT_VERSION` (server constant, 1) else `failed-precondition: consent-required`; mint three V4 PUT URLs for `users/{uid}/scans/{scanId}/{pose}.jpg`: `version: "v4"`, `action: "write"`, `expires: now + 10 min`, `contentType: "image/jpeg"`, `extensionHeaders: { "x-goog-content-length-range": "1024,3145728" }`; doc `photosState = awaiting_upload`.
Else (`requiresPhotos == false`, the PROVISIONAL provider): no URLs, `photosState = none`, and the client skips the upload stage.
Response: `{ scanId, status, provider: {id, version, provisional, requiresPhotos}, uploads?: { front|side|back: { url, headers: {"Content-Type", "x-goog-content-length-range"}, expiresAtMs } }, serverNowMs }`.
Failure modes: quota exhausted -> `resource-exhausted`; signing failure -> `internal` (client retries with backoff); Firestore unavailable -> `internal`.

### 7.2 `estimateBodyScan`

Request `{ scanId }`. Quota `bodyScanEstimate` = 14/day (charged before the provider call, refunded via `refundQuota` when the provider fails before returning output). Flow: load doc (must exist, `pending`); if `requiresPhotos`, for each pose read object metadata: exists, `contentType == image/jpeg`, `1024 <= size <= 3145728`, first bytes pass `sniffImageMimeType` (reuse `image_validation.ts`) else `failed-precondition: missing-upload:<pose list>` (client re-uploads); run `provider.estimate(...)` with a 25 s timeout; pass the output through `validateEstimate`; in ONE transaction write `estimate`, `status = done`, delete `pendingExpiresAt`, `photosState`/`photosExpireAt` per settings, `isBaseline` (no other `done` scan exists). If retention is 0 the objects are deleted inline right after success (best effort; the purge job is the backstop). Structured log event per call: `{operation: "bodyScanEstimate", outcome, latencyMs, providerId, providerVersion}` - no uid, no body metrics (the `noteAppCheck` rationale: Cloud Logging is outside `users/{uid}` and cannot be erased by `deleteAccount`).
`validateEstimate`: numbers finite; `3 <= low <= value <= high <= 60`; `high - low <= 20`; `confidence` in enum; `checkCodes` subset of the closed `CheckCode` list; `modelId`/`modelVersion` non-empty <= 64 chars. Violation -> `internal: provider-output-invalid` and the doc stays `pending` (retryable), never a silent clamp of nonsense.

### 7.3 `deleteBodyScan`

Request `{ scanId, photosOnly: bool }`. Deletes every object under `users/{uid}/scans/{scanId}/` (idempotent). `photosOnly`: set `photosState = deleted`, `photosDeletedAt = now`. Otherwise delete the document. Light quota `bodyScanDelete` 60/day. The client then deletes the local scan/photos through the existing `confirmAndDeleteScan` path; an offline delete is queued as a `pendingRemoteDelete` job (section 10).

### 7.4 `purgeExpiredBodyScanPhotos` (scheduled)

`onSchedule("30 3 * * *")`, region `europe-west1`, timeout 300 s, stop starting new work after 240 s (pattern: `reconcileAccountDeletions`). Collection-group queries from 5.1, pages of 200. For each hit: delete objects, set `photosState = deleted` (stored) or `status = cancelled` (expired pending). Idempotent; failures are logged by scan id only and retried on the next run.

### 7.5 Food callables: `analyzeMealPhoto`, `parseNutritionLabel`, `lookupBarcode`, `searchFoods`

Specified in sections 17.3-17.6. They are added to `QUOTAS` (`analyzeMealPhoto: 60`, `parseNutritionLabel: 60`, `barcodeLookup: 120`, `foodSearch: 150`), `AI_GATEWAY_OPERATIONS` (adds `"analyzeMealPhoto"` and `"parseNutritionLabel"`, which automatically extends the monitoring definitions that derive from the tuple - the implementer must update `monitoring/ai_gateway_definitions.ts` expectations, `release_guard.ts` callable list and `__tests__/discover_callables.ts`).

### 7.6 Account deletion and export hooks

`sweepAccountData(uid)` additionally runs `getStorage().bucket(BODY_SCAN_BUCKET).deleteFiles({ prefix: "users/" + uid + "/", force: true })`; it THROWS on failure so the durable reconciler retries (`accountDeletionRetries`), and is idempotent. `account_export.ts` additions are in 20.3. Tests: extend `delete_account.test.ts` and `account_deletion_reconcile.test.ts` mocks for the storage call; extend `account_export.test.ts`.

### 7.7 Function test plan (jest, focused)

`create` (validation table, idempotency states, consent gate, quota, signed URL options incl. content-type and length-range), `estimate` (missing upload, bad signature, provider error refund, output validation, baseline flag, retention 0 inline delete), `delete`, `purge` (pagination, idempotency, time budget), provisional estimator (formula vectors, clamps), meal and barcode callables (section 17), `sweepAccountData` storage call. A `FakePhotoEstimator` (test-only, `requiresPhotos: true`) drives the upload path end to end so swapping a real provider needs no client change.

## 8. Estimator provider interface and the PROVISIONAL estimator

```ts
export interface BodyCompositionEstimator {
  readonly id: string;           // stable, e.g. "provisional-anthropometric"
  readonly version: string;      // e.g. "deurenberg-1991-v0"
  readonly provisional: boolean; // true => the UI shows the PROVISIONAL banner
  readonly requiresPhotos: boolean;
  estimate(input: EstimatorInput): Promise<EstimatorOutput>;
}
interface EstimatorInput { scanId: string; subject: Subject; photos?: { front: Buffer; side: Buffer; back: Buffer }; capture: { manualOverride: Record<Pose, boolean> } }
interface EstimatorOutput { bodyFatPct: number; rangeLowPct: number; rangeHighPct: number; confidence: "low"|"medium"|"high"; checkCodes: CheckCode[] }
```

Registry: `BODY_SCAN_PROVIDER` env var selects the provider (`provisional-anthropometric` default; `licensed-api` reserved and throws `failed-precondition: provider-not-configured` until an operator wires a vendor; `test-fake` only when running under the emulator/jest). The stored `provider` and `estimate.modelId/modelVersion` make every historical number traceable to the exact estimator.

**PROVISIONAL estimator (D-3).** There is NO validated photo-based body-fat model in this repository or in the sprint. The only real, tested body-fat helper is `navyBodyFatPercent` (needs waist/neck measurements the app does not collect). Therefore the shipped estimator is the Deurenberg et al. (1991, Br J Nutr 65:105-114) anthropometric equation: `BF% = 1.20 * BMI + 0.23 * age - 10.8 * s - 5.4`, `s = 1` male, `0` female, `0.5` unspecified. It uses ONLY height, weight, age and sex; the photos are ignored, hence `requiresPhotos = false` and **no photo leaves the device while this provider is active** (uploading images that no model reads would be a privacy cost with no benefit). Output: value clamped to [5, 55]; range half-width is the named constant `PROVISIONAL_HALF_WIDTH_PTS = 5.0`, a deliberately wide PLACEHOLDER that is NOT a measured accuracy (no accuracy number is claimed anywhere); `confidence = "low"`; `checkCodes` always contains `provisionalEstimator`; `modelId = "provisional-anthropometric"`, `modelVersion = "deurenberg-1991-v0"`, `provisional = true`.

Consequences, all intentional and honest: (a) the result screen carries a permanent banner "Rough estimate from your height, weight and age. A photo-analysis model is not connected yet." (b) because the half-width is 5.0, the noise threshold (12.3) is about 7 points, so "change vs last scan" correctly reads "no meaningful change" until a real provider reports tighter ranges, rather than inventing a trend from weight alone; (c) capture, local encrypted storage, comparison, history, trend and plan logic are fully real and exercised. The limitation is recorded in `core/DECISION_LOG.md` (D-3) and in the final report.

**Choosing a real provider (OPEN Q-1).** Criteria to evaluate: published validation against a reference method (DXA) with error stated; contractual no-retention / no-training on photos; EU processing and a DPA; acceptance of pre-blurred JPEG; price per scan; availability. An in-house model is a research project and is not in this sprint. Swapping is a server-config change plus one adapter file.

## 9. Face blurring, upload pipeline, retention

**DECISION D-4: blur ON DEVICE, before upload, fail closed.** Justification: (1) the server and Cloud Logging never receive an unblurred face, so there is nothing to retain, leak, subpoena or mis-delete; (2) it works offline until upload; (3) the pose landmarks are already measured at the shutter frame (`ScanShot.landmarks`), so no new ML dependency or model is needed; (4) a server-side blur would require trusting and retaining the raw face image first, which contradicts "face-blurring before any server-side retention".

Algorithm (`body_scan/data/face_region.dart` pure geometry + `state/blur_service.dart` pixels in an isolate via `compute`, using the `image` package already in `pubspec`):
1. Head landmarks = nose, eyes, ears, mouth corners with `likelihood >= 0.3` (names per `LandmarkType.name` - VERIFY in `form_check/data/pose_landmark.dart`). Centre `c` = mean of those; `s` = shoulder width (or `0.45 * torso length` if one shoulder is hidden).
2. Radius `r = max(1.35 * maxDistance(c, head landmark), 0.40 * s)`. Blur box = square centred at `c`, half-side `1.5 * r`, extended `0.3 * r` upward (hair), clamped to the image, plus a 15% margin because the landmarks come from the preview frame, not the still.
3. No head landmarks (typical back view): crown estimate from the shoulder line as in `ReadinessConfig` (height `H` from shoulder-to-ankle span / 0.78; centre `shoulderMid.y - 0.10 * H`, half-side `0.14 * H`).
4. Neither head nor shoulders available, or the still is missing landmarks (manual shutter without a detected body): **do not upload**; show "We could not protect your face in this photo. Retake or keep it on this device only." (`blurUnavailable`).
5. Pixelate the box with block size `max(8 px, side / 10)` then two box-blur passes (irreversible), after resizing to long edge 1280 px; re-encode JPEG quality 85 from raw pixels so EXIF/GPS/ICC are NOT copied; assert `<= 3 MB`.
6. The blurred bytes live in memory only; nothing unblurred is written outside the existing encrypted store.

Residual risks stated plainly (consent copy and risks section): other identifying marks (tattoos, scars) are not blurred; landmark misses fail closed; the server cannot verify blurring.

**Upload.** Per pose: `PUT` the blurred JPEG with the returned headers (via `dio`, progress callback), up to 3 attempts with 1/2/4 s backoff; a 403/expired URL triggers an idempotent `createBodyScan` for fresh URLs; then `estimateBodyScan`. The three uploads run sequentially to keep memory low.

**Retention (user-controlled).** Setting `retentionDays` in {0 (default: delete after analysis), 30, 90, 365} in `body_scan_settings/main`; enforced by the inline delete (0) and the daily purge; the 400-day bucket lifecycle is only a backstop. "Delete this scan's photos" is one tap on the result and history screens (calls `deleteBodyScan(photosOnly)` then the local delete). The user can also switch the cloud analysis off entirely; capture/compare still work locally.

**Consent (D-5).** A separate `CloudConsentSheet` is shown before the FIRST upload and ONLY when the active provider `requiresPhotos` (so with the provisional estimator it is never shown). It states: why an account is needed; exactly what is sent (3 face-blurred, metadata-free images + height/weight/age/sex-at-birth); where it is processed; who receives it; retention choice with the default; one-tap deletion; no analytics SDK receives photos or body metrics; not medical advice. Acceptance writes `cloudConsent {version, acceptedAt}` and bumps on material change. The existing local photo consent (`photo_consent.dart`) is unchanged and still gates the camera.

## 10. Scan state machine, offline queue, resume

Pure Dart `BodyScanFlowMachine` (`body_scan/data/body_scan_flow_machine.dart`): `State next(State, Event)` with no side effects; a separate job runner executes effects.

States: `idle`, `intro`, `weightPrompt`, `capturing(pose)`, `reviewing`, `savingLocal`, `queued`, `uploading(pose)`, `analysing`, `verifying`, `done`, `failed(reason, retriable)`, `cancelled`.

| From | Event | To | Effect |
|---|---|---|---|
| idle | `open` | intro | access check via `scanAccessProvider` (unchanged gate) |
| intro | `start` | weightPrompt if latest weight entry is >= 3 days old or missing, else capturing(front) | |
| weightPrompt | `weightLogged` / `skipWeight` | capturing(front) | write `weight_entries/<day>` on log |
| capturing(p) | `captured(p)` | capturing(next) / reviewing after back | existing auto/manual shutter; manual capture while not ready sets `manualOverride[p]` |
| reviewing | `retake(p)` | capturing(p) | existing |
| reviewing | `confirm` | savingLocal | existing encrypted save through the progress-photo path |
| savingLocal | `saved` | queued | `ScanRecord.analysis = queued`; reminder sync |
| queued | `online` | uploading(front) or analysing (provider without photos) | `createBodyScan` |
| uploading(p) | `uploaded(p)` | uploading(next) / analysing | blur then PUT |
| analysing | `estimated` | verifying | `estimateBodyScan` |
| verifying | `verified` | done | plausibility + trend (pure), result screen |
| any active | `cancel` | cancelled | abort in-flight HTTP; call `deleteBodyScan` (queued if offline) for any uploaded objects; offer "keep photos on this device" or "delete scan" |
| any active | `error(retriable)` | `queued` with `attempt + 1` | backoff `min(2^attempt, 300)` s, max 5 attempts, then `failed(retriable: true)` and a Retry button |
| failed | `retry` | queued | attempt reset |
| any | `appKilled` | (state is persisted) | on next foreground the job runner re-reads non-terminal `analysis` blocks and resumes |

Persistence: `ScanRecord` v2 adds `analysis: { status: queued|uploading|analysing|done|failed|cancelled, attempt: int, remoteStatus?: string, lastError?: slug, updatedAt }`, `weightKg?`, `capture: { manualOverride }`, and `pendingRemoteDelete: bool`, written by the existing atomic temp-file + rename `ScanStore.save`. `ScanRecord.tryFromJson` keeps accepting v1 (missing `analysis` = legacy local-only scan, never auto-uploaded: D-6). Resume is idempotent end to end because `scanId` = local id and all three callables are idempotent on it.

Offline queue: the queue IS the set of `ScanRecord`s with non-terminal `analysis`. The runner (`body_scan_job_runner.dart`) runs on app foreground, on connectivity regain (`connectivity_plus` VERIFY in pubspec; else a retry timer), and when the user opens Progress; never in a background isolate (iOS parity: no background execution is assumed). Concurrency: one scan at a time; a second scan taken while one is queued is queued behind it.

Stage UI mapping (section 3 stage names are ours): `Photos secured` (upload done, or "kept on this device" when the provider needs no photos), `Body composition` (estimate call), `Plausibility check` (pure), `Trend verification` (pure), `Result saved` (doc visible), with elapsed time and a Cancel button; each stage is a live-region announcement.

## 11. Live capture checks and gating

Reuse `ReadinessEvaluator` + `AutoShutterMachine` unchanged in logic. Changes: (1) `ScanCamera` exposes `luminance` (mean frame brightness 0..1 from `core/camera/frame_brightness.dart averageFrameBrightness` - VERIFY signature and that the session already samples frames; today the screen passes the fixed values 0.1/0.5 derived from `lowLight`), so over-exposure is detected and `ReadinessConfig.minLuminance 0.25 / maxLuminance 0.92` become real checks; (2) the setup panel shows four rows with icon + text + state: **Distance** (Move back / Move closer / Good), **Lighting** (Improve lighting / Too bright / Good), **Position** (Centre yourself / Good), **Pose** (Stand straight and face the camera / Turn sideways / Turn around / Good); (3) the skeleton overlay (`SkeletonOverlay`, CustomPainter) draws the major joints and bones from the latest `PoseFrame` through the existing projection helpers (`ui/scan_landmark_mapper.dart`, `form_check/data/pose_projection.dart` - VERIFY), tinted by readiness but never by colour alone.

**Gating.** Automatic capture requires all four checks to pass continuously for `holdMs = 1000`, then a 3-2-1 countdown, and ANY lost readiness cancels (existing, no grace window). A manual shutter stays available (pose detection fails in real gyms: hair, loose clothing, backlight - existing design note); using it while not ready records `manualOverride[pose] = true`, which adds `manualCapture` to that scan's check items and lowers its displayed confidence one level. The thresholds remain "opening values" (existing doc comment): calibrating them on the operator's phone is an explicit test/NOT_RUN item, not an assumption.

## 12. Result math

All in `body_scan/data/` (pure Dart).

**12.1 Display.** Value `v`, range `[l, h]`, half-width `hw = (h - l) / 2`, one decimal. With recorded weight `W`: fat mass `FM = W * v / 100`, range `W * [l, h] / 100`; lean mass `LM = W - FM`, range `[W - FM_high, W - FM_low]`. Editing the recorded weight recomputes these on the client; the estimate itself is unchanged.

**12.2 Disclosure.** Every estimate is rendered as "likely range", never a bare number, with the fixed plain-language limit: "Single readings can vary by about 1-2 points even with a good model; the trend matters more than one scan." For `provisional` results the stronger banner of section 8 applies.

**12.3 Noise threshold ("no meaningful change").** For a new reading `(v_t, hw_t)` and the previous reading `(v_p, hw_p)`: `noisePts = max(1.0, sqrt(hw_t^2 + hw_p^2))`. `|v_t - v_p| <= noisePts` -> label `noMeaningfulChange`; otherwise `down` / `up`. The 4-week trend label compares the smoothed value now with the smoothed value 28 days earlier (needs >= 3 readings in the window): meaningful when `|S_t - S_{t-28d}| > max(1.0, 0.8 * mean(hw))`. The threshold is shown in the explanation text ("changes smaller than +-X points are within measurement noise"). With the provisional provider `hw = 5` so `noisePts ~ 7.1`: every weekly change reads "no meaningful change" by construction (section 8).

**12.4 Plausibility and trend verification (client, pure).** `estimateOutOfRange` (value outside [3, 60]) -> reject display and keep the scan unresolved with a retry; `estimateFarFromProfile` (`|v - deurenberg(profile)| > 12`) -> keep, confidence one level lower, chip; `weightJump` (recorded weight differs from the previous scan by > 3 kg within 7 days) -> chip "check your weight"; `wideRange` (`hw > 4`) -> confidence `low`; `largeJumpVsTrend` (`|v_t - S_{t-1}| > max(4.0, 2.5 * hw_t)`) -> chip, and the smoothing update uses the winsorised input below (the raw dot is still plotted and marked).

**12.5 Smoothing (exact).** Irregular-interval exponential smoothing: `S_0 = x_0`; `S_t = S_{t-1} + alpha_t * (x'_t - S_{t-1})`, `alpha_t = 1 - exp(-dDays / tau)`, `dDays = clamp(days since previous reading, 0.5, 28)`, `x'_t = clamp(x_t, S_{t-1} - 4.0, S_{t-1} + 4.0)` (winsorised for body fat only). Parameters: `tau_bf = 21 days` (weekly scans give `alpha ~ 0.28`, memory about 3-4 scans, damps +-1-2 point noise without hiding a real 4-8 week change); `tau_weight = 7 days` (daily weigh-ins give `alpha ~ 0.13`). Rationale for not using Holt's linear method: with 6-12 noisy points it over-shoots and invents a trend; a robust slope is computed separately: **weight slope** = `7 * median over pairs (i<j, dDays >= 2) of (w_j - w_i) / (d_j - d_i)` (Theil-Sen) on the raw entries of the last 21 days, requiring >= 3 entries spanning >= 7 days, else `null` ("not enough data"). Chart: last 12 scans, dots = raw readings with range whiskers, line = `S_t`; legend states that dots are single noisy readings and the line is the smoothed trend; a data table is provided as the accessible alternative.

**12.6 Goal progress.** `pointsToGoal = S_t - targetBodyFatPct` (null when no BF target; then weight-based progress `weightTargetKg` is shown). Start value = baseline scan's raw value.

**12.7 Closed check-item codes (`CheckCode`, l10n keyed, mapped to actions):** `provisionalEstimator`, `manualCapture`, `poorLighting`, `partialBody`, `looseClothing`, `poseMismatch`, `weightMissing`, `weightStale` (> 7 days), `weightJump`, `wideRange`, `estimateFarFromProfile`, `largeJumpVsTrend`, `blurUnavailable`. Free text from any provider is never displayed (closed set keeps it translatable and removes a prompt-injection surface).

## 13. Nutrition maths and safety clamps

Pure Dart in `nutrition_plan/data/` (`energy_math.dart`, `plan_calculator.dart`, `safety_clamps.dart`). Provenance tags used throughout this document: **[PUB]** published formula or guideline, **[OBS]** observed behaviour in the operator's reference material (as described in the brief), **[OWN]** our own conservative choice. Section 29 consolidates every number with its tag.

### 13.1 Inputs resolved by `NutritionInputs`

Weight `W` = latest `weight_entries` value within 14 days, else `profile.personal.weightCurrentKg` (flagged `weightStale`); height `H` cm; age `A` = `PersonalInfo.ageAt(year)`; `BMI = W / (H/100)^2`; sex basis `s`: `NutritionPrefs.sexAtBirth`, else `gender` male/female, else `unspecified`; activity from `PersonalInfo.activityLevel`; typical steps from `NutritionPrefs.typicalDailySteps` or the 14-day median steps from `HealthService.readSnapshots` when connected. Any required input missing -> `status = needsProfile` listing exactly what is missing (`missingNutritionInputs`), no plan.

### 13.2 Energy

- BMR [PUB, Mifflin & St Jeor 1990, Am J Clin Nutr 51:241-247]: `BMR = 10*W + 6.25*H - 5*A + c`, `c = +5` male, `-161` female, `-78` unspecified ([OWN] midpoint, used for non-binary / prefer-not-to-say / unknown).
- Activity factor `f` [PUB convention for PAL multipliers 1.2 / 1.375 / 1.55 / 1.725]: `sedentary 1.2`, `moderatelyActive 1.375`, `active 1.55`, `veryActive 1.725` [OWN mapping of our four-value `ActivityLevel`; the 1.9 "extra active" level is deliberately NOT used]. Steps cross-check [OWN]: `<5,000 -> 1.2`, `5,000-7,499 -> 1.375`, `7,500-9,999 -> 1.55`, `>=10,000 -> 1.725`; the factor used is the LOWER of the questionnaire factor and the steps factor when both exist (conservative: never over-estimate TDEE).
- `TDEE = BMR * f`. Exercise calories are NOT added back (D-29): the factor already averages habitual activity and the weekly review corrects residual error from the observed weight trend.

### 13.3 Goal energy and rates

Weekly pace as % of bodyweight [OWN, within PUB ranges: public-health guidance of about 0.5-1 kg/week, e.g. NHS and CDC weight-loss pages; Helms, Aragon & Fitschen 2014, J Int Soc Sports Nutr 11:20 for 0.5-1.0 %/week]:

| Goal | default rate | max rate | absolute cap |
|---|---|---|---|
| lose, BMI < 25 | 0.50 %/wk | 0.75 %/wk | 0.5 kg/wk |
| lose, 25 <= BMI < 30 | 0.75 %/wk | 1.00 %/wk | 1.0 kg/wk |
| lose, BMI >= 30 | 1.00 %/wk | 1.00 %/wk | 1.0 kg/wk |
| gain muscle | 0.25 %/wk | 0.50 %/wk | 0.5 kg/wk |
| maintain | 0 | 0 | - |

`kgPerWeek = rate/100 * W`; energy per kg of body-mass change = 7,700 kcal [PUB, Wishnofsky rule 3,500 kcal/lb, known to over-state long-run change - acceptable because the weekly review closes the loop]. `dailyDelta = kgPerWeek * 7700 / 7`.

- lose: `deficit = min(dailyDelta, 0.25 * TDEE, TDEE - floor)`; `target = TDEE - deficit` [0.25 cap OWN].
- gain: `surplus = clamp(dailyDelta, 100, min(500, 0.15 * TDEE))`; `target = TDEE + surplus` [OWN].
- maintain: `target = TDEE`.
- Calorie RANGE [OWN]: `low = round10(target - 150)`, `high = round10(target + 150)`; then lose: `high <= TDEE`, gain: `low >= TDEE`; always `low >= floor`.
- Slider BOUNDS [OWN]: lose `[max(floor, TDEE - maxDeficit), TDEE]` with `maxDeficit = min(0.25*TDEE, maxRateKg*7700/7)`; maintain `[max(floor, TDEE - 300), TDEE + 300]`; gain `[TDEE, TDEE + min(500, 0.15*TDEE)]`. The user range width is clamped to `[100, 400]` kcal and must lie inside the bounds; the editor never produces a value outside them and the same function re-validates on every load and before every write.
- Calorie floor [OWN, informed by widely used consumer minimums of about 1,200 kcal for women and 1,500 kcal for men without medical supervision]: `floor = max(absFloor, round(BMR))`, `absFloor = 1,200` female, `1,500` male and unspecified. Because `TDEE >= 1.2 * BMR >= floor + 0.2*BMR`, the slider interval is never empty.
- BMI guards: `BMI < 18.5` -> `goalDirection = lose` is refused and coerced to `maintain` with message `underweightNoDeficit`; `18.5 <= BMI < 20` -> deficit allowed only at the `BMI < 25` row's rate capped at 0.25 %/wk; target weight whose BMI < 18.5 is rejected (`targetBelowHealthyRange`).

### 13.4 Macros (ranges, with a reference weight)

`Wref = W` if `BMI <= 30`, else `30 * (H/100)^2` (protein is not scaled to excess mass) [OWN].

- Protein per kg of `Wref` [PUB: ISSN position stand, Jager et al. 2017, J Int Soc Sports Nutr 14:20: 1.4-2.0 g/kg for active adults; Morton et al. 2018, Br J Sports Med 52:376: benefit plateaus near 1.6 g/kg, upper 95% CI 2.2; RDA 0.8 g/kg as the absolute lower bound]: **minimum** 1.4 maintain, 1.6 lose/gain [OWN choice inside the range]; **target** 1.6 maintain, 2.0 lose, 1.8 gain [OWN]; **maximum** 2.2 [PUB upper CI], also `<= 220 g` and `<= 40 %` of `kcalMid` [OWN]. The "protein minimum" shown to the user is the minimum.
- Fat [PUB: acceptable macronutrient distribution range 20-35 % of energy, IOM 2005 DRI report]: `fatMin = max(0.6 * Wref, 0.20 * kcalMid / 9)` g, `fatMax = 0.35 * kcalMid / 9` g [0.6 g/kg OWN].
- Carbohydrate: `carbMax = (kcalHigh - 4*proteinMin - 9*fatMin) / 4`, `carbMin = max(100, (kcalLow - 4*proteinMax - 9*fatMax) / 4)` [100 g OWN], clamped so `carbMin <= carbMax`. Point targets for the plan header: protein target above, fat 25 % of `kcalMid` (bounded by min/max), carbs the remainder; if remainder < 100 g, fat moves toward `fatMin`, then protein toward its minimum, and the plan is flagged `lowCarbBySafety`. Macro intervals are independent bounds, not additive; the UI states this.
- Display rounding: kcal to 10, grams to 1. A high-protein advisory line ("very high protein intake is not suitable for everyone; talk to a professional if you have a kidney condition") is shown with the protein card - generic, no inference from stored health text (the free-text health fields are never read, `health_flags.dart` ruling).

### 13.5 Steps goal

`base = typical steps` (self-reported bucket midpoint or Health Connect 14-day median) else by activity [OWN]: sedentary 6,000, moderate 7,500, active 9,000, very active 10,000. `stepsGoal = clamp(roundTo500(base + 1,000), 6,000, 12,000)` for `coached`/`shared` computed goals [OWN]; a user-set goal may be 2,000-30,000 (the rules backstop). Auto-adjust (coached only, toggle on): +1,000 per review at most, never above 12,000, never reduced automatically.

### 13.6 Clamp table (all are named constants in `safety_clamps.dart`; a unit test asserts each)

| Clamp | Value | Source |
|---|---|---|
| Minimum age | 18 (`PersonalInfo.lowestAgeAt >= 18`; unknown age = no plan) | existing `kMinScanAge`/age policy + [OWN] |
| Absolute kcal floor | 1,200 F / 1,500 M and unspecified | [OWN] |
| Relative floor | >= round(BMR) | [OWN] |
| Max daily deficit | `min(25 % TDEE, maxRate*7700/7)` | [OWN] |
| Max weekly loss | 0.5 / 0.75 / 1.0 %/wk per BMI row, absolute 0.5-1.0 kg/wk | [OWN] over [PUB] ranges |
| Max surplus | `min(500, 15 % TDEE)` | [OWN] |
| Max weekly gain | 0.5 %/wk, 0.5 kg/wk | [OWN] |
| Underweight guard | BMI < 18.5 -> no deficit | WHO adult BMI band (existing `bandFor`) |
| Protein | min 1.4/1.6 g/kg, max 2.2 g/kg, <= 220 g, <= 40 % kcal | [PUB]+[OWN] |
| Fat | 20-35 % kcal, >= 0.6 g/kg | [PUB]+[OWN] |
| Carbs | >= 100 g | [OWN] |
| Steps goal (computed) | 6,000-12,000 | [OWN] |
| Review kcal step | +-150 kcal, cooldown 14 days, cumulative drift +-400 kcal | [OWN] |
| Range width | 100-400 kcal | [OWN] |

## 14. Exclusions and the neutral "talk to a professional" behaviour

`NutritionEligibility evaluate(profile, now)` returns exactly one of: `eligible`, `referProfessional(reasons)`, `needsAnswer(question)`, `needsProfile(missing)`. First match wins, in this order:

| # | Condition | Source field | Result |
|---|---|---|---|
| 1 | age unknown | `personal.lowestAgeAt(year) == null` | `needsProfile(birthYear)` |
| 2 | under 18 (conservatively: could still be 17) | `lowestAgeAt(year) < 18` | `referProfessional(underAge)` |
| 3 | pregnant / breastfeeding / postpartum reported | `health.flags.professionalGuidance == reported` (F014 question; its wording is widened to name breastfeeding - VERIFY the current EN/RU text of `healthStepProfessionalGuidance`) | `referProfessional(guidance)` |
| 4 | eating-disorder history or clinician nutrition supervision reported | NEW `health.flags.nutritionGuidance == reported` | `referProfessional(guidance)` |
| 5 | clinician advised against exercise, or surgery under restrictions | existing `clinicianAdvice == advisedAgainstExercise`, `surgery == underRestrictions` | `referProfessional(clinician)` (D-9: conservative) |
| 6 | nutrition safety question never answered | `nutritionGuidance == null` | `needsAnswer(nutritionGuidance)` - the coach is locked, never assumed clear (same "unanswered is not clear" doctrine as PAR-Q) |
| 7 | pregnancy question never answered | `professionalGuidance == null` | `needsAnswer(professionalGuidance)` |
| 8 | other inputs missing | height, weight, sex basis, activity | `needsProfile(list)` |
| 9 | otherwise | | `eligible` |

Other health flags (blood pressure, movement restrictions) are not nutrition exclusions; the generic "not medical advice" line applies. Free-text health fields are never parsed (existing Gate M ruling).

**Neutral behaviour for `referProfessional`.** The plan, the kcal ring, macro numbers, the steps goal, the diary and the home nutrition card show NO numbers; the single screen `ProfessionalNotice` says, in plain non-alarming language and without naming the reason: "We can't give personalised nutrition targets for your situation. A doctor, dietitian or other qualified professional can help you with this." with a link to the data-sources/limits page; nothing about eating disorders or pregnancy is stated back to the user, and nothing about the reason is stored (the stored value is the generic flag, matching F014's privacy rationale). Workout and scan features follow their own existing gates. Body-scan capture stays available only to adults per `ScanAccess`; for users with the nutrition `referProfessional` verdict from reasons 3-5 the scan result screen hides the plan decision and next-week nutrition actions (kept: the measurement itself and its honest range).

`NutritionGuidanceNeed {none, reported}` is added to `health_flags.dart` mirroring `ProfessionalGuidanceNeed` exactly: nullable, generic name on the wire, no "prefer not to say" (indistinguishable from unanswered, which already locks), device-only (`stripSensitive`, rules `flagsAreStripped`). `foodAllergens: Set<FoodAllergen>` (closed EU-14 list: gluten, crustaceans, eggs, fish, peanuts, soy, milk, treeNuts, celery, mustard, sesame, sulphites, lupin, molluscs) joins the same class; it participates in `isEmpty` (not in `isUnanswered`), `==`, `hashCode`, `toJson`, `fromJson` (unknown names dropped), `copyWith`. The F014 lesson (a field added to the model and serialiser but not to the guarding list) is why section 6.1(c) and the tests in 6.4 case 8 exist.

## 15. Weekly review: client-side pure logic

**DECISION D-8: client-side, not a scheduled function.** The deciding facts: (1) the exclusion inputs (`nutritionGuidance`, `professionalGuidance`, allergens) are device-only by an existing privacy promise and Cloud Functions cannot and must not read them; a server job would either skip the safety check or need the data uploaded; (2) inputs are tiny (a 21-day weight series, the plan, one scan trend); (3) the logic is pure and therefore directly unit-testable; (4) no new server surface, cost or IAM; (5) works offline. Cost accepted: the review runs only when the app is opened; the weekly scan reminder doubles as the nudge. One review per ISO week, idempotent by `nutrition_plan_reviews/{yyyy-Www}`; it runs when the Plan screen or Home card is first shown in a new week and immediately after a scan reaches `done`.

`WeeklyReviewDecision decide(ReviewInput)`; `ReviewInput` = plan, bounds (recomputed), eligibility, ownership, autoAdjust, `weightSlopeKgPerWeek?`, `weightPoints`, `spanDays`, `intendedKgPerWeek`, last two reviews' classifications, `daysSinceLastKcalAdjust`, `driftFromInitialKcal`, optional smoothed body-fat trend (meaningful or not), `now`.

1. Not `eligible` -> `referProfessional` (no numbers).
2. `weightPoints < 3` or `spanDays < 7` -> `needMoreData` (keep plan, say what is needed).
3. Tolerance `tol = max(0.15, 0.25 * |intended|)` kg/wk [OWN]; `e = slope - intended`. Classification: `onTrack` if `|e| <= tol`; for LOSE: `behind` if `e > tol`, `ahead` if `e < -tol`; for GAIN: `behind` if `e < -tol`, `ahead` if `e > tol`; for MAINTAIN: `behind` if `slope > 0.25 % W/wk` over two reviews -> treated as drift up (`-100`), `slope < -0.25 % W/wk` -> drift down (`+100`) [OWN].
4. `ahead` beyond `maxRateKg * 1.25` (loss/gain faster than allowed) -> immediate bounded correction toward maintenance, `+150` (loss) or `-150` (gain), reason `tooFast`; no waiting period.
5. `behind` requires TWO consecutive `behind` classifications (current + previous review) and `daysSinceLastKcalAdjust >= 14` [OWN]. Then in this order: (a) if `autoAdjust.steps` and ownership allows and `stepsGoal + 1,000 <= 12,000`: `adjustSteps(+1,000)`; (b) else kcal: LOSE `-150`, GAIN `+150` but only if the resulting range stays inside the recomputed bounds - if not, `keep` with reason `atSafetyLimit` and the explanation "your plan is already at its safe limit; consider a longer timeframe or professional advice".
6. Recomposition rule: if weight is `onTrack`/flat and the smoothed body-fat trend is meaningfully down -> `keep`, reason `recomposition`.
7. `|driftFromInitialKcal + delta| > 400` -> `needRecalculation` (ask the user to review profile inputs; no change).
8. Every outcome carries `reasonCodes` (closed list, l10n) and numeric `inputs`, stored in the review document and rendered as a plain-language "why" card. Output never violates bounds: `clampToBounds` runs last and the decision is downgraded to `keep(atSafetyLimit)` rather than silently truncated beyond the bounds.

Ownership semantics applied to the decision: `coached` -> applied automatically, user notified with a 7-day "undo" (previous range stored on the review doc); `shared` -> proposed, applied only on accept; `manual` -> never changed, the decision is shown as an "insight" only (section 18). The same function is used by the post-scan "This week's plan decision" screen (with the body-fat trend input), so there is one decision path.

## 16. Onboarding diff and "complete your nutrition profile"

### 16.1 Reuse (nothing asked twice)

| Need | Existing source | Reused |
|---|---|---|
| birth year, gender, height, weight, target weight, activity level | `step_personal` -> `PersonalInfo` | yes |
| goal | `step_goal_and_level` -> `FitnessGoals` (`weightLoss`, `muscleGain`, `primary`) | default for goal direction |
| diet pattern | `step_lifestyle` -> `Lifestyle.diet` | yes (+ `pescatarian`) |
| sleep hours | `step_lifestyle` -> `Lifestyle.sleepHoursPerNight` | yes (shown, not re-asked; advisory only, not in the maths) |
| schedule, equipment, barriers, injuries | existing steps | unchanged |
| pregnancy/breastfeeding | `step_health_flags` -> `professionalGuidance` | yes (wording widened) |
| PAR-Q+ | `step_screening` | unchanged (workout gate, not a nutrition gate) |

### 16.2 Additions

- **`OnboardingStep.nutrition`**, new file `onboarding/steps/step_nutrition.dart`, inserted in `kOnboardingOrder` after `lifestyle` and before `healthFlags`. All fields optional ("Skip"/"Next" label is automatic from `isOnboardingStepAnswered`): sex at birth (female / male / "use a neutral estimate", default from gender when male/female); goal direction (lose / maintain / gain; default derived: `weightLoss` -> lose, `muscleGain` -> gain, else maintain); target body-fat % (optional) and/or target weight (existing field) with a realistic-pace message from the same calculator ("At a safe pace of about 0.5 kg per week this takes roughly N weeks"; capped message when the target is below the healthy range, section 13.3); typical daily steps bucket (<3k, 3-5k, 5-8k, 8-11k, 11k+ = 2,500 / 4,000 / 6,500 / 9,500 / 12,500 [OWN]) or Health Connect (embedding the existing `HealthSyncCard`, read-only, manual fallback; the removed-from-onboarding rule of `step_answered.dart` is respected by making it an optional card, not a step); allergens (chips); excluded foods (<= 20 free-text chips of <= 40 chars); meals per day 2-6 (default 3); plan ownership (default Coached).
- **`step_health_flags.dart`** gains the `nutritionGuidance` single-choice (none / reported) after the existing guidance question, and the allergen chips live on `step_nutrition` (same `HealthFlags.copyWith` path).
- **`step_lifestyle.dart`** gains the `pescatarian` chip.
- **Model**: `NutritionPrefs` on `UserProfile` (`sexAtBirth`, `goalDirection`, `targetBodyFatPct`, `typicalDailySteps`, `mealsPerDay`, `excludedFoods`, `planOwnership`, `healthConnectChoice`, `completedAt`), `copyWith`, tolerant `fromJson`/`toJson` inside `UserProfile.toJson` (so the export automatically includes it) and `FirestoreProfileRepository._fromMap`/`_toMap` (VERIFY both). `QuestionnaireDraft` gets `updateNutrition(...)`. `step_answered.dart`: `case OnboardingStep.nutrition` = any `NutritionPrefs` field set or `flags.foodAllergens` non-empty; the exhaustive `switch` forces this. Answers stay analytics-light: no analytics SDK is added; step state is just "touched".

### 16.3 Existing users (migration-safe)

Profiles without `nutrition` read as `NutritionPrefs.empty`; unknown enum names degrade to null; nothing is written until the user acts. Users with `completedAt != null` are not routed back to `/onboarding` (`redirectFor`), so they are never forced. The Plan screen and Home card show `needsProfile` / `needsAnswer` states with a button into `/nutrition/profile` - a short three-sheet flow reusing the same widgets and `QuestionnaireDraft` update methods: (1) the two safety questions, (2) body and goal (only the missing fields), (3) food and activity. `missingNutritionInputs(profile)` (pure) decides which sheets and fields appear. Saving goes through the existing profile repository (VERIFY `saveDraft` keeps `completedAt`).

## 17. Food scanning, diary and nutrition data (scope delta)

### 17.1 Behaviour

Add-food entry points (one `AddFoodPage`): **Photo** (AI meal recognition), **Describe** (free text), **Search** (generic foods + the user's saved foods), **Barcode**, **Label**. Every path ends in the same confirm sheet (`FoodDetailSheet`): items with portion editors, macro ranges, confidence, "Check these" chips, slot picker (breakfast / lunch / dinner / snack, defaulted by local time), Save. Nothing is logged without the user pressing Save. The diary page shows the selected day by slot, per-day totals vs plan targets (17.7), and per-meal targets (17.8). A manual quick-log (calories and protein only) is available; quick-log values are stored as one item with `foodRef: "quick"`, a fixed 100 g pseudo-portion and the typed values as per-100g.

### 17.2 Meal photo handling (D-27)

The photo is resized on device (long edge 1024 px, JPEG q85, EXIF stripped by re-encode), sent INLINE to `analyzeMealPhoto` (existing pattern; no server storage, nothing written to Cloud Storage), and discarded server-side after the call. Meal photos are private: an optional encrypted local thumbnail (default on, one switch) is kept on device for the diary and deleted with the entry. No meal photo is ever uploaded for retention. Provider-side handling by Vertex AI is governed by Google Cloud's terms (OPEN Q-6: confirm zero-data-retention / abuse-logging posture for the project and state it on the privacy page).

### 17.3 `analyzeMealPhoto` (meal photo and describe-in-text)

Pattern and provenance (FINDINGS.md, researcher report 2026-10-15; no accuracy was measured by anyone): no open repository ships a TypeScript/Firebase photo-to-foods backend, so the call is our own. Ideas re-authored from `calorie-tracker` (MIT: structured JSON schema with per-item grams and confidence, per-item database lookup with a per-item `source` tag, overall confidence plus assumptions) and `calorie-count` (server-side `coerceMealAnalysis` clamping, "the user's note is authoritative" prompt idea, empty items when no food). `calorie-count`'s licence file is ambiguous, so **no code is copied from it**; `calorie-tracker` calls Gemini from the client with an API key (**not adopted**: no key ever ships in the app; the call goes through our Vertex gateway via ADC).

Callable: `onCall(AI_METERED, ...)` in `functions/src/analyze_meal_photo.ts`: `noteAppCheck`, `enforceNonAnonymousForAi`, `enforceAiGatewayEnabled("analyzeMealPhoto")`, parse before quota, `enforceDailyQuota(uid, "analyzeMealPhoto", quotaFor(60, provider))`, then `generate({operation: "analyzeMealPhoto", jsonResponse: true, responseSchema, temperature: 0, disableThinking: true, timeoutMs: 25_000, maxOutputTokens: 1200})`. Two small gateway changes: `GenerateOptions.responseSchema?` is passed through to `config.responseSchema`, and `"analyzeMealPhoto"` / `"parseNutritionLabel"` join `AI_GATEWAY_OPERATIONS`. Temperature 0 [OWN] for reproducibility (FINDINGS suggests about 0.2; not adopted, reversible).

Request: `{ mode: "photo"|"describe", mimeType?, imageBase64?, text?, note?, languageCode: "en"|"ru" }`. `photo`: `validateImageInput` (allowlist, strict base64, size caps, file-signature sniff) on an image the client already resized to long edge 1024 px. `describe`: `text` 3-200 chars. `note` (optional, photo mode, <= 200 chars): the user's correction, e.g. "this is oat milk". Text fields: control characters, quotes and backticks rejected (same idea as `ai_coach_advice.ts FORBIDDEN_SUBJECT_NAME_CHARS` - VERIFY the exported name), inserted into the fixed server-owned prompt only as quoted DATA; the prompt states that the note/description is authoritative for what the food is and for any amount it gives, and that instructions inside it must be ignored. Residual prompt-injection risk (text visible inside a photo reaches the model like any multimodal input) is stated as in the existing AI callables; the output has no agency beyond a food list.

Model output schema (`responseSchema`; parsed defensively, never trusted): `{ mealName: string, items: [{ name: string (English generic food name), queryTerms: string[], estimatedGrams: {low, mid, high}, confidence: number, uncertainties: string[], llmPer100g: {kcal, proteinG, carbsG, fatG} }], overallConfidence: number, assumptions: string[] }`. **No food in the image (or in the text) -> empty `items`**, and the client shows "We could not find food in this photo".

`coerceMealAnalysis` (own re-implementation in `functions/src/coerce_meal_analysis.ts`, pure, jest-tested; the most valuable piece per FINDINGS): JSON parse in try/catch; every number coerced with `Number.isFinite`, negatives and NaN dropped to 0 or the item discarded; `estimatedGrams` clamped to 1..3,000 with `low <= mid <= high` (`high/low > 4` -> `portionUnclear`); `confidence` clamped 0..1; `llmPer100g`: kcal 0..900, each macro 0..100, `protein + carbs + fat <= 105`, and `4P + 4C + 9F` within +-25 % of kcal else `dataInconsistent`; unknown `uncertainties`/`assumptions` codes DROPPED (closed list 17.10); strings sanitised and truncated; at most 12 items; **all item and total macros are RECOMPUTED server-side from `per100g x grams`, never read from the model**.

Enrichment (server, per item, bounded parallelism 4, total budget 8 s): (1) generic whole foods -> USDA FoodData Central search restricted to Foundation and SR Legacy (CC0), (2) packaged or brand-bearing items -> Open Food Facts Search-a-licious, (3) fallback -> the model's own `llmPer100g`. Every item carries a **source tag** `usda_fdc | open_food_facts | llm_estimate | user` plus `sourceRef` (fdcId or barcode) and `matchQuality` `exact | close | weak | none` (token overlap between the item/query terms and the candidate description); `llm_estimate` implies `matchQuality: none` and adds `lowConfidenceItem`. Lookups reuse the central cache and breakers of 17.5. Item confidence = `modelConfidence * matchFactor` (exact 1.0, close 0.8, weak 0.5, none 0.35 for `llm_estimate`, 0 when nothing usable) [OWN]; entry confidence: `high` if every item >= 0.75 and no unresolved check codes, `medium` if every item >= 0.5, else `low` [OWN].

Response: `{ mealName, items: [{ name, grams: {low, mid, high}, per100g, source, sourceRef?, matchQuality, confidence, checkCodes[] }], totals (recomputed), overallConfidence, assumptions[], model: { id: AI_MODEL, version: "meal-prompt-v1" } }`. Logging: the shared gateway event only; never meal text, notes or images. If the callable is unreachable (offline), the add-food flow offers Search (bundled table) and manual entry; nothing is queued silently.

### 17.4 `lookupBarcode`, the barcode client and the Open Food Facts cache

Client: `mobile_scanner` (BSD-3; FINDINGS used 7.4.2 from cloned pubspecs; `mobile_scanner` is already in `pubspec.yaml` per TECHSTACK - VERIFY the resolved version and that it supports iOS and Android), formats EAN-8, EAN-13, UPC-A, UPC-E, ITF-14; on Android set `dev.steenbakker.mobile_scanner.useUnbundled=true` (FINDINGS: saves 3-10 MB; VERIFY the Play-services model-download behaviour on the operator's phone before keeping it). The GTIN check-digit validator `gtin_validator.dart` is re-implemented from the public GS1 algorithm; **OpenNutriTracker (GPL-3.0) code is not pasted** - its `barcode_check_digit.dart`, `off_data_source.dart` (Search-a-licious + legacy fallback + breaker + retry) and `retry_util` are read as design references only and re-written.

Callable `lookupBarcode` (`INTERACTIVE`-class profile on the `fn-data` identity; quota `barcodeLookup` 120/day): request `{ barcode }` digits only, length 8/12/13/14, GTIN check digit verified server-side too. Flow: (1) `nutrition_cache/off_<barcode>`; (2) on miss, **Open Food Facts v3** `GET https://world.openfoodfacts.org/api/v3/product/<barcode>.json?fields=code,product_name,brands,quantity,product_quantity,serving_size,serving_quantity,nutrition_data_per,nutriments` (FIXED host and template, verified 2026-10-15 by the researcher: v2 is deprecated, v3 returns `{code, errors, product}`; `serving_size` can be ABSENT and must be handled); (3) on miss or unusable data, USDA FDC branded lookup by `gtinUpc` equality (registered key, 17.5); (4) otherwise `found: false` and the client offers `parseNutritionLabel` (photo of the label) or manual entry, with "save this product" into the private `saved_foods` (a per-user cache of the user's own products; never shared). Mandatory `User-Agent: FitnessApp/<version> (<operator contact from config>)` (OFF policy per FINDINGS). **Rate limits (documented by OFF: product reads 15/min/IP, search 10/min/IP, no search-as-you-type) are the reason for the central cache**: Functions egress IPs are shared, so a per-instance in-memory 5-minute circuit breaker (opens after 3 consecutive failures or any 429, answers cache-only with `upstream-unavailable`) and exponential backoff protect both us and OFF; positive cache 30 days, negative 1 day, via the `expireAt` TTL.

Normalisation (pure, `nutrition_normalise.ts`, jest-tested): per-100 g values only from `<nutrient>_100g`; kcal from `energy-kcal_100g` else `energy_100g / 4.184` (kJ); `salt = sodium * 2.5` where salt is needed (we do not track it); serving size optional; sanity: kcal <= 900, each macro <= 100 g, `4P + 4C + 9F` within +-25 % of kcal else `dataInconsistent`; missing energy and macros -> not usable. Reference sample (researcher, verified): barcode 3017620422003 per 100 g kcal 539, kJ 2252, protein 6.3, carbs 57.5, fat 30.9 - usable as a contract test fixture (`off_sample.json` in the scratchpad is the recorded response). Response `{ found, product?: {name, brand, per100g, servingG?}, dataQuality: "complete"|"partial"|"inconsistent", source: "open_food_facts"|"usda_fdc", attribution: { source, licence: "ODbL 1.0 (database), DbCL 1.0 (contents)", url } }`.

### 17.5 `searchFoods` and the nutrition data sources

Callable `searchFoods` (same profile; quota `foodSearch` 150/day): request `{ query: string 3..60 (sanitised), languageCode, scope: "generic"|"packaged"|"both", limit <= 20 }`. The client searches ONLY on an explicit submit with a debounce of at least 600 ms and a 3-character minimum (OFF forbids search-as-you-type) and caches the last results per query. Server flow: `nutrition_cache/q_<sha1(lang|query|scope)>` (TTL 7 days) -> **USDA FoodData Central** `GET https://api.nal.usda.gov/fdc/v1/foods/search` with `dataType=Foundation,SR Legacy`, `pageSize` 10, using a **registered API key held in Secret Manager** (`USDA_FDC_API_KEY`, bound like the Stripe secrets; the runtime SA needs `secretAccessor` on that one secret - operator step; the public `DEMO_KEY` is limited to 30/hour and 50/day per IP and was observed to fail intermittently, so it is never used; the registered key allows about 1,000/hour) -> **Open Food Facts Search-a-licious** `GET https://search.openfoodfacts.org/search?q=<q>&langs=<lang>,en&page_size=20` with the 5-minute breaker and the legacy `cgi/search.pl` endpoint as fallback when Search-a-licious is down (FINDINGS: it can be down for hours). Results are normalised to `{ foodRef, name, brand?, per100g, servingG?, source, completeness }`, de-duplicated, ranked, capped. USDA energy uses nutrient id 1008; some foods lack it, then energy is derived by Atwater 4/4/9 from macros and flagged `derivedEnergy`. Russian coverage in Open Food Facts is patchy (researcher: a 28-hit Russian query, regional collections of very different completeness), so the documented chain is: bundled table -> USDA/OFF search -> `analyzeMealPhoto` in describe mode (flagged `llm_estimate`) -> manual entry plus a private "save this product". The UI says plainly when a result is an estimate.

Bundled generic table (offline search, instant, and the fallback when the callables are unreachable): `mobile/assets/nutrition/generic_foods_v1.json`, built by `scripts/nutrition/build_generic_foods.py` (written in implementation, not CI) from USDA FDC Foundation Foods and SR Legacy (CC0 1.0), nutrient ids 1008, 1003, 1005, 1004, about 2,000-2,500 common foods, rows `{id: "gen:<fdcId>", name, category, per100g, sourceId: "usda_fdc", fdcId, tags}`; Russian display names from an own-authored `generic_foods_ru.json` (names only; English fallback). Diet/allergen tags (`containsAllergens`, `animalProduct`, `pescatarianOk`) are authored by category rules and **uncertain tags default to the restrictive side** (hidden from suggestions, still searchable with a warning). Pure-Dart token search (exact token > prefix > substring + small synonym table).

### 17.6 `parseNutritionLabel` (label OCR, Cyrillic-capable)

Decision D-28: **label text is read by Gemini vision on the server, not by ML Kit.** The researcher verified that ML Kit text recognition supports Latin, Chinese, Devanagari, Japanese and Korean scripts only - NO Cyrillic - and the app is EN + RU, so an on-device ML Kit parser would fail on Russian labels. (ML Kit remains optionally usable as a Latin-only pre-check; not required, therefore not built, and the earlier idea of reusing `visual_equipment/mlkit_text_recogniser.dart` is dropped.) Callable `parseNutritionLabel` (`AI_METERED`, quota 60/day, added to `AI_GATEWAY_OPERATIONS`, image validated by `validateImageInput`, resized to long edge 1280 px by the client; the label photo is not stored): response schema `{ servingSize: {value, unit}, servingsPerContainer, perServing: {kcal, kJ, proteinG, carbsG, fatG}, per100g: {...}, energyUnit, unreadableFields: string[] }`. Deterministic post-step (pure `label_normalise.ts`, jest-tested, EN + RU fixtures): kJ / 4.184 when kcal is absent; decimal comma; if only per-serving exists and the serving weight is known, `per100g = perServing * 100 / servingG`; sanity (kcal <= 900, macros <= 100, `4P + 4C + 9F` within +-25 % of kcal) else `dataInconsistent`; any `unreadableFields` -> `labelAmbiguous`. The client ALWAYS shows an editable confirmation sheet and saves the result as a `saved_food` only after the user confirms; nothing is auto-logged.

### 17.7 Day totals and honesty

Per item `Range{low, mid, high}`. Day total: `mid = sum(mid)`; asymmetric half-widths combined by root-sum-square, `loSpread = sqrt(sum((mid_i - low_i)^2))`, `hiSpread = sqrt(sum((high_i - mid_i)^2))` [OWN: assumes independent errors, so the total is not absurdly wide; stated as "likely range"]. Targets: kcal status `below | within | above` the plan range using `mid`; "remaining" is shown against the top of the range; protein "minimum reached" tick; neutral colours and neutral wording for exceeding the range (no red, no "over budget", no "burn it off"). Per-meal targets (17.8) are a share of the day: `mealsPerDay` split with fixed weights [OWN] (3 meals: 30 % / 35 % / 35 %; with snacks the remainder is spread evenly), shown as ranges.

### 17.8 Food guidance without a meal-planner pillar

`food_suggestions.dart` (pure): for the remaining day macros it lists up to 5 example foods from the bundled table that fit diet pattern, allergens and exclusions (e.g. protein-dense foods when protein is behind) - suggestions only, never prescriptions, no "good/bad" labelling.

### 17.9 Safety, privacy and attribution

No medical claims anywhere: estimates are labelled estimates; the Data-sources page states limits; no condition-specific advice; for `referProfessional` users the diary and its numbers are hidden (section 14). Meal text and images are never logged. Diary data is per-user Firestore data covered by deletion and export (section 20). Attribution file `core/ATTRIBUTIONS_NUTRITION.md` (created in implementation) lists per component: source URL, licence, what is used, repo location, whether code was copied, date. Initial rows (from FINDINGS.md): USDA FoodData Central (CC0), Open Food Facts database (ODbL 1.0 / DbCL 1.0; its images, CC BY-SA, are NOT used; attribute "Open Food Facts"), `mobile_scanner` (BSD-3, dependency), `calorie-tracker` (MIT; ideas and schema shape re-authored, no code pasted), `calorie-count` (licence ambiguous; nothing copied), OpenNutriTracker (GPL-3.0; design reference only, everything re-implemented, nothing pasted), the Mifflin-St Jeor and Deurenberg equations (published formulae), Nutrition5k (CC BY 4.0; evaluation pointer only, not used). The in-app Data-sources page shows the same list. ODbL share-alike applies to public redistribution of a derived database; the cache is private and the app is privately distributed (noted for any future public release).

### 17.10 Check-these (food) closed codes

`portionUnclear`, `hiddenIngredients` (resolution: none / 1 tsp 5 g / 1 tbsp 14 g of oil from the generic table), `liquidUnknown`, `cookingMethod`, `multipleItems`, `brandUnknown`, `foodNotMatched`, `lowConfidenceItem`, `labelAmbiguous`, `dataInconsistent`, `scaleMissing`. Each chip opens a small sheet with a concrete resolution (portion slider, pick another food, choose the oil amount, edit label numbers); resolving updates ranges and marks `resolved: true`.

## 18. Plan ownership (Coached / Shared / Manual)

| | Coached | Shared | Manual |
|---|---|---|---|
| Who sets kcal range, protein, steps | the app computes and applies | the app proposes; the user accepts or edits | the user |
| Safety clamps | enforced | enforced | enforced (bounds also apply to manual edits; manual cannot exceed them) |
| Weekly review | applies bounded change, notifies, 7-day undo | proposes; applied only on accept | insight only, never changes the plan |
| `autoAdjust.steps` toggle | honoured | honoured when the user accepts | forced off |
| `autoAdjust.kcal` | honoured | proposals only | forced off |
| Editing the slider | allowed within bounds; switches ownership to Shared (explained) | allowed | allowed |

Default `coached` (D-10). Changing ownership is always allowed and takes effect for the next review; it never rewrites the current range. A "how your plan adapts" explainer page documents these rules and the clamps in plain language.

## 19. Weekly scan reminder

Extend `scan_reminder.dart` (same notifier, same `kScanReminderId`, same `NotificationService.scheduleAt` one-shot contract; no new mechanism): the fixed 14-day gap becomes a weekly weekday/time rule. Defaults [OBS: weekly, Sunday 08:00 in the reference; OWN as defaults]: weekday 7, minutes 480. Next fire = the next occurrence of weekday/time strictly after `max(now, newestScan + 5 days)` (so a Friday scan does not trigger a Sunday reminder two days later). Persistence: `body_scan_settings/main.reminder` (synced) with the existing per-uid SharedPreferences bool read as a v1 fallback for `enabled`; behaviour "on once a scan exists unless the user explicitly chose" is preserved. User editing UI: Profile row and the entry card (weekday chips + time picker). Re-synced after each scan save/delete, on settings change and on app start (one-shot chaining; there is no OS repeating schedule in `NotificationService`, stated limit: a missed week if the app is never opened and the one-shot fired). Notification tap opens `/body-scan` (VERIFY tap handling in `LocalNotificationService`; if absent, opens the app only). Existing tests for the 14-day rule are updated; strings `photosReminderTitle/Body` are reused or replaced by new keys.

## 20. Privacy flow, account deletion, data export, lifecycle policy

**20.1 Privacy flow (UI).** (1) Existing photo consent before the camera. (2) `CloudConsentSheet` before the first upload and only if the provider needs photos. (3) `PrivacyAndRetention` view (`/body-scan/privacy`): retention choice, "delete all cloud photos", "delete all scans" (existing `confirmAndDeleteAllScans` extended to also call `deleteBodyScan`), cloud analysis on/off, link to data-sources. (4) Result screen "Delete this scan's photos" one tap with a confirm dialog (existing dialog keys reused). (5) `public/privacy.html` updated in the same change: it currently describes on-device photos; the new text must state the blur, the retention default, deletion, the provider, and that meal photos are not stored. No analytics SDK receives photos or body metrics (none is added).

**20.2 Account deletion.** `recursiveDelete(users/{uid})` covers `body_scans`, `body_scan_settings`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`; `sweepAccountData` adds the Storage prefix purge (7.6). Device-local data: the existing wipe deletes the per-uid photo directory, which contains the `scans/` sidecars and the new `meals/` thumbnails; the per-uid SharedPreferences keys (`scan_reminder...`, `body_scan...`) are added to the existing preference wipe list (VERIFY `account_deletion` feature's key list). Account deletion in progress aborts in-flight scan/diary writes through the existing `accountBeingDeletedUidProvider` fence (the capture screen already does this; the job runner and diary writers adopt the same `accountChanged()` pattern).

**20.3 Data export (`exportAccountData`).** Add to the collection list in `account_export.ts` (each bounded by `MAX_ROWS + 1` like the existing reads): `body_scans` (metadata, estimate, provider, photosState), `body_scan_settings`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`; the profile already exports `nutrition` through `UserProfile.toJson`. Photos: bytes are NOT embedded; for any scan with `photosState == stored` the export carries short-lived (24 h) signed read URLs capped at 60 objects (D-15), and states that originals and meal thumbnails live on the user's device. `nutrition_cache` is not user data. Tests extend `account_export.test.ts` and the data-lifecycle parity expectations.

**20.4 Governance files.** Update `core/DATA_INVENTORY_2026-08-11.{md,csv}`, `scripts/ci/data_lifecycle_policy.json` (6.2), `core/CODEMAP.md` (three new features, routes, functions, assets), `core/INDEX.md` (registry rows), `runbooks/body_scan_bucket.md`.

## 21. Routes, entry points, state management

All routes declared in `app_router.dart`; none inside `MainShell` (the five shell routes stay as is); the existing redirect keeps signed-out and not-onboarded users out.

| Route | Page |
|---|---|
| `/body-scan` | `BodyScanFlowPage` (intro -> weight prompt -> capture -> analysis progress -> result), `?scanId=` resumes |
| `/body-scan/result/:scanId` | `ResultView` |
| `/body-scan/history` | history + baseline marker + compare entry points |
| `/body-scan/privacy` | consent/retention settings |
| `/photos/compare` (existing) | accepts `?mode=baseline|previous` |
| `/nutrition` | plan screen (kcal range slider, macros, steps, ownership, review card) |
| `/nutrition/profile` | complete-your-nutrition-profile flow |
| `/nutrition/diary` | diary by day and slot |
| `/nutrition/add` | add-food chooser; `/nutrition/add/photo`, `/nutrition/add/barcode`, `/nutrition/add/label`, `/nutrition/add/search` |
| `/nutrition/sources`, `/nutrition/how-it-adapts` | data sources and limits; explainer |

Entry points: Progress page - two cards at the top (`BodyScanEntryCard` showing next scan due / last result with range; `NutritionEntryCard` showing today's range and protein); Home - one compact card (next scan due or today's kcal remaining; hidden for `referProfessional` users); the existing `ScanEntryCard` stays on the photos page and routes into the new flow. Scan access reuses `scanAccessProvider` unchanged (signed-in, adult, supporter tier, local photo consent).

State (Riverpod, providers in `state/`): `bodyScanHistoryProvider` (Firestore stream of `body_scans` merged with local `ScanRecord`s by `scanId`), `bodyScanJobRunnerProvider`, `bodyScanSettingsProvider`, `weightEntriesProvider`, `scanTrendProvider` (derived pure), `nutritionInputsProvider`, `nutritionEligibilityProvider`, `nutritionPlanProvider` (repository + calculator + clamps), `weeklyReviewProvider`, `foodEntriesForDayProvider(day)`, `dayTotalsProvider(day)`, `genericFoodIndexProvider` (asset), `mealRecognitionControllerProvider`. Repositories are interfaces with Firestore implementations and in-memory fakes for tests (the same pattern as `ProfileRepository`/`MockProfileRepository`).

## 22. Subscription gating

Facts: scan access already requires a non-free tier (`ScanAccess.needsSupporter`, `scan_access.dart`); `subscription/data/feature_gates.dart` is the existing place for tier gates (VERIFY its shape). This design does NOT invent pricing and does not change the existing scan gate. Implementation default (D-26): body-scan capture/result keeps the existing `scanAccessProvider`; nutrition plan, diary and AI food recognition are NOT tier-gated (they are bounded by per-user daily quotas, anonymous refusal and the server kill switch). All gates are expressed as entries in `feature_gates.dart` so the operator's decision is a one-line change per feature. **OPEN Q-2** (operator): which of {body-scan estimate, nutrition plan, diary, AI meal photo, barcode/label, weekly review} are Supporter-only, and whether free users get a limited number of AI meal scans per day (the server quota can be tier-scaled the way `quotaFor` already scales anonymous callers).

## 23. l10n key plan (EN + RU)

All user-visible strings go through the existing ARB setup (VERIFY `l10n.yaml` and the ARB directory under `mobile/lib/l10n`); EN and RU are added in the same change and `scripts/ci/check_ru_en_drift.js` parity must hold (not run here). Key families (camelCase, prefix per feature, matching existing `scan*`, `onb*`, `photos*`): `bodyScan*` (intro, weight prompt, stages, result, history, compare actions, retention, consent, errors), `scanCheck*` (existing; new rows for pose hints), `checkCode*` (one per `CheckCode`), `nutrition*` (plan, bounds, ownership, auto-adjust, explainer, sources, professional notice), `reviewReason*` (one per review reason code), `onbNutrition*` (new step), `diary*`, `food*`, `foodCheck*` (one per food check code), `activity*` reserved for Phase 2. Rules: ICU placeholders and plurals (RU has three plural forms: weeks, kilograms, points); numbers and dates through `intl`; units metric in this sprint (kg, cm, km); imperial display is a follow-up (OPEN Q-8); notification strings are resolved by the caller and passed to `NotificationService`; no provider-authored free text is displayed (closed codes only); medical-safe wording reviewed once in the same pass (no diagnosis words, no "should"/"must" about health). Estimate: about 260-300 new keys.

## 24. Accessibility

- Every status uses icon + text + (optionally) colour; the readiness chips already announce `label: text` through `Semantics` - the skeleton overlay is decorative (`ExcludeSemantics`) because the panel and hint line carry the information.
- The countdown keeps its live region; the voice coach path and mute switch are reused; haptics remain optional. A manual shutter is always reachable (also the switch-access path).
- Analysis stages and elapsed time are a polite live region; the Cancel button is focusable first.
- Charts have a data-table alternative and a one-sentence summary ("Smoothed trend 24.1 percent, down 0.8 points over 4 weeks; within measurement noise"); dots vs line are distinguished by shape and a legend, not colour alone.
- Range sliders: two thumbs with semantic labels ("lowest daily calories", "highest daily calories"), step 10, value announcements, keyboard/TalkBack increment actions, bounds announced; touch targets >= 48 dp.
- Contrast: colours come from `app_semantic_colors.dart` tokens (measured WCAG ratios); overlay text over the camera preview sits on the existing dark translucent panel. Large text (200 %): result and plan screens scroll, no clipped fixed-height cards.
- Neutral wording for exceeding calorie ranges (no red, no shaming); the professional notice is calm and non-diagnostic; chips ("Check these") are buttons with clear action labels.
- RU strings checked for expansion (about +30 %) in chips and the status panel.

## 25. iOS parity, extension points, follow-ups

### 25.1 iOS notes (nothing blocks iOS; nothing is verified on iOS)

Packages used are cross-platform: `google_mlkit_pose_detection`, `camera`, `mobile_scanner`, `image`, `dio`, `cloud_functions`, `shared_preferences`, `flutter_local_notifications`. Health goes only through `HealthService` (HealthKit implementation per `core/health/health_service.dart` doc comment). Signed-URL PUT, callables and rules are platform-neutral. Gaps/NOT_RUN: no iOS device or CI run; App Check on iOS needs DeviceCheck/App Attest configuration in the console; `Info.plist` camera/photo/Health usage strings; the Android-only `useUnbundled` scanner flag has no iOS equivalent; ML Kit pose and scanner accuracy on iOS are unmeasured; no background execution is assumed anywhere (job runner resumes in the foreground). Cupertino fallbacks (pickers, switches) are switched in selectively later per `CONVENTIONS.md`.

### 25.2 Extension points (documented, not built)

`BodyCompositionEstimator` provider slot (section 8); `GoalPreviewProvider` interface name reserved for "Future You" - NOT created: generated body imagery is out of scope and carries the consent/legal flag on item 67 of `FITNESS_APP_TASK_LIST.md`; optional tape-measure inputs feeding the existing `navyBodyFatPercent` as a second signal; imperial units; optional exercise-calorie credit (off, D-29); meal templates/recipes; Withings-style scale import into `weight_entries.source` (section 31); the nutrition-aware programme hook (section 30).

### 25.3 Follow-ups (shrunk by the scope delta)

Meal planner/recipes, restaurant menus, supplement tracking, imperial units, wearable-scale weight import, per-meal photo comparison, a measured portion-estimation evaluation set (Nutrition5k CC BY 4.0 is the evaluation pointer), Russian food-name coverage beyond the first ~400 foods.

## 26. Risks and open questions

### 26.1 Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | The estimate is provisional and may be misread as a photo measurement | permanent banner, confidence `low`, range half-width 5.0, noise threshold, no trend claims; D-3 |
| R2 | Face blur depends on pose landmarks; a miss leaks a face | fail closed, margin, tests on fixtures, default retention 0, consent copy states other marks are not blurred |
| R3 | Rules carve-out missed -> client-forgeable server data, or `flagsAreStripped` missed -> all profile saves refused | rules tests 6.4 cases 2, 8, 9; deploy rules before client |
| R4 | Safety logic wrong for edge profiles (tiny/very large, non-binary) | named clamps, table tests incl. boundaries, floor >= BMR, conservative unspecified sex |
| R5 | Review changes the plan wrongly on noisy weight | needs >= 3 points over >= 7 days, two-review confirmation, 14-day cooldown, +-150 step, +-400 drift cap |
| R6 | Portion estimates are guesses | ranges, editable grams, `llm_estimate` tag, Check-these, no accuracy claim |
| R7 | Open Food Facts rate limits/outages; patchy Russian coverage | central cache, breaker, legacy fallback, chain to describe/manual, private saved foods |
| R8 | Cost of AI calls and paid-lookup abuse | per-uid quotas, anonymous refusal, kill switch, `AI_METERED` ceilings |
| R9 | Privacy-policy drift (text says on-device) | `public/privacy.html` updated in the same change; consent text reviewed |
| R10 | Existing scan tests/behaviour break (14-day reminder, capture pop result) | additive params, updated tests named in section 28 |
| R11 | Thresholds (readiness, luminance) are uncalibrated opening values | recorded as NOT_RUN device calibration |
| R12 | Document is large; sprint size | sprint plan (separate doc) orders epics; the programme-level and activity-model pieces are minimal this sprint |

### 26.2 Open questions for the operator

Q-1 which real body-composition provider (or "stay provisional"); Q-2 tier gating per feature (section 22); Q-3 confirm the default photo retention "delete after analysis" (D-17); Q-4 contact string for the Open Food Facts `User-Agent` and registration of a free USDA FoodData Central API key stored as a secret; Q-5 provisioning of the private bucket and IAM (6.3) and the secret accessor grant; Q-6 Vertex AI data-retention posture to state on the privacy page; Q-7 minimum age 18 for nutrition (D-9) - confirm; Q-8 imperial units in this sprint or later; Q-9 source of Russian food names (own translation vs none); Q-10 `public/privacy.html` wording owner; Q-11 product-ux-reviewer to confirm section 3 against the reference frames (not re-inspected while authoring).

## 27. Decisions (copy into `core/DECISION_LOG.md`)

| ID | Decision | Why (short) |
|---|---|---|
| D-1 | Extend the existing local scan stack in `progress_photos/scan/`; add features `body_scan`, `nutrition_plan`, `food_diary` | capture, alignment, shutter, compare, encryption already exist and are tested |
| D-2 | Clean-room: behaviour only; every adopted number is tagged observed / published / own choice (section 29); attribution file for copied/bundled open-source | scope rule, reviewability |
| D-3 | Ship a clearly named PROVISIONAL estimator (`provisional-anthropometric` / `deurenberg-1991-v0`, half-width 5.0 placeholder, confidence low, no photo upload); real provider is a swap | no validated model exists; no accuracy invented |
| D-4 | Face blur happens ON DEVICE before upload from pose landmarks, fail closed | server never holds an unblurred face |
| D-5 | A separate cloud-upload consent, shown only when the provider needs photos; none with the provisional provider | upload without benefit is a privacy cost |
| D-6 | Legacy local-only scans are never auto-uploaded | consent was not given for them |
| D-7 | `body_scans` is server-authored; the client may edit only `weightKg`/`clientNote`; deletion via callable | integrity of provider/estimate fields |
| D-8 | Weekly review is client-side pure logic | exclusion flags are device-only; offline; testable |
| D-9 | Exclusions: under 18/unknown age, pregnancy-breastfeeding flag, new nutrition-guidance flag, clinician advice against exercise, surgery under restrictions -> neutral professional notice, no numbers anywhere (plan, ring, diary, home card) | conservative; unanswered locks the coach |
| D-10 | Default ownership Coached; clamps bind every ownership mode | safety does not depend on mode |
| D-11 | `HealthFlags` gains `nutritionGuidance` and `foodAllergens`, device-only; rules `flagsAreStripped` updated first | F014 privacy doctrine; fail-closed lesson |
| D-12 | `NutritionPrefs.sexAtBirth`; BMR constant -78 and male floor for unspecified | Mifflin needs a sex term; stay conservative |
| D-13 | Energy maths: Mifflin-St Jeor x {1.2, 1.375, 1.55, 1.725}, lower of questionnaire/steps factor, +-150 kcal range, floors, deficit and surplus caps (section 13) | published formulas, conservative own caps |
| D-14 | Body-scan callables run as `fn-data` with bucket-scoped IAM (operator step) | no new identity this sprint |
| D-15 | Export carries scan metadata plus capped 24 h signed photo links | portability without embedding bytes |
| D-16 | Private bucket with signed V4 PUT URLs (content type + length range), deny-all `storage.rules` for the default bucket | no client Storage SDK path |
| D-17 | Retention default "delete after analysis" (0), options 30/90/365 days, daily purge, 400-day bucket backstop | user control, minimal retention |
| D-18 | Smoothing: irregular-interval EWMA (tau 21 d body fat, 7 d weight), winsorise +-4 pts, Theil-Sen weight slope, no Holt | robust with few noisy points |
| D-19 | Noise threshold `max(1.0, sqrt(hw1^2 + hw2^2))`; with the provisional provider every change reads "no meaningful change" | honest uncertainty |
| D-20 | Manual shutter stays; overriding records `manualOverride` and lowers confidence | detector failures are real |
| D-21 | Reminder extended in place to weekly weekday/time (default Sunday 08:00) on the existing notification mechanism | no new mechanism |
| D-22 | Weight history = day-keyed `weight_entries`; plan reads the latest, never rewrites the profile | avoids profile write contention |
| D-23 | Macro rules: protein min 1.4/1.6, target 1.6/2.0/1.8, max 2.2 g/kg of reference weight; fat 20-35 % and >= 0.6 g/kg; carbs >= 100 g | published ranges, own bounds |
| D-24 | Steps goal 6,000-12,000 computed; auto-adjust +1,000 per review, never reduces | conservative |
| D-25 | Every new `users/{uid}` collection is carved out of the wildcard and has a shape-validating block | wildcard otherwise overrides |
| D-26 | No pricing invented; existing scan gate unchanged; other food/plan features ungated pending Q-2 | operator decision |
| D-27 | Meal and label photos are never stored server-side; optional encrypted local thumbnail | privacy |
| D-28 | Cyrillic label OCR through Gemini vision on the server; ML Kit text recognition is not used (no Cyrillic) | verified limitation |
| D-29 | No exercise-calorie credit added to the budget | avoids overeating; review corrects error |
| D-30 | Food macros come from databases (USDA/OFF) with a per-item source tag; the model supplies names and gram ranges; the server recomputes all totals (`coerceMealAnalysis`) | traceable numbers |
| D-31 | Open Food Facts only via a cached server function (v3 API, User-Agent, breaker); USDA via a registered key in Secret Manager; bundled CC0 table; GPL-3 code re-implemented not pasted; attribution file | rate limits, licences |
| D-32 | "Check these" uses closed codes; provider free text is never displayed | l10n and injection surface |
| D-33 | Nutrition-aware programme level: data contract + pure function + neutral-default hook this sprint (section 30) | foundation |
| D-34 | Sport-agnostic activity model, `DeviceSource` interfaces and pure merge/dedup this sprint, no sport UI (section 31) | foundation |
| D-35 | Reverse engineering of proprietary apps is refused; competitive study uses only public docs, store listings, official APIs/SDK docs, published research and ordinary observation | legality, clean-room |
| D-36 | Priority Phase 2 backlog lives in `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` | one place |

## 28. Requirement-to-test seeds

Focused tests only, authored and run by the functional/e2e agents after coding (nothing was run here). Seeds for the coverage map:

| Area | Test seeds |
|---|---|
| `energy_math`, `plan_calculator`, `safety_clamps` | BMR vectors (M/F/unspecified), factor mapping, steps cross-check picks the lower, deficit/surplus caps, floor = max(abs, BMR), BMI guards (17.9, 18.5, 19.9, 25, 30), range width, bounds never empty, boundary ages (17/18 via `lowestAgeAt`), tiny and very large weights, rounding |
| macros | protein min/target/max per goal, `Wref` cap above BMI 30, 220 g cap, fat bounds, carb 100 g floor and `lowCarbBySafety` |
| `nutrition_eligibility` | each row of the section 14 table and its order, unanswered questions lock, no numbers for `referProfessional` |
| `weekly_review` | needMoreData, deadband, two-review rule, cooldown, `tooFast` immediate, steps first, atSafetyLimit, drift cap, ownership matrix, recomposition |
| `scan_trend` | EWMA vectors with irregular spacing, winsorising, Theil-Sen with outliers and minimum span, noise threshold with provisional half-width, 4-week trend label |
| `plausibility`, `check_items` | each code triggers/does not trigger at the boundary |
| `body_scan_flow_machine`, `body_scan_job` | every transition in the table, cancel from each state, retry/backoff and attempt cap, resume from persisted v2 record, v1 record never uploaded, idempotent re-run |
| `face_region` + blur | box geometry with/without head landmarks, back-view crown estimate, fail-closed cases, pixel test (inside changed, outside unchanged), EXIF absent |
| capture | luminance gating, manual override recorded, overlay painter smoke (widget) |
| onboarding | `kOnboardingOrder` contains `nutrition`, `isOnboardingStepAnswered` case, resume index with new step, completed profile not redirected, defaults from goals, `missingNutritionInputs`, existing profile JSON round-trips without `nutrition`, flags JSON with and without new keys |
| rules (emulator) | section 6.4 cases 1-11 |
| functions (jest) | section 7.7 plus `coerce_meal_analysis`, `nutrition_normalise`, `label_normalise` (EN + RU fixtures), GTIN validator, OFF v3 fixture (barcode 3017620422003), breaker, cache TTL, quota names, `sweepAccountData` storage call, export additions |
| food | `portion_math`, `day_totals` RSS ranges, per-meal targets, `gtin_validator`, source tags, check-these resolution, `food_suggestions` diet/allergen filtering with restrictive defaults |
| programme hook / activity model | sections 30.5 and 31.8 |
| l10n | EN/RU key parity for all new keys, plural forms |

## 29. Numeric parameter provenance

Legend: **OBS** = observed in the operator's reference recordings as described in the brief (frames were not re-inspected while authoring; product-ux-reviewer to confirm, Q-11), **PUB** = published formula or guideline, **OWN** = our own choice, **TECH** = existing repo value.

| Parameter | Value | Tag | Source / note |
|---|---|---|---|
| Poses per scan | 3 (front, side, back) | OBS | brief; TECH `ScanPose` |
| Scan duration promise | about 60 s | OBS | copy is ours |
| Countdown | 3-2-1 | OBS + TECH | `AutoShutterConfig` |
| Readiness hold before countdown | 1000 ms | TECH | `AutoShutterConfig.holdMs` |
| Live checks | distance, lighting, position (+ pose) | OBS + TECH | |
| Luminance window | 0.25-0.92 | TECH | `ReadinessConfig` (uncalibrated) |
| Disclosure "single readings vary about 1-2 points" | 1-2 pts | OBS | copy is ours; NOT used as a model accuracy |
| Example result range (30.8 % likely 29.2-32.6) | - | OBS | example only, not a default |
| Example plan values (1,760 kcal, 145 g protein) | - | OBS | NOT used as defaults |
| Reminder default | Sunday 08:00, weekly | OBS | |
| Reminder minimum gap after a scan | 5 days | OWN | |
| Provisional half-width | 5.0 pts | OWN | placeholder, NOT an accuracy |
| Provisional formula | Deurenberg 1991 | PUB | Br J Nutr 65:105-114 |
| Noise floor / threshold | 1.0 pt; `sqrt(hw1^2+hw2^2)` | OWN | |
| 4-week trend factor | 0.8 x mean half-width | OWN | |
| Smoothing tau | 21 d (body fat), 7 d (weight) | OWN | |
| Winsorise | +-4.0 pts | OWN | |
| Weight slope window | 21 d, >= 3 points, >= 7 d span | OWN | Theil-Sen is PUB (1950/1968) |
| Plausibility: far from profile | 12 pts | OWN | |
| Plausibility: weight jump | 3 kg in 7 d | OWN | |
| Plausibility: wide range | hw > 4 | OWN | |
| BMR | Mifflin-St Jeor | PUB | AJCN 51:241 |
| Unspecified-sex constant | -78 | OWN | midpoint of +5/-161 |
| Activity factors | 1.2 / 1.375 / 1.55 / 1.725 | PUB convention + OWN mapping | 1.9 unused |
| Steps bands | 5,000 / 7,500 / 10,000 | OWN | |
| kcal per kg | 7,700 | PUB | Wishnofsky |
| Weekly rates | 0.5-1.0 %/wk loss, 0.25-0.5 %/wk gain | OWN within PUB | NHS/CDC guidance; Helms 2014 |
| Deficit cap | 25 % TDEE | OWN | |
| Surplus cap | min(500, 15 % TDEE) | OWN | |
| kcal floors | 1,200 F / 1,500 M, >= BMR | OWN (consumer minimums) | |
| Range half-width | 150 kcal; width 100-400 | OWN | |
| Protein | 1.4/1.6 min, 1.6/2.0/1.8 target, 2.2 max g/kg | PUB ranges + OWN picks | Jager 2017; Morton 2018 |
| Fat | 20-35 % kcal, >= 0.6 g/kg | PUB (AMDR) + OWN | IOM 2005 |
| Carb floor | 100 g | OWN | |
| Steps goal | 6,000-12,000; +1,000 per review | OWN | |
| Review step / cooldown / drift | 150 kcal / 14 d / 400 kcal | OWN | |
| Review deadband | max(0.15 kg/wk, 25 % of intended) | OWN | |
| Energy sanity | 4/4/9 within +-25 % | PUB (Atwater) + FINDINGS | |
| Meal macro bounds | kcal <= 900, macro <= 100 g per 100 g | PUB physical limits | |
| Portion clamp | 1-3,000 g; high/low > 4 flagged | OWN | |
| Item confidence factors | 1.0 / 0.8 / 0.5 / 0.35 | OWN | |
| Meal split | 30/35/35 % | OWN | |
| Quotas | scan create 30, estimate 14, delete 60, meal 60, label 60, barcode 120, search 150 per day | OWN | |
| Upload limits | 1 KiB-3 MiB, 1280 px, JPEG q85, URL 10 min | OWN | |
| Retention | 0 (default) / 30 / 90 / 365 d; backstop 400 d | OWN | |
| OFF limits | 15/min reads, 10/min search | FINDINGS (documented by OFF) | |
| USDA limits | DEMO_KEY 30/h and 50/d; registered about 1,000/h | FINDINGS | |
| Cache TTLs | 30 d product, 1 d negative, 7 d search | OWN | |

## 30. Nutrition-aware programme level

### 30.1 Goal and boundary

Training programmes consume the user's nutrition state to adjust weekly volume, an intensity cap and deload suggestions, conservatively. This never replaces or bypasses existing safety: the result is combined with `AgeBand.intensityCap`, the screening ceiling and the injury filter (`equipment/data/exercise_filter.dart`) by taking the MORE conservative value; nutrition can lower load, never raise a cap that safety set.

### 30.2 Data contract (pure Dart, `nutrition_plan/data/nutrition_training_state.dart`)

```
class NutritionTrainingInput {
  NutritionEligibility eligibility;     // not eligible => neutral output
  EnergyPhase phase;                    // deficit | maintenance | surplus
  double? deficitPct;                   // (TDEE - kcalMid) / TDEE, >= 0 in deficit; null if unknown
  double? surplusPct;
  double? proteinAdherence;             // fraction of LOGGED days meeting the protein minimum; null if < 4 logged days in 14
  int loggedDays14;                     // diary coverage
  double? avgSleepHours;                // lifestyle.sleepHoursPerNight or Health Connect sleep when connected
  double? weightRatePctPerWeek;         // from the Theil-Sen slope
  int sessionsPerWeek;                  // from the schedule / recent logs
  bool recoveryDeloadSignal;            // existing recovery/data/deload_detector.dart output
  double kcalMid; double floorKcal;
}
class TrainingNutritionAdvice {
  double volumeFactor;                  // 0.70 .. 1.05 multiplier on weekly working sets
  double intensityCapDelta;             // 0 or negative (e.g. -0.05); added to the existing intensity factor cap
  DeloadSuggestion deload;              // none | consider | recommended, with reasonCodes
  List<TrainingNutritionReason> reasons;// closed codes, l10n
  bool neutral;                         // true when nothing is applied
}
TrainingNutritionAdvice adviseTrainingFromNutrition(NutritionTrainingInput i);
```

### 30.3 Decision function (all numbers OWN, conservative; tags per section 29 rule)

1. `eligibility != eligible`, or `kcalMid`/`phase` unknown -> neutral (`volumeFactor = 1.0`, no delta, no suggestion). Never act on missing data.
2. Deficit depth: `deficitPct >= 0.20` -> volume 0.85; `0.10 <= deficitPct < 0.20` -> 0.95; below 0.10 -> 1.0. Intensity is NOT reduced for a deficit alone (published guidance for resistance training in a deficit is to keep load and trim volume, e.g. Helms et al. 2014).
3. Surplus phase: `volumeFactor = 1.05` only if `avgSleepHours >= 7` and `proteinAdherence >= 0.7`; otherwise 1.0.
4. Protein: `proteinAdherence != null && < 0.5` while in deficit -> reason `proteinLow`, `deload = consider`, plus a protein nudge on the plan screen (no volume change by itself).
5. Sleep: `avgSleepHours != null && < 6.0` -> `intensityCapDelta = -0.05`, reason `sleepLow`.
6. Fast loss: `weightRatePctPerWeek` below `-1.25 x` the plan's max rate -> volume `min(current, 0.90)`, `deload = consider`, reason `lossTooFast`.
7. Low intake with high load: `kcalMid <= floorKcal * 1.05` and `sessionsPerWeek >= 5` -> `deload = recommended`, reason `lowIntakeHighLoad`, plus the generic "talk to a professional if you feel unwell or train hard on low intake" line (this is a screening proxy for low energy availability; true energy availability needs fat-free mass and exercise energy expenditure which the app does not hold, so it is deliberately NOT computed and no RED-S claim is made).
8. `recoveryDeloadSignal` true -> `deload = recommended` regardless of nutrition (existing behaviour preserved).
9. Floors: `volumeFactor` is clamped to `[0.70, 1.05]`; `intensityCapDelta` to `[-0.10, 0]`; factors multiply, they do not stack past the clamp.

### 30.4 Where it plugs in

`nutritionTrainingAdviceProvider` (Riverpod) exposes the advice; the programme builder receives it as an OPTIONAL parameter (`volumeFactor`, `intensityCapDelta`) whose default is neutral, so nothing changes for users without a nutrition plan. VERIFY the builder file under `features/programmes/` (and `suggestion_builder.dart`) before wiring; if the seam is not a small parameter, the hook is delivered as the provider only and the wiring moves to Phase 2.

### 30.5 This sprint vs Phase 2

THIS SPRINT: the data contract, `adviseTrainingFromNutrition`, `TrainingNutritionReason` codes, the provider, the optional neutral-default parameter on the programme builder if it is a small change, and focused tests (neutral on missing data, each rule at its boundary, clamps, combination with age/screening caps takes the minimum, injury filter untouched). PHASE 2 (backlog doc): periodised cut/bulk blocks, automatic deload scheduling, per-exercise adaptation, training-day carbohydrate guidance, Health Connect energy expenditure, in-app explanation UI, evaluation with real users.

## 31. Sport-agnostic activity model and device sources

Foundation only. THIS SPRINT: pure-Dart model, interfaces, merge/dedup and tests, in a new logic-only feature `mobile/lib/features/activity/` (`data/` only; no page, no sport UI, no persistence, no adapters). Everything else is Phase 2.

### 31.1 Model (`activity/data/`, no Flutter imports)

- `SportType`: `running, trailRunning, walking, hiking, cycling, indoorCycling, mountainBiking, swimmingPool, swimmingOpenWater, rowing, strength, other` (extendable; unknown names degrade to `other`).
- `ActivitySession`: `id` (stable `act_<sha1 of canonical source key>`), `sport`, `startUtc`, `endUtc`, `utcOffsetMinutes` (local offset at start), `movingTimeS?`, `summary: ActivitySummary`, `streams: Map<StreamKind, SampleStream>`, `laps: List<Lap>`, `provenance: List<SourceRecord>`, `userEdits` (fields the user overrode), `privacy: ActivityPrivacy`, `schema`.
- `ActivitySummary`: `distanceM, ascentM, descentM, avgHrBpm, maxHrBpm, avgSpeedMps, avgCadence, avgPowerW, normalizedPowerW?, activeEnergyKcal, steps, strokeCount, poolLengthM, lapCount, avgSwolf` (all nullable; pace is DERIVED, never stored).
- `StreamKind`: `heartRate, speed, cadence, power, altitude, gps, strokeRate, temperature`. `SampleStream`: `kind`, `unit` (canonical per kind: bpm, m/s, rpm-or-spm by sport, W, m, WGS84 degrees, strokes/min, degC), `offsetsMs` (milliseconds from `startUtc`, strictly increasing) and `values` (GPS as parallel lat/lon/accuracy lists), `sourceId`. Streams are never interleaved across sources within one kind.
- `Lap`: `index`, `kind` (auto, manual, poolLength, interval), `startOffsetS`, `durationS`, `distanceM?`, `avgHrBpm?`, `strokeCount?`, `strokeType?` (free, back, breast, fly, mixed).
- `SourceRecord`: `sourceId`, `sourceKind`, `deviceModel?`, `appPackage?`, `externalId?`, `importedAt`, `fieldsContributed`, `rawRef?` (the original per-source session is retained so a merge can be undone).
- Units and localisation: canonical SI storage; km vs miles, min/km vs min/mi, per-100 m vs per-100 yd swim pace, feet for elevation are PRESENTATION concerns resolved by locale and a user setting (`intl`), never converted in the data layer.

### 31.2 `DeviceSource` abstraction

```
abstract class DeviceSource {
  String get id;                        // "health_platform", "ble_hr", "garmin_cloud", ...
  SourceKind get kind;                  // platformHealth | bleSensor | vendorCloud | companionApp | fileImport
  SourceCapabilities get capabilities;  // static matrix, see 31.6
  Future<SourcePermission> permission(Set<StreamKind> kinds);
  Future<SourcePermission> request(Set<StreamKind> kinds);
  Future<List<ActivitySession>> fetchSessions({required DateTime from, required DateTime to});   // history
  Stream<LiveSample> live(Set<StreamKind> kinds);                                                 // BLE / watch only
  Future<void> disconnect({bool deleteImported});
}
```
Adapters (all Phase 2): `HealthServiceSource` over the existing seam (the current `HealthService` returns per-day `HealthSnapshot`s only; adding session/route/series reads is an interface extension implemented in `MockHealthService` and `PlatformHealthService`), `BleGattSource` (standard profiles), `WearCompanionSource`, vendor adapters, file import (FIT/GPX/TCX). Vendor-cloud adapters run in Cloud Functions (OAuth tokens never on the device) and deliver normalised `ActivitySession`s.

### 31.3 Merge and dedup rules (pure, `activity_merger.dart`)

`MergeResult merge(List<ActivitySession> candidates, MergePolicy policy)` is deterministic and order-independent (inputs sorted by `(priority, startUtc, id)`; a property test shuffles input).

1. **Exact duplicate**: same `sourceId` + `externalId` -> keep one (idempotent re-import).
2. **Same workout from different sources** if all hold [OWN thresholds]: sports compatible (equal, or same family: running/trailRunning, cycling/indoorCycling/mountainBiking, swimming pool/open water NOT merged with each other); time IoU of `[start, end]` >= 0.8 OR (`|start1-start2| <= 120 s` and `|end1-end2| <= 300 s`); if both have distance, relative difference <= 15 %; if both have GPS, mean distance between time-aligned points <= 100 m.
3. **Echo detection**: a platform-health record whose `appPackage`/recording metadata names a source we already hold (e.g. a watch app writing to Health Connect) is treated as the same workout under rule 2 and ranked below the direct source.
4. **Not merged**: overlap below the thresholds (brick sessions, intervals); back-to-back records from ONE source with a gap <= 60 s are only joined when `policy.joinSplits` is on (default off).
5. **Field policy**: per `StreamKind`, the stream comes from the highest-priority source whose coverage is >= 80 % of the session (default priority: dedicated sensor / power meter / chest strap > watch or vendor cloud > phone app > platform aggregate; user-configurable). Complementary merging is allowed across kinds (HR from a strap, GPS from the phone) after estimating clock skew by cross-correlation within +-5 s; samples are never mixed within one kind. Summary fields are recomputed from the merged streams where streams exist, otherwise taken from the highest-priority source; a disagreement above 10 % is recorded in `mergeNotes`. `userEdits` always win. `provenance` lists every contributing source and keeps the originals.
6. **Time handling**: all comparisons in UTC; offset stored for display; DST irrelevant to comparison.

### 31.4 Permissions and privacy

Per-source, per-data-kind consent; GPS is location data (sensitive): default redaction trims the first and last 200 m of a route in any shared or exported view [OWN] and there is no map sharing; HR/sleep are health data and follow the device-only doctrine unless the user opts into sync (OPEN question for Phase 2); BLE needs Bluetooth/nearby-devices permission requested at connection time with a reason; vendor OAuth requires explicit connect and a working disconnect that revokes the token and, on request, deletes imported data; no analytics SDK receives any of it; vendor API terms (retention, display, sharing) are checked per vendor before building the adapter.

### 31.5 Storage and retention (design only)

`users/{uid}/activities/{activityId}` (summary, laps, provenance, privacy, schema; under 1 MB) and the streams as compressed JSON in the private bucket under `users/{uid}/activity_streams/{activityId}.json.gz` (Firestore document size limit); user-controlled retention (default: keep summaries, streams for 2 years - OPEN for Phase 2); included in `deleteAccount`, in `exportAccountData` (FIT/GPX export of the merged session is a Phase 2 story) and in the lifecycle policy files when the collection is introduced. None of this is created this sprint.

### 31.6 Capability matrix (hypotheses to be confirmed against official documentation in the Phase 2 competitive/API study; Y = specified by the standard or platform documentation as understood, P = partial, N = no, ? = not verified here)

| Source | Session list | HR | Speed/pace | Cadence | Power | GPS route | Strokes/laps | Steps | Sleep | Live stream | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Health Connect (Android) | Y | Y | Y | Y | Y | Y | P | Y | Y | N | read-only; data richness depends on the writing app |
| HealthKit (iOS) | Y | Y | Y | Y | Y | Y | P | Y | Y | P | per-type permissions |
| BLE Heart Rate (GATT 0x180D) | N | Y (+RR) | N | N | N | N | N | N | N | Y | chest straps, many watches in broadcast mode |
| BLE Running Speed & Cadence (0x1814) | N | N | Y | Y | N | N | N | N | N | Y | foot pods |
| BLE Cycling Speed & Cadence (0x1816) | N | N | Y | Y | N | N | N | N | N | Y | wheel/crank revolutions |
| BLE Cycling Power (0x1818) | N | N | P | P | Y | N | N | N | N | Y | power meters |
| BLE FTMS (0x1826) | N | P | Y | Y | Y | N | N | N | N | Y | indoor bikes, treadmills, rowers |
| Wear OS companion | Y | Y | Y | Y | ? | Y | ? | Y | ? | Y | existing `wear/` module is a phone-sync scaffold |
| Garmin, Polar, Suunto, Fitbit, Wahoo, Strava, Withings (cloud APIs) | ? | ? | ? | ? | ? | ? | ? | ? | ? | N | partner approval, terms, rate limits and data scopes to be verified; Withings is the candidate for body-weight/body-composition scale data feeding `weight_entries` |

### 31.7 This sprint vs Phase 2

THIS SPRINT: the model classes with tolerant JSON, the `DeviceSource` and capability interfaces, `ActivityMerger` and `MergePolicy`, a `FakeDeviceSource` for tests, and the focused tests of 31.8. PHASE 2 (priority backlog): everything else, in `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md`.

### 31.8 Test seeds

Exact duplicate; same workout from watch + phone + platform echo -> one session with provenance of three; brick session not merged; swim pool vs open water not merged; HR from strap + GPS from phone complementary merge with 3 s skew; order independence (shuffled inputs); user edit wins; summary disagreement > 10 % noted; unknown sport degrades to `other`; stream offsets not increasing rejected; JSON round trip with unknown fields; unit canonicalisation (no conversion in the data layer).

