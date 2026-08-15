# Fitness-App Recommendation Engine v1.1 — real-repo binding

**Repository:** `xLZDx/Fitness-App` (private)  
**Branch audited:** `master`  
**Remote HEAD audited:** `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`  
**Audit mode:** READ-ONLY  
**Repository writes:** NONE

This bundle supersedes the speculative file/class mapping in Recommendation Engine v1.
It is grounded in the actual private repository at the commit above.

## Files

- `00_G0_REAL_REPO_AUDIT.md` — verified current-state audit.
- `01_IMPLEMENTATION_MAP.md` — exact KEEP / EXTEND / REPLACE / DEPRECATE mapping.
- `02_FINDINGS_REGISTER.md` — prioritised defects and architectural gaps.
- `03_DATA_CONTRACT_AND_MIGRATION.md` — data evolution for prescription/load/progression.
- `04_GATE_PLAN.md` — implementation sequence after a separate implementation GO.
- `05_TEST_MATRIX.md` — release/eval matrix.
- `06_G1_CLAUDE_CODE_PROMPT.md` — implementation prompt for the first write gate only.
- `implementation_map.json` — machine-readable map.
- `findings.json` — machine-readable findings register.

## Core conclusion

The app already contains many of the right primitives, but decision logic is fragmented across:

- `equipment/data/exercise_filter.dart`
- `home/data/suggestion_builder.dart`
- `personalisation/data/fitness_model.dart`
- `personalisation/data/for_you_ranker.dart`
- `ai_planner/data/plan_builder.dart`
- `programmes/data/programme_fit.dart`
- `programmes/data/programme_schedule.dart`
- `workouts/data/progression.dart`
- `recovery/data/deload_detector.dart`
- `workouts/state/set_timer_providers.dart`
- `ai_coach/ai_coach_context.dart`

Recommendation Engine v1.1 should centralise **eligibility, prescription, load,
progression and validation**, while keeping the existing repositories, profile models,
catalog, programme persistence, workout-session persistence, scanner pipeline,
Form Check pipeline and Firebase wiring.

**STOP — this bundle is design/audit only. No repository files were modified.**
