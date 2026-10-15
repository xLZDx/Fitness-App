# Change record: C11 nutrition profile flow

## What changed
- NEW `mobile/lib/features/nutrition_plan/nutrition_profile_flow_page.dart`: `NutritionProfileFlowPage` plus the pure `nutritionProfileSheets(missing)` and `NutritionProfileSheet {safety, body, food}`. Up to three sheets: (1) the two safety questions (only those unanswered), (2) the missing body and goal inputs only (birth year, height, weight, sex basis, activity, goal), (3) food and activity (steps, allergens, excluded foods, meals, ownership). It reuses the C10 widgets in `onboarding/widgets/nutrition_inputs.dart` and the `QuestionnaireDraft` update methods, and saves through `saveDraft()` (the existing profile repository).
- `core/router/app_router.dart`: only `/nutrition/profile` is registered; other `/nutrition*` and `/body-scan*` paths arrive with their pages.
- ARB `nutProfile*` EN + RU.

## Why
Sprint plan C11; design s16.3, D-55, D-75; coverage map ONB-*.

## Behaviour
- Existing onboarded users are not routed to `/onboarding` (`redirectFor` unchanged; an onboarded user is never redirected away from this path). Nothing is written until the user acts.
- The draft is rebuilt from the cached profile after the first frame, then the sheet list is fixed once from `missingNutritionInputs`, so a field filled mid-sheet does not disappear.
- Safety first: sheets 2 and 3 show only the neutral lock-out notice (plus allergens, excluded foods, meals on sheet 3) while either safety answer is not `none`, evaluated live so answering `reported` on sheet 1 locks the rest immediately.
- `NutritionPrefs.completedAt` is stamped on the final Save only; the profile `completedAt` (`hasCompletedOnboarding`) is carried unchanged by the draft copy.

## Deviations
- The sheets are pages of one full-screen flow (progress "Step n of m", m = 1..3), not modal bottom sheets, for focus and text-scaling reasons. The count is the sheets this profile needs, so a profile missing nothing sees only the food sheet.
- An already-answered safety question is not asked again here; it is changed through onboarding edit.
- The pace line and body-fat target are not repeated in the flow (they live on the onboarding step).
- Not done here: the Plan screen / Home card buttons that navigate to this route (C18/C19 own those screens). VERIFY outcome: `FirestoreProfileRepository.save` writes `profile.toJson()` with merge, and the draft is a copy of the cached profile, so `completedAt` is preserved.

## Affected contracts and paths
New route `/nutrition/profile`; `questionnaireDraftProvider` is invalidated on entry.

## Verification state
Not run, per DEVELOPMENT RULES v4.

## Review state
Pending the test phase and specialist reviewers.
