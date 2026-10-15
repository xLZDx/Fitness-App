/// `/nutrition/how-it-adapts`: plain-language rules of the weekly review, the
/// ownership modes and the safety limits (design s15, s18). No promises about
/// dates or results.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/hud_tokens.dart';
import '../../shared/widgets/glass.dart';

class PlanExplainerPage extends StatelessWidget {
  const PlanExplainerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
      appBar: AppBar(title: Text(l10n.nutritionExplainerTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(HudTokens.screenGutter),
          children: [
            section(l10n.nutritionExplainerWeeklyTitle, [
              l10n.nutritionExplainerWeekly1,
              l10n.nutritionExplainerWeekly2,
              l10n.nutritionExplainerWeekly3,
            ]),
            const SizedBox(height: 12),
            section(l10n.nutritionExplainerModesTitle, [
              l10n.nutritionOwnershipCoachedBody,
              l10n.nutritionOwnershipSharedBody,
              l10n.nutritionOwnershipManualBody,
            ]),
            const SizedBox(height: 12),
            section(l10n.nutritionExplainerLimitsTitle, [
              l10n.nutritionExplainerLimits1,
              l10n.nutritionExplainerLimits2,
              l10n.nutritionExplainerLimits3,
            ]),
          ],
        ),
      ),
    );
  }
}
