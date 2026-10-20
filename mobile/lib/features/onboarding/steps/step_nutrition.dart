import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';
import '../widgets/nutrition_inputs.dart';

/// Food and activity inputs for the nutrition coach (design s16.2, D-75).
///
/// ## Order and the lock-out
///
/// This step sits AFTER the health-flags step, whose two safety questions
/// (pregnancy / breastfeeding and the nutrition question) it reads. A goal,
/// pace line or any target text appears ONLY when both were answered `none`
/// ([nutritionSafetyClear]). When either is `reported` or unanswered the step
/// shows one neutral line instead, with no reason and no number, and keeps only
/// the inputs that are not targets: allergens, foods the user does not eat and
/// meals per day. Showing the pace first and asking afterwards is the v1 flaw
/// D-75 removed.
///
/// ## Nothing is asked twice
///
/// The target WEIGHT, birth year, gender, height, current weight and activity
/// level all come from `step_personal`; the diet pattern and sleep from
/// `step_lifestyle`. This step shows the target weight as a read-only line with
/// a link back ([onEditTarget]).
///
/// Every field is optional, and "Skip" / "Next" on the page's button follows
/// `isOnboardingStepAnswered`.
class StepNutrition extends ConsumerWidget {
  const StepNutrition({super.key, this.onEditTarget});

  /// Jumps to the personal screen, which owns the target weight.
  final VoidCallback? onEditTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flags = ref.watch(questionnaireDraftProvider).health.flags;
    final clear = nutritionSafetyClear(flags);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: l10n.onbNutritionTitle,
          subtitle: l10n.onbNutritionSubtitle,
        ),
        if (!clear)
          const NutritionLockedNotice()
        else ...[
          const NutritionGoalField(),
          NutritionPaceMessage(onEditTarget: onEditTarget),
          const NutritionTargetBodyFatField(),
          const NutritionSexAtBirthField(),
          const NutritionStepsField(),
        ],
        const NutritionAllergensField(),
        const NutritionExcludedFoodsField(),
        const NutritionMealsField(),
        if (clear) const NutritionOwnershipField(),
        const SizedBox(height: 16),
      ],
    );
  }
}
