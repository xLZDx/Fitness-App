/// Entry card to the plan screen for Progress / Home (mounted by their owners,
/// not here). Shows the calorie range only for an eligible user with a plan;
/// for `referProfessional` (and every other non-eligible verdict) it shows no
/// number at all (D-55).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/nutrition_eligibility.dart';
import '../state/nutrition_providers.dart';

class NutritionEntryCard extends ConsumerWidget {
  const NutritionEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final verdict = ref.watch(nutritionEligibilityProvider);
    final plan = ref.watch(nutritionPlanProvider).valueOrNull;
    final nf = NumberFormat.decimalPattern(
        Localizations.localeOf(context).toString());
    final String body;
    if (verdict is Eligible && plan != null) {
      body = l10n.nutritionEntryRange(
          nf.format(plan.kcalRange.low), nf.format(plan.kcalRange.high));
    } else if (verdict is ReferProfessional) {
      body = l10n.nutritionEntryProfessional;
    } else {
      body = l10n.nutritionEntrySetUp;
    }
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/nutrition'),
      child: Semantics(
        button: true,
        container: true,
        label: '${l10n.nutritionPlanTitle}. $body',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.nutritionPlanTitle,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(body,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hud.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
