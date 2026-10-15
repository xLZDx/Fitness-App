/// Coached / Shared / Manual selector (design s18). Radio rows with one-line
/// explanations; changing it never rewrites the current range.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../profile/data/profile_models.dart';

String ownershipTitle(AppLocalizations l10n, PlanOwnership o) => switch (o) {
      PlanOwnership.coached => l10n.nutritionOwnershipCoached,
      PlanOwnership.shared => l10n.nutritionOwnershipShared,
      PlanOwnership.manual => l10n.nutritionOwnershipManual,
    };

String ownershipBody(AppLocalizations l10n, PlanOwnership o) => switch (o) {
      PlanOwnership.coached => l10n.nutritionOwnershipCoachedBody,
      PlanOwnership.shared => l10n.nutritionOwnershipSharedBody,
      PlanOwnership.manual => l10n.nutritionOwnershipManualBody,
    };

class OwnershipSelector extends StatelessWidget {
  const OwnershipSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final PlanOwnership value;
  final ValueChanged<PlanOwnership> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.nutritionOwnershipTitle,
                style: theme.textTheme.titleMedium),
          ),
          for (final o in PlanOwnership.values)
            // ignore: deprecated_member_use
            RadioListTile<PlanOwnership>(
              key: Key('nutrition.ownership.${o.name}'),
              value: o,
              // ignore: deprecated_member_use
              groupValue: value,
              // ignore: deprecated_member_use
              onChanged: enabled
                  ? (v) {
                      if (v != null && v != value) onChanged(v);
                    }
                  : null,
              contentPadding: EdgeInsets.zero,
              title: Text(ownershipTitle(l10n, o)),
              subtitle: Text(ownershipBody(l10n, o)),
            ),
          Text(l10n.nutritionOwnershipNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: hud.textSecondary)),
        ],
      ),
    );
  }
}
