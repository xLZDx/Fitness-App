import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/food_source.dart';
import 'food_format.dart';

/// Where a food's numbers came from. Text plus icon, never colour alone; an
/// estimate is labelled as one (design s17.9).
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final FoodSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = sourceLabel(l10n, source);
    return Semantics(
      label: l10n.foodSourceBadgeLabel(name),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            source.isEstimate ? Icons.auto_awesome : Icons.verified_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
