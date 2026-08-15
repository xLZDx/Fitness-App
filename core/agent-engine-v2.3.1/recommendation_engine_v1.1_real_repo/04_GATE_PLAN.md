# Implementation gates after G0

No gate below is authorized by this G0 audit alone.

## G1 — Contracts + shadow context only

Create `features/recommendation/`:
- domain enums/models;
- RecommendationContext builder;
- RecommendationResult;
- reason codes;
- validator interface;
- no UI behavior change.

Context sources:
- screeningProfileProvider
- safe catalog / catalog repository
- WorkoutSession history directly
- scheduled sessions
- active programme
- health providers as optional/freshness-tagged inputs

Tests:
- loading profile cannot become "no restrictions";
- missing optional health remains missing, not zero;
- no duplicate UserProfile/ExerciseItem models.

**STOP / local commit.**

## G2 — Single eligibility boundary

Implement:
- SafetyGate interface/state;
- ExerciseEligibility;
- reuse `safeFor`;
- reuse `availableWith`;
- current-session scanner equipment override;
- unknown/review states.

Initially keep clinical rules conservative and explicitly versioned.

Shadow-run against existing Home/AI Planner/Programme pools and produce only test/debug
diffs, no user-visible switch.

**STOP / local commit.**

## G3 — Correct split-brain candidate selection

Migrate consumers one by one:
1. Home Suggestions
2. AI Planner
3. onboarding Plan Preview

Immediate correctness goals:
- unavailable equipment never wins;
- injury behavior does not regress;
- location/equipment questionnaire is honored consistently;
- AI Planner stops building from "all machines";
- Home does not bypass EquipmentAccess.

Do not change programme persistence yet.

**STOP / local commit.**

## G4 — Personalisation semantics

Replace the current sign-inverted adaptive ranking.

Separate:
- exposure/history;
- perceived effort/tolerance;
- recovery/readiness;
- goal preference;
- novelty/adherence.

"Too hard" can never, by itself, increase the same muscle's training priority.

Shadow compare old vs new ranking, with deterministic fixtures.

**STOP / local commit.**

## G5 — Performed-set data evolution

Backward-compatible model migration:
- PerformedSet with optional RIR/RPE;
- preserve all sets;
- equipment/load context snapshot;
- recommendation/prescription linkage.

Do not change old Firestore documents.

Update every affected serializer/test in the same gate.

**STOP / local commit.**

## G6 — Prescription + Load + Progression

Implement deterministic:
- sets/reps/duration;
- target RIR/RPE;
- rest;
- exact/range/calibration load;
- progression/hold/regress/recalibrate.

Replace `progression.dart` as policy owner.

Release invariants:
- no history -> no invented kg;
- stale/nontransferable history -> calibration;
- machine context unknown -> no silent exact-load transfer;
- equipment increment controls rounding;
- all numeric outputs have calculation trace/reason code.

**STOP / local commit.**

## G7 — Programme/session prescription

Keep Programme/ScheduledSession repositories.

Replace `programme_schedule.dart`'s exercise-only session content with engine-produced
exercise + prescription snapshots while preserving:
- preferred weekdays;
- multi-exercise day;
- one day = one WorkoutSession;
- old document compatibility.

Template ranking becomes:
1. feasibility;
2. fit/rank.

An infeasible template cannot receive Best Fit.

**STOP / local commit.**

## G8 — Recovery/adherence separation

Refactor deload:
- missed workouts -> adherence/schedule-fit signal;
- wearable/readiness -> optional physiological signal;
- subjective difficulty -> workload tolerance signal;
- freshness/provenance mandatory.

No universal "two signals => halve everything".
No use of `durationMinutes` as a proxy for training volume.

**STOP / local commit.**

## G9 — AI boundary

AI Coach:
- remove authority to invent starting kg and independent volume;
- deterministic prescription rendered separately;
- AI can explain technique/reason codes.

AI Planner:
- becomes an adapter/view onto Recommendation Engine session output.

Add validator tests that reject novel numeric prescription if AI text is ever allowed
to discuss prescription.

**STOP / local commit.**

## G10 — Scanner / Form Check context

Scanner:
- preserve outcome/source;
- only confident or user-confirmed identity establishes current equipment.

Form Check:
- only validated observable signals;
- no diagnosis;
- no future injury prediction;
- low confidence -> cannot evaluate.

Do not alter load based on one low-confidence frame.

**STOP / local commit.**

## G11 — Release gate

Required:
- `flutter analyze`
- complete host `flutter test`, 0 failures
- recommendation adversarial suite
- v2.2 safety cases adapted to real engine
- migration/backward parsing tests
- real device/emulator integration test
- scanner confidence states
- Form Check invalid-frame behavior
- RU + EN UI for reasons
- audit trace test
- no raw sensitive health data in server-side recommendation trace

Only after actual execution may the gate be called PASS.
