/// First screen of the body scan flow (design s10, D-73, D-74). With the
/// provisional estimator it says plainly that the figure is a rough estimate
/// from height, weight and age and not a photo measurement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';

class IntroView extends StatelessWidget {
  const IntroView({
    super.key,
    required this.provisional,
    required this.measurementOnly,
    required this.onStart,
    required this.onClose,
  });

  /// The active estimator is the provisional, photo-free one.
  final bool provisional;

  /// Eligibility says no goal figures (D-74): photos and history only.
  final bool measurementOnly;
  final VoidCallback onStart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return ListView(
      padding: const EdgeInsets.all(HudTokens.screenGutter),
      children: [
        Semantics(
          header: true,
          child: Text(l10n.bodyScanIntroTitle,
              key: const Key('bodyScan.intro.title'),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: hud.textPrimary)),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (provisional) ...[
                Row(
                  children: [
                    Icon(Icons.info_outline, color: context.colors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.bodyScanRoughLabel,
                          key: const Key('bodyScan.intro.roughLabel'),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: hud.textPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                provisional
                    ? l10n.bodyScanIntroBodyRough
                    : l10n.bodyScanIntroBodyPhotos,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: hud.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(l10n.bodyScanIntroTime,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textSecondary)),
              if (measurementOnly) ...[
                const SizedBox(height: 8),
                Text(l10n.bodyScanMeasurementOnlyNote,
                    key: const Key('bodyScan.intro.measurementOnly'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: hud.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('bodyScan.intro.start'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onStart,
          child: Text(l10n.bodyScanIntroStart),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('bodyScan.intro.close'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onClose,
          child: Text(l10n.bodyScanIntroClose),
        ),
      ],
    );
  }
}
