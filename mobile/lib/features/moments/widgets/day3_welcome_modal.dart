import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';

/// Day-3 nurture modal. Shown once on the user's third launch, at least
/// 48 hours after account creation, before any premium features become
/// visible. Soft-asks for a recurring donation.
class Day3WelcomeModal extends StatelessWidget {
  const Day3WelcomeModal({super.key});

  static Future<void> show(BuildContext context) async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SafeArea(
          top: false,
          child: Day3WelcomeModal(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      floating: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraPeach,
                AppPalette.auroraPink,
              ]),
            ),
            child: const Icon(Icons.favorite_outline,
                color: AppSemanticColors.onGradientInk, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context).momentsThreeDaysInWelcome,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).momentsWeReANonprofitAndThe,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.75),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(AppLocalizations.of(context).momentsMaybeLater),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    GoRouter.of(context).push('/subscription');
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                      AppLocalizations.of(context).momentsSeeWaysToSupport),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.of(context).push('/about');
              },
              child: Text(AppLocalizations.of(context).momentsReadOurMission),
            ),
          ),
        ],
      ),
    );
  }
}
