# Findings register

Severity meaning:

- **BLOCKER** — Recommendation Engine v1 must not ship with this unresolved.
- **HIGH** — material correctness/safety issue; migration gate required.
- **MEDIUM** — architecture/data-quality issue.
- **KEEP** — existing behavior that should be preserved.

## RE-B01 — BLOCKER — Personalisation sign inversion

**Evidence:** `mobile/lib/features/personalisation/data/fitness_model.dart`, `mobile/lib/features/personalisation/data/for_you_ranker.dart`

**Finding:** tooHard lowers score, while the ranker gives lower score higher priority. This contradicts fitness_model.dart's stated recovery/downweight semantics.

**Required action:** Do not migrate this formula into Recommendation Engine. Split tolerance/recovery signal from training priority and add regression tests.

## RE-B02 — BLOCKER — LLM owns unvalidated starting-load guidance

**Evidence:** `mobile/lib/features/ai_coach/ai_coach_context.dart`, `mobile/lib/features/ai_coach/ai_coach_service.dart`

**Finding:** Cloud AI is explicitly asked for beginner volume and an exercise starting-load cue, with no deterministic prescription validator.

**Required action:** Remove numeric prescription authority from AI Coach before Recommendation Engine release.

## RE-B03 — BLOCKER — Clinical safety inputs are collected but not generally enforced

**Evidence:** `mobile/lib/features/profile/data/profile_models.dart`, `mobile/lib/features/equipment/data/exercise_filter.dart`

**Finding:** HealthHistory contains conditions, medications, limitations, surgeries, blood pressure and concerns; production recommendation safety primarily screens Injury objects.

**Required action:** Add a centralized SafetyGate. Raw medication strings may not be classified by model memory.

## RE-H01 — HIGH — AI Planner / onboarding preview ignore equipment availability

**Evidence:** `mobile/lib/features/ai_planner/state/ai_planner_providers.dart`, `mobile/lib/features/onboarding/state/plan_preview_provider.dart`, `mobile/lib/features/ai_planner/data/plan_builder.dart`

**Finding:** Candidate pools include bodyweight plus every equipment's exercises. buildPlan filters injuries but does not consume EquipmentAccess/location.

**Required action:** Route through centralized eligibility before ranking.

## RE-H02 — HIGH — Home Suggestions ignore EquipmentAccess

**Evidence:** `mobile/lib/features/home/state/suggestion_providers.dart`, `mobile/lib/features/equipment/state/equipment_providers.dart`

**Finding:** Home uses forYouExercisesProvider; it injury-screens and tier-sorts but does not apply availableWith(profile.equipment).

**Required action:** Use Recommendation Engine eligible candidates.

## RE-H03 — HIGH — Exact-kg progression is a hard-coded heuristic

**Evidence:** `mobile/lib/features/workouts/data/progression.dart`, `mobile/lib/features/equipment/workout_player_page.dart`

**Finding:** UI directly surfaces kg from fixed -5%, +5%, +2.5/+1.25 rules, default 8 reps and default compound=true.

**Required action:** Replace with load/progression engine using history quality, target effort, load context, staleness and equipment increments.

## RE-H04 — HIGH — Isolation increment is destroyed by rounding grid

**Evidence:** `mobile/lib/features/workouts/data/progression.dart`

**Finding:** The 1.25kg isolation increment is passed through a global nearest-2.5kg rounder.

**Required action:** Rounding must be equipment-context-specific and applied after a valid target is calculated.

## RE-H05 — HIGH — Legacy history view loses set-level information

**Evidence:** `mobile/lib/features/workouts/data/workout_session.dart`, `mobile/lib/features/workouts/state/workout_session_providers.dart`

**Finding:** asLogEntries emits one compatibility row per exercise using only its last set. A progression engine cannot infer full performance from this view.

**Required action:** New engine reads WorkoutSession / per-set data directly.

## RE-H06 — HIGH — Performed-set model lacks effort and load context

**Evidence:** `mobile/lib/features/workouts/data/set_capture.dart`, `mobile/lib/features/workouts/data/workout_session.dart`

**Finding:** SetCapture only stores weightKg/reps; no RIR/RPE, equipment instance/load context, or recommendation link.

**Required action:** Add backward-compatible performed-set/context fields in a dedicated migration gate.

## RE-H07 — HIGH — Programme schedule is exercise-duration rotation, not prescription

**Evidence:** `mobile/lib/features/programmes/data/programme_schedule.dart`, `mobile/lib/features/workouts/data/scheduled_session.dart`

**Finding:** The schedule stores exercises and duration but no sets/reps/effort/load prescription; current rows use uniform 10-minute exercise durations per generator comments.

**Required action:** Add an optional prescription snapshot to scheduled sessions without breaking old documents.

## RE-H08 — HIGH — Recovery detector conflates adherence with physiological recovery

**Evidence:** `mobile/lib/features/recovery/data/deload_detector.dart`, `mobile/lib/features/recovery/state/recovery_providers.dart`

**Finding:** Missed scheduled sessions are one of the deload signals; HRV is not currently wired; a fixed 0.5 factor scales scheduled duration.

**Required action:** Split readiness/recovery from adherence and from dose adaptation.

## RE-M01 — MEDIUM — Set timer presets can be mistaken for prescription

**Evidence:** `mobile/lib/features/workouts/data/set_session.dart`, `mobile/lib/features/workouts/state/set_timer_providers.dart`

**Finding:** Tier-based fixed work/rest/set presets are useful timer defaults but are not goal-specific training prescription.

**Required action:** Keep as UX preset or make it consume engine prescription; label policy class explicitly.

## RE-M02 — MEDIUM — Loaded-equipment whitelist is incomplete by construction

**Evidence:** `mobile/lib/features/workouts/data/set_capture.dart`

**Finding:** exerciseUsesLoad uses a fixed whitelist; unknown equipment defaults to no load capture.

**Required action:** Move load semantics to exercise/equipment recommendation metadata while retaining conservative fallback.

## RE-M03 — MEDIUM — Documentation drift

**Evidence:** `CLAUDE.md`, `AGENTS.md`, `core/CODEMAP.md`, `core/CONVENTIONS.md`

**Finding:** Historical counts/capabilities differ across docs; current code must be source of truth for implementation.

**Required action:** Update CODEMAP/CONVENTIONS in the same commit when Recommendation Engine feature is added.

## RE-K01 — KEEP — Cold-start safety screening is fail-closed

**Evidence:** `mobile/lib/features/equipment/state/equipment_providers.dart`

**Finding:** screeningProfileProvider awaits auth and profile instead of treating AsyncLoading as no profile.

**Required action:** Reuse this pattern in RecommendationContext.

## RE-K02 — KEEP — Sensitive health profile is device-local

**Evidence:** `mobile/lib/main.dart`

**Finding:** DeviceHealthProfileRepository merges local sensitive data with Firestore profile.

**Required action:** Engine consumes merged provider; never bypass it with direct Firestore reads.

## RE-K03 — KEEP — Scanner has explicit uncertainty states

**Evidence:** `mobile/lib/features/visual_equipment/data/scan_outcome.dart`, `mobile/lib/features/visual_equipment/data/visual_equipment_match.dart`

**Finding:** The scanner distinguishes alternatives/unknown/failure and deliberately distrusts high-confidence offline results.

**Required action:** Preserve source/outcome in RecommendationContext.

## RE-K04 — KEEP — Form Check says cannot-tell instead of inventing faults

**Evidence:** `mobile/lib/features/form_check/data/pose_gate.dart`

**Finding:** Pose gate separates unscorable frames from bad form.

**Required action:** Use only validated observable signals; no diagnosis/injury-risk claims.
