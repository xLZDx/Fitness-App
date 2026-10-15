/// `/nutrition/sources`: where the numbers come from, what they cannot do, and
/// the attribution list (design s17.9). Estimates are labelled estimates; no
/// medical claims.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/hud_tokens.dart';
import '../../shared/widgets/glass.dart';

class PlanSourcesPage extends StatelessWidget {
  const PlanSourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    Widget section(String title, List<String> lines) => GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nutritionSourcesTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(HudTokens.screenGutter),
          children: [
            Text(l10n.nutritionSourcesIntro,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: hud.textSecondary)),
            const SizedBox(height: 12),
            section(l10n.nutritionSourcesFormulasTitle, [
              l10n.nutritionSourcesMifflin,
              l10n.nutritionSourcesProtein,
              l10n.nutritionSourcesEnergyPerKg,
            ]),
            const SizedBox(height: 12),
            section(l10n.nutritionSourcesFoodTitle, [
              l10n.nutritionSourcesUsda,
              l10n.nutritionSourcesOff,
            ]),
            const SizedBox(height: 12),
            section(l10n.nutritionSourcesSoftwareTitle, [
              l10n.nutritionSourcesScanner,
              l10n.nutritionSourcesCalorieTracker,
              l10n.nutritionSourcesReferenceOnly,
              l10n.nutritionSourcesFullList,
            ]),
            const SizedBox(height: 12),
            section(l10n.nutritionSourcesLimitsTitle, [
              l10n.nutritionSourcesLimitEstimates,
              l10n.nutritionSourcesLimitScan,
              l10n.nutritionSourcesLimitNotMedical,
            ]),
          ],
        ),
      ),
    );
  }
}
