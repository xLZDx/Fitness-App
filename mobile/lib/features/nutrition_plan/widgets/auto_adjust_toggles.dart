/// The two auto-adjust toggles (steps goal, calorie range). In Manual mode the
/// review ignores them, so they are shown off and disabled (design s18).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../profile/data/profile_models.dart';
import '../data/weekly_review.dart';

class AutoAdjustToggles extends StatelessWidget {
  const AutoAdjustToggles({
    super.key,
    required this.value,
    required this.ownership,
    required this.onChanged,
  });

  final AutoAdjust value;
  final PlanOwnership ownership;
  final ValueChanged<AutoAdjust> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final manual = ownership == PlanOwnership.manual;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.nutritionAutoTitle,
                style: theme.textTheme.titleMedium),
          ),
          SwitchListTile(
            key: const Key('nutrition.auto.steps'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.nutritionAutoSteps),
            value: !manual && value.steps,
            onChanged: manual
                ? null
                : (v) => onChanged(AutoAdjust(steps: v, kcal: value.kcal)),
          ),
          SwitchListTile(
            key: const Key('nutrition.auto.kcal'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.nutritionAutoKcal),
            value: !manual && value.kcal,
            onChanged: manual
                ? null
                : (v) => onChanged(AutoAdjust(steps: value.steps, kcal: v)),
          ),
          Text(
            manual
                ? l10n.nutritionAutoManualOff
                : ownership == PlanOwnership.shared
                    ? l10n.nutritionAutoSharedHint
                    : l10n.nutritionAutoCoachedHint,
            style:
                theme.textTheme.bodySmall?.copyWith(color: hud.textSecondary),
          ),
        ],
      ),
    );
  }
}
