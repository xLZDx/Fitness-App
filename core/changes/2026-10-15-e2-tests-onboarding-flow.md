# E2 tests: l10n, nutrition profile flow, onboarding page journey, router gating (part 2)

## What
- NEW `mobile/test/l10n/onboarding_nutrition_l10n_test.dart`: EN/RU key and placeholder parity for onbNutrition*/nutProfile*/onbStepNutrition/onbDietPescatarian/healthStepProfessionalGuidance, RU one/few/many/other completeness, the generated `onbNutritionPaceMessage(String kg, int weeks)` signature and plural rendering (EN 1/2/0, RU 1,2,3,4,5,11,12,14,21,22,25,101,111), exact D-75 safety copy through the generated class, no diagnostic words.
- NEW `mobile/test/features/nutrition_plan/nutrition_profile_flow_page_test.dart`: sheet list from `missingNutritionInputs`, fixed on entry, live lock-out, final-Save-only `NutritionPrefs.completedAt`, profile `completedAt` carried through, cancel writes nothing, RU 360x640 text scale 2.0.
- NEW `mobile/test/features/onboarding/onboarding_nutrition_flow_test.dart`: real `OnboardingPage` journey, no pace text before the nutrition step, none/none unlocks, reported keeps the lock, Change link returns to the personal screen, completedAt stamping on leaving the step.
- NEW `mobile/test/router/nutrition_profile_route_test.dart`: finished users never redirected to /onboarding, `redirectFor` unchanged, route registered once. See the verification section for its run state.
- UPDATED `mobile/test/features/onboarding/step_answered_test.dart`: the two "fully answered" drafts now include a nutrition answer (otherwise the new step is the first gap and the resume index is not the last screen / the screening step); added an order assertion (healthFlags, nutrition, screening). No assertion was weakened.

## Verification (Flutter 3.27.1, `flutter test --no-pub -r expanded <single file>`, cwd `D:\Repo\Fitness_App_bodyscan\mobile`)
- onboarding_nutrition_l10n_test.dart: 18 passed
- nutrition_profile_flow_page_test.dart: 16 passed
- onboarding_nutrition_flow_test.dart: 8 passed
- step_answered_test.dart: 19 passed
- nutrition_profile_route_test.dart: NOT_RUN. It imports app_router.dart, which transitively imports other epics' in-flight lib files that do not compile at this head (data_export/server_export.dart missing ServerExport.fetchAll, body_scan_result_page.dart ScanHistoryRow? nullability, body_scan_flow_driver.dart ScanPose undefined, earlier trend_chart.dart CustomSemanticsAction). Not E2 code; not edited here.
- Final complete E2 run at head 40022ed: data 47, step_nutrition 50, l10n 18, flow page 16, onboarding journey 8, step_answered 19 passed (158 total); route NOT_RUN.
- Existing files checked because E2 touches what they cover (all passed): onboarding_shell_test 12, training_schedule_test 14, body_zones_test 17, barriers_test 9, f014_professional_guidance_test 20, profile_models_test 15, step_health_test 1, questionnaire_notifier_test 4.
