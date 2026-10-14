# Change record: Body Scan + Nutrition Coach sprint plan, test coverage map, reference notes

## What changed
Documentation only, no code:
- `core/plans/BODY_SCAN_NUTRITION_SPRINT_PLAN_2026-10-15.md` (new): 27 ordered commits in nine epics (rules and flags first, pure-Dart domain, onboarding, body scan, nutrition plan, food scanning, privacy, l10n and accessibility, docs), per-commit file lists, Definition of Done, verification plan, risks and the operator-owned items with defaults.
- `core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md` (new): 201 requirement ids mapped to 126 focused test files, negative paths, items that cannot be verified without a device or operator action, and the per-epic and final full-set run order for the test-writing agents.
- `core/plans/BODY_SCAN_REFERENCE_BEHAVIOUR_NOTES_2026-10-15.md` (new): sanitised, own-words distillation of the operator's reference recordings (flows, state machines, observed and inferred numbers, formula checks).
- `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md`: sections 3, 10, 12, 13, 17.7 and 29 updated from the notes; decisions D-37..D-45 added.
- `core/DECISION_LOG.md`: one entry (plan, clamps-win rule, test execution policy).
- `core/INDEX.md`: the three new documents registered.

## Why
DEVELOPMENT RULES v4 step 1 (documentation first) and the operator's 2026-10-15 scope and test-policy updates.

## Affected contracts and paths
None changed yet. Changed design values that later documents must cite: loss range -200/+100 kcal, BMI >= 30 default loss rate 0.75 %/week, smoothing warm-up (alpha = max(weekly rule, 1/n)), Atwater tolerance max(25 %, 10 kcal), first review on day 7. Two test-infrastructure prerequisites are recorded (argument forwarding in `functions/scripts/run_emulator_tests.js`, a Storage emulator entry in `firebase.json`).

## Verification state
Nothing executed: no tests, analyzer, build, lint or CI. The test map is a plan; the tests do not exist yet.

## Review state
Pending the single documentation review pass (architect, security-reviewer, database-reviewer, product-ux-reviewer, a11y-architect).
