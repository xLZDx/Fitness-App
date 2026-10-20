# C15 change record: intro view, weight prompt sheet, analysis progress view

Story: C15, part 3 of 4.

## What changed
- `mobile/lib/features/body_scan/widgets/intro_view.dart`: intro with the plain-language "rough estimate from height, weight and age" label for the provisional estimator (D-73) and the measurement-only note (D-74). 48 dp buttons.
- `.../widgets/weight_prompt_sheet.dart`: modal sheet (framework modal route), initial focus on the heading, comma or point decimals, 20-400 kg validation, Save / Skip results (D-85).
- `.../widgets/analysis_progress_view.dart`: five named stages, plain elapsed counter, one polite live region for stage changes and the 20 s notice, single assertive announcement at 25 s with focus moved to Retry, Cancel first in focus and semantics order, no animation when reduced motion is set (D-81).

## Affected contracts
New files only. Uses existing HUD tokens, `GlassCard`, and l10n keys from the ARB commit.

## Verification state
Not run (operator rule); test agents own widget tests and the tap-target guideline sweep.
