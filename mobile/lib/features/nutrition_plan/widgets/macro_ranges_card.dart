/// Protein / fat / carbohydrate RANGES and the steps goal of the plan screen
/// (design s13). Ranges, never exact targets; the steps goal has +/-500
/// steppers (a non-drag control, 48 dp targets).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/stored_nutrition_plan.dart';

const int kStepsGoalStep = 500;

class MacroRangesCard extends StatelessWidget {
  const MacroRangesCard({
    super.key,
    required this.plan,
    required this.onStepsChanged,
  });

  final StoredNutritionPlan plan;
  final ValueChanged<int> onStepsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final nf = NumberFormat.decimalPattern(
        Localizations.localeOf(context).toString());
    String grams(int a, int b) =>
        l10n.nutritionGramsRange(nf.format(a), nf.format(b));
    Widget row(String name, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(name, style: theme.textTheme.bodyLarge)),
              const SizedBox(width: 12),
              Text(value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: hud.textPrimary)),
            ],
          ),
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.nutritionMacrosTitle,
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          row(l10n.nutritionProteinLabel,
              grams(plan.protein.minG, plan.protein.maxG)),
          Text(l10n.nutritionProteinAim(nf.format(plan.protein.targetG)),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: hud.textSecondary)),
          row(l10n.nutritionFatLabel, grams(plan.fat.minG, plan.fat.maxG)),
          row(l10n.nutritionCarbsLabel,
              grams(plan.carbs.minG, plan.carbs.maxG)),
          const SizedBox(height: 4),
          Text(l10n.nutritionMacrosNote,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: hud.textSecondary)),
          const Divider(height: 24),
          Semantics(
            header: true,
            child: Text(l10n.nutritionStepsTitle,
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Semantics(
                button: true,
                label: l10n.nutritionStepsDecrease(kStepsGoalStep),
                excludeSemantics: true,
                child: IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.remove),
                  onPressed: () =>
                      onStepsChanged(plan.stepsGoal - kStepsGoalStep),
                ),
              ),
              Expanded(
                child: Text(
                  l10n.nutritionStepsValue(plan.stepsGoal),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: hud.textPrimary),
                ),
              ),
              Semantics(
                button: true,
                label: l10n.nutritionStepsIncrease(kStepsGoalStep),
                excludeSemantics: true,
                child: IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.add),
                  onPressed: () =>
                      onStepsChanged(plan.stepsGoal + kStepsGoalStep),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
