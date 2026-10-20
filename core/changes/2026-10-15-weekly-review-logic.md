# Change record: C06 weekly review pure logic

## What changed
Pure Dart (no Flutter imports) under `mobile/lib/features/nutrition_plan/data/`:
- `weekly_review.dart`: `ReviewInput` (incl. `basePlanVersion`), `decide(ReviewInput)` returning `WeeklyReviewDecision?` (null when not eligible), closed enums `ReviewClass`, `ReviewDecisionKind` (keep, adjustKcal, adjustSteps, needMoreData, needRecalculation; no `referProfessional`, D-55), `ReviewApplication` (coached applied / shared proposed / manual insight only), `ReviewReason` (closed non-health codes), `AutoAdjust`, `intendedKgPerWeekFor`, and the ISO week key (`isoWeekKeyForDate`, `reviewWeekKey` with an explicit UTC offset so the result never depends on the machine zone).
- `body_fat_trend_source.dart`: the PORT `BodyFatTrendSource` / `BodyFatTrendInput` (D-71) with a safe `NoBodyFatTrendSource` default; a provisional or changed-model series never counts as a meaningful decrease (D-54).

Rules implemented (design s15): needMoreData under 3 weigh-ins or 7 days; tolerance `max(0.15, 25 % of intended)` with an epsilon so `|e| == tol` is on track; `tooFast` (loss/gain faster than row maximum x 1.25) acts immediately with +150 (loss) / -150 (gain); `behind` needs the same classification in the previous review and a 14-day cooldown, then steps +1,000 first (if allowed and <= 12,000) else kcal +-150; maintain drift +-100 on the same two-review rule; recomposition keeps the plan; `|drift + delta| > 400` gives needRecalculation; a shifted range that would leave the recomputed bounds becomes `keep(atSafetyLimit)` instead of being truncated.

## Why
Sprint plan commit C06; design s15, D-8, D-55, D-57, D-71; coverage map PLAN-12..PLAN-14, SAFE-15, PLAN-15 (week key vectors: 2026-12-31 and 2027-01-01 are `2026-W53`, 2027-01-04 is `2027-W01`).

## Deviations (safe behaviour chosen)
- The "steps first" path is taken for a LOSS goal only. For a gain goal "behind" means gaining too slowly and extra steps would work against the goal, so only the kcal path applies.
- The drift cap is checked before the bounds clamp and also applies to the `tooFast` correction.
- For `manual` ownership the auto-adjust toggles are ignored (the decision is only shown as an insight); for coached and shared, toggles off give `keep(autoAdjustOff)`.
- The stored classification of the previous review is passed as one value (`previousClass`), which is all the two-review rule needs.

## Affected contracts and paths
New files only. The transaction, cooldown re-check and undo record are applied by the C18 scheduler using `basePlanVersion` and the decision fields.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: coverage map T16 (and T82 later).

## Review state
Pending the test phase and specialist reviewers.
