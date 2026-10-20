# S02 test plan added; summary revision counter settles the ordering question

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- Added `docs/phase2/s02/S02_TEST_PLAN.md` (181 planned tests: 37 Dart unit, 30 Dart integration, 31 Firestore rules, 3 Storage rules, 75 functions unit with fakes, 5 fake-backed E2E; generator spec for 100 synthetic sessions; requirement-to-test map; per-epic run order; NOT_RUN list). Authored and aligned to the revised design by a `functional-test-reviewer` agent.
- `docs/phase2/s02/S02_DESIGN.md`: the summary document gets a monotonic `rev` that rules require to be 1 on create and strictly increasing on update (section 3.2 row, rules snippet, section 14 answer to DQ-5). This resolves the conflict the test planner reported: the summary is written offline by the client, so no server stamp exists on it.
- Test plan note: five rules tests for `rev` (R32-R36).

## Why
Phase 4 of S02 (test plan) and removal of an open design conflict before the review.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`.

## Verification state
No tests or checks were run. Untestable by design and marked NOT_RUN: tombstone TTL deletion, real bucket behaviour, deploy order, alert delivery. Disguised heart rate cannot be detected structurally and is documented as accepted residual risk. Operator-owned answers still pending: cloud stream kinds beyond GPS, the "never" retention option, the default expiry value.
