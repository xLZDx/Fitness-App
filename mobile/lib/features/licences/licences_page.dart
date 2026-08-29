import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/licences/asset_licences.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart' show FrostedScaffold, GlassAppBar;
import '../../shared/widgets/hud/hud_surface.dart';
import '../../core/theme/app_semantic_colors.dart';

/// Credits for the third-party content the app bundles.
///
/// Two surfaces, because they answer different questions. The cards name the
/// bundled ASSETS and their terms — that is the attribution the CC licences
/// require, and it has to be readable without hunting. The button underneath
/// opens Flutter's own licence page, which enumerates every Dart/Flutter
/// package's licence text and is generated, so it can never fall out of date.
class LicencesPage extends StatelessWidget {
  const LicencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l.settingsLicencesAndCredits),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          HudPanel(
            child: Text(l.licencesIntro, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          for (final a in kAssetAttributions) ...[
            _AttributionCard(attribution: a),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          AppSecondaryButton(
            key: const Key('licences-open-package-licences'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Fitness App',
              applicationLegalese: l.licencesLegalese,
            ),
            icon: Icons.list_alt_outlined,
            label: l.licencesOpenPackageLicences,
          ),
        ],
      ),
    );
  }
}

class _AttributionCard extends StatelessWidget {
  const _AttributionCard({required this.attribution});
  final AssetAttribution attribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colors.textSecondary;
    return HudPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            attribution.what,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(attribution.author, style: theme.textTheme.bodySmall),
          Text(
            attribution.licence,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          // Shown as text rather than a tappable link on purpose: the credit has
          // to be legible offline, and launching a browser is not part of the
          // obligation.
          SelectableText(
            attribution.url,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
          if (attribution.note != null) ...[
            const SizedBox(height: 6),
            Text(
              attribution.note!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
