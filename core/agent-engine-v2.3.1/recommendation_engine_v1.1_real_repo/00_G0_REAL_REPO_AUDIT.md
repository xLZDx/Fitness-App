# G0 — Real repository audit

## 1. Baseline

Audited remote repository:

- `xLZDx/Fitness-App`
- private
- default branch: `master`
- remote HEAD: `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`
- commit timestamp: `2026-08-15T11:48:20Z`

The GitHub connector can inspect the remote repository but cannot establish the
operator's **local** working-tree facts such as uncommitted changes, untracked files,
or `@{u}..HEAD` in `D:\Repo\Fitness_App`. Therefore this report does **not**
claim the local checkout is clean.

The HEAD commit itself explicitly records that another session had uncommitted
Form Check WIP in a shared working tree when that commit was written. That makes
"remote HEAD == local working tree" an unsafe assumption.

## 2. Architecture verified from code

Production app wiring remains:

- Flutter / Dart
- Riverpod
- go_router
- Firebase Auth / Firestore / Functions
- `DeviceHealthProfileRepository(FirestoreProfileRepository, PrefsSensitiveStore)`
- canonical new workout writes through `FirestoreWorkoutSessionRepository`
- programmes through `FirestoreProgrammeRepository`
- health through `PlatformHealthService`
- Form Check through ML Kit pose detection
- equipment recognition through cloud + on-device hybrid recognition

### Safety-sensitive profile data is device-local

`main.dart` wires `DeviceHealthProfileRepository` so the health block is merged from
the local sensitive store instead of being stored in Firestore.

**Implementation consequence:** Recommendation Engine must consume the existing
`currentProfileProvider` / `screeningProfileProvider`. It must not bypass them and
query Firestore directly, or conditions/injuries/medications can disappear from the
decision context.

## 3. Existing recommendation-related flows

### A. Injury screening

Current central primitive:

`mobile/lib/features/equipment/data/exercise_filter.dart`

It provides:
- injury contraindication filtering;
- tier sorting;
- focus-zone mapping;
- equipment availability filtering (`availableWith`);
- conservative handling of unknown equipment in non-gym contexts.

`screeningProfileProvider` correctly waits for both auth and the profile before
serving safety-sensitive exercise results. This is an important fail-closed primitive
and should be retained.

### B. Equipment detail recommendations

`recommendedExercisesProvider(equipmentId)`:
- resolves catalog/AI fallback;
- removes generated AI exercises when the profile has injuries because they do not
  have trusted contraindication metadata;
- requires a real demonstration;
- applies injury filtering and tier ordering.

This is conservative and should remain underneath the new engine.

### C. Public catalog / For You

`safeCatalogProvider`:
- injury screens the complete public catalog.

`forYouExercisesProvider`:
- tier-sorts `safeCatalogProvider`.

**Gap:** it does **not** apply the user's `EquipmentAccess`.

### D. Home Suggestions

`home/state/suggestion_providers.dart` reads:
- `forYouExercisesProvider`;
- profile;
- workout-session history.

`suggestion_builder.dart` then independently scores candidates using goal/history/
duration heuristics.

**Gap:** because the candidate provider is not equipment-filtered, Home can rank an
exercise requiring equipment that the user's questionnaire says is unavailable.

### E. Programme enrollment

`ProgrammeAction.enroll()` is currently the strongest questionnaire-aware path:
- waits for `screeningProfileProvider`;
- reconciles requested training days and exact weekdays;
- resolves focus zones;
- obtains `safeCatalogProvider`;
- applies `availableWith(profile.equipment)`;
- builds the schedule from that narrowed catalog.

KEEP this persistence/orchestration shape.

### F. Template fit

`programme_fit.dart` calculates five explicit boolean dimensions:
- goal
- level
- schedule
- zones
- equipment

The score is internal and not exposed as a fake percentage. This is a good product
choice.

**Gap:** equipment fit is muscle-coverage feasibility rather than proof the exact
template/session prescription can be instantiated.

### G. Programme schedule generation

`programme_schedule.dart`:
- creates real exercise IDs;
- respects preferred weekdays;
- creates multi-exercise days;
- uses an already injury/equipment-narrowed catalog;
- rotates by muscle and fills time greedily.

But it still plans primarily as:

`muscle -> exercise list -> target minutes`

rather than:

`training objective -> movement slots -> sets/reps/effort/rest/load -> weekly dose`.

Its own comments state the current 1,887 catalog rows each use 10 minutes, so the
time budget currently approximates "number of exercises", not a true session-duration
model.

### H. AI Planner and onboarding preview

`generatedPlanProvider` and `onboardingPlanPreviewProvider` build the candidate pool
as:
- bodyweight exercises;
- exercises for **every** equipment item in the repository.

They then call `buildPlan()`.

`buildPlan()`:
- filters injuries;
- ranks by the muscle fitness model;
- greedy-fills a time cap;
- applies a deload/cycle intensity factor.

It does **not** receive the user's:
- equipment availability;
- training location;
- primary goal;
- level;
- focus zones;
- exact weekdays.

This is a separate decision engine with materially different rules from Programme
enrollment.

### I. Personalisation

`fitness_model.dart` converts perceived difficulty into a per-muscle score:
- tooEasy -> +1 good
- justRight -> +0.5
- tooHard -> +0

Its comment says a lower score should be downweighted to give a muscle recovery time.

But `for_you_ranker.dart` computes:

`priority = 1 - profile.averageFor(muscles)`

Therefore a **lower** score is ranked **higher**.

This creates a direct semantic inversion:
- repeated "too hard" lowers the score;
- lower score raises priority;
- the same muscle can then surface more aggressively.

This must not be inherited by Recommendation Engine.

### J. Workout history

Canonical write model:
- `WorkoutSession`
- `WorkoutSessionExercise`
- `SetCapture`

Good:
- a workout can hold multiple exercises;
- an exercise structurally supports a list of sets;
- sessions preserve one-workout semantics.

Current limitation:
- `SetCapture` contains only `weightKg` and `reps`;
- no RIR/RPE;
- no planned target;
- no equipment/load context;
- no link to the recommendation that produced the target.

`WorkoutSessionLogView.asLogEntries()` converts a session to the old
`WorkoutLogEntry` compatibility view and keeps only the **last set** for an exercise.
That is acceptable for legacy charts but is not sufficient for a new progression
engine.

The current Workout Player completion path also persists at most one captured set
per exercise in the primary flow even though the model supports a list.

### K. Progression

`workouts/data/progression.dart` currently makes exact-kg recommendations using hard
rules:

- tooHard -> -5%
- 3 × tooEasy + target reps -> +5%
- 2 × justRight + target reps -> fixed +2.5 kg compound / +1.25 kg isolation
- default target reps = 8
- default isCompound = true
- all results rounded to 2.5 kg

This is exactly the type of policy that v2.2 classified as a product heuristic rather
than universal evidence.

There is also an internal arithmetic defect: the "1.25 kg isolation increment" is
subsequently rounded to a 2.5 kg grid, so it cannot reliably remain a 1.25 kg
increment.

Workout Player displays the output directly as "Suggested kg".

### L. Set timer vs prescription

`SetPlan` contains fixed timer presets:
- beginner: 3 × 20s / 20s rest
- intermediate: 3 × 30s / 10s rest
- advanced: 4 × 45s / 10s rest

Loaded work adjusts time/rest via an equipment whitelist.

These can remain **timer UX presets**, but they must not be treated as the training
prescription engine. A training prescription requires objective-specific sets/reps,
target effort, rest and load logic.

### M. Recovery / deload

`deload_detector.dart` uses:
1. difficulty trend;
2. missed scheduled sessions;
3. optional HRV trend.

Two-of-three triggers a fixed 0.5 factor.

Current provider does **not** wire HRV at all, despite HealthSnapshot supporting it.
Therefore in current production the detector effectively needs the two remaining
signals.

More importantly, missing scheduled workouts is an adherence/schedule-fit observation,
not necessarily a physiological recovery signal. Treating it as fatigue can conflate
"busy week" with "needs a deload".

`DeloadAction` then scales **scheduled duration**, not measured training volume.

Recommendation Engine should split:
- recovery/readiness;
- adherence/schedule fit;
- training-dose adaptation.

### N. Health data

`HealthSnapshot` already supports:
- steps;
- active minutes;
- resting HR;
- sleep score;
- HRV;
- activity-ring percent.

Providers currently expose today and last 7 days.

No 30-day HRV baseline provider is wired into the current deload path.

### O. Clinical intake usage

`HealthHistory` stores:
- conditions;
- allergies;
- raw medication strings;
- injuries;
- physical limitations;
- recent surgeries;
- blood pressure category;
- other concerns.

Production search shows exercise decision logic currently consumes **injuries**.
Fields such as medications, blood pressure and physical limitations are collected and
stored, but do not form a general clinical safety gate for recommendation generation.

This is a major gap relative to the requested safety architecture.

### P. Medication model

Current profile storage is:

`List<String> medications`

This has no verified:
- normalized name;
- drug class;
- exercise effect tags;
- source;
- verification timestamp.

Recommendation Engine must not infer these from the raw string.

### Q. AI Coach

`ai_coach_context.dart` currently tells the cloud model to generate:
- technique;
- mistakes;
- beginner volume;
- for an exercise, a **starting load cue**.

The context intentionally excludes private health data.

That privacy decision is sensible, but it also means the cloud model cannot safely
own individual prescription. There is no deterministic post-validator that prevents
the model from inventing kg/sets/reps.

Recommendation Engine v1.1 should remove numeric prescription authority from the AI
Coach. The UI renders deterministic prescription; AI explains technique and rationale.

### R. Scanner

The scanner already has a good uncertainty model:
- confident
- alternatives
- unknown
- noEquipment
- timeout
- failed

The offline 10-class classifier is explicitly prevented from claiming a confident
identification because measured high-confidence wrong answers exist.

KEEP this uncertainty. Recommendation Engine must consume the scan **outcome/source**,
not only `equipmentId`.

### S. Form Check

`pose_gate.dart` has the correct philosophy:
- unusable frame -> cannot tell;
- never convert missing/confidence/framing problems into "bad form";
- thresholds are explicitly opening product values, not measured truth.

KEEP this boundary. v1 should not use Form Check as a diagnosis or injury-risk engine.

## 4. Documentation drift

Repository docs are not perfectly synchronized. Examples found during G0 include
different historical test counts and stale descriptions of injury coverage.

Rule for implementation:
1. current code;
2. current tests;
3. current gate/state docs;
4. older descriptive docs.

Do not reintroduce behavior solely because CODEMAP text says it exists.

## 5. G0 verdict

**Architecture direction: APPROVE WITH REQUIRED FIXES.**

Do not build a second recommendation stack.

Recommendation Engine v1.1 should become the single decision boundary and migrate
existing consumers one by one.

**STOP — G0 only; no repository files modified.**


## 6. Independent remote re-verification, 2026-08-15

The pinned commit `5b7c9acc7acdd00db502e1934afd2c75983eaeb9` was fetched again and the two load-bearing findings were rechecked
against files at that exact ref. Progression hard-coded rules and RE-B01 both remain present.
Remote G0 remains valid. Local shared working-tree state remains outside GitHub-connector scope.
