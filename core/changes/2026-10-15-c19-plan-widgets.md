# C19 plan widgets (part 1)

What: new widgets under `mobile/lib/features/nutrition_plan/widgets/`:
`kcal_range_slider.dart` (custom two-thumb slider, per-thumb semantics with
increase/decrease of 10, bound and gap announcements, +/-10 and +/-100
steppers, pure `moveKcalThumb`), `macro_ranges_card.dart` (macro ranges and
steps goal steppers), `ownership_selector.dart`, `auto_adjust_toggles.dart`,
`professional_notice.dart`.

Why: sprint plan story C19, design D-82 (slider contract), s18 (ownership), D-55.

Contracts: widgets are controlled and write nothing; the plan page persists
through `NutritionPlanActions`. Uses l10n keys added in the C19 ARB commit
(`nutrition*`); this commit does not compile alone until that commit lands.

Verification: none run (operator rule: tests are written and run by the test agents).
