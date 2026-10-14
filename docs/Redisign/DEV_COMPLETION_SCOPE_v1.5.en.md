# Dev Agent — Complete Missing Refactor Scope — v1.5 (English)

**English companion:** Original [developer completion scope](DEV_COMPLETION_SCOPE_v1.5.md), exact Git blob `9c3b3355421eddc400387558a7f05892d9a0a90d`. Original historical assertions are requirements to verify against code, not certification of a current feature or permission to bypass any operator-held gate.

The Figma prototype has not yet been completely wired. This does not block
implementation.

Start with a read-only audit and compare this list against the current repository.
Do not treat a missing Figma frame as proof that the corresponding feature is absent from code.

## Existing repository facts to verify/preserve

- Flutter/Riverpod/go_router stack.
- `/form-check` route already exists.
- `/photos` progress-photo route already exists.
- Scanner/history and local fallback logic already exist.
- Progress feature already has charts/stats implementation.
- AI Coach already exists and is consumed by equipment-related flows.

## Gate R1 — Home completion

Implement:

- weekly calendar;
- milestones block;
- horizontal recovery list;
- visible scroll affordance;
- empty/loading/error states;
- responsive/safe-area behaviour.

Use approved tokens/components. No new design language.

## Gate R2 — Scanner completion

Preserve and restyle:

- scan history;
- saved machine cards;
- unknown equipment;
- offline/local fallback;
- permission/network/error states;
- navigation to equipment and AI Coach context.

Do not replace unknown equipment with nearest incorrect catalog result.

## Gate R3 — Exercise Page

After receiving the minimal approved Exercise Page frame:

- add a dedicated route/page if absent;
- map real exercise/catalog data;
- media lifecycle;
- muscles;
- instructions;
- common errors;
- restrictions;
- history;
- suitability;
- Add to Workout;
- Start Exercise;
- AI Coach entry;
- TechCoach entry;
- loading/empty/error states;
- tests.

Do not duplicate WorkoutPlayer business logic into the page.

## Gate R4 — TechCoach entry and Summary consolidation

- wire Exercise Page → `/form-check` with exercise context;
- preserve WorkoutPlayer entry;
- decide Q26 before mutation;
- recommended default: WorkoutSummary canonical;
- migrate WorkoutDone logic/state;
- remove or reduce old screen to compatibility wrapper;
- one persisted completion path;
- regression tests.

## Gate R5 — Real Progress charts

Implement real data-backed:

- Strength line chart;
- Volume weekly bars;
- Consistency calendar/weekly bars;
- Muscle load anatomy/ranked bars;
- date/period selectors;
- loading/empty/error/insufficient-data states;
- accessibility labels;
- no fake or medically precise values.

If Figma has only placeholders, use v1.5 recommended defaults and submit
screenshots for visual review.

## Gate R6 — AI Coach contextual integration

Add contextual entries from:

- Scan result;
- Equipment;
- Exercise;
- Recovery;
- Workout Summary where useful.

Reuse existing AI Coach UI/service/cache. Pass explicit context; do not create
parallel chat architecture.

## Gate R7 — Platform, light theme, accessibility and offline

- build semantic light theme or consume approved palette;
- preserve dark theme;
- Android/iOS safe areas and native behaviour;
- large text;
- semantics;
- focus order;
- reduced motion;
- offline states;
- permission states;
- contrast audit.

## Gate R8 — End-to-end wiring

Implement real route flow even if Figma prototype links are incomplete:

Onboarding
→ Home
→ Scan
→ Result
→ Equipment
→ Exercise Page
→ Workout Player
→ Complete Set
→ Rest Timer
→ Next Set
→ TechCoach
→ Workout Summary
→ Progress.

Rest Timer screen/state must have a real entry and exit.
No dead screen types.

## Verification

After every gate:

- targeted tests;
- regression tests;
- flutter analyze;
- emulator screenshot;
- compare to nearest approved Figma frame;
- document any dev-owned visual decision;
- one local commit;
- STOP;
- no push without push-GO.
