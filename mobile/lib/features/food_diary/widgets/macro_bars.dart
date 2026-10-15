import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/food_entry.dart';
import 'food_format.dart';

/// Protein / carbs / fat of a total as labelled rows: text values first, a
/// thin bar as decoration only (so the numbers are the information).
class MacroBars extends StatelessWidget {
  const MacroBars({super.key, required this.totals});

  final MacroTotals totals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = totals.proteinG.mid;
    final c = totals.carbsG.mid;
    final f = totals.fatG.mid;
    final max = [p, c, f, 1.0].reduce((a, b) => a > b ? a : b);
    Widget row(String name, double v) {
      final value = l10n.foodUnitGrams(fmtGrams(context, v));
      return Semantics(
        label: '$name, $value',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
              ),
              Expanded(
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: (v / max).clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        row(l10n.foodMacroProtein, p),
        row(l10n.foodMacroCarbs, c),
        row(l10n.foodMacroFat, f),
      ],
    );
  }
}
