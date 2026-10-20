/// Separate cloud-upload consent (D-5). Shown ONLY when the active provider
/// needs photos; the provisional provider never triggers it. Framework modal
/// route: outside semantics blocked, initial focus on the heading, focus
/// returns to the trigger on close (D-85). Resolves to true only on an explicit
/// agree; a dismissal is a refusal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';

class CloudConsentSheet extends StatelessWidget {
  const CloudConsentSheet({super.key});

  /// Returns true when the user agreed. The caller must not show the sheet
  /// when the provider does not need photos.
  static Future<bool> show(BuildContext context) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CloudConsentSheet(),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HudTokens.screenGutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            autofocus: true,
            child: Semantics(
              header: true,
              focusable: true,
              child: Text(l10n.bodyScanCloudTitle,
                  key: const Key('bodyScan.cloud.title'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: hud.textPrimary)),
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.bodyScanCloudBody,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bodyScan.cloud.agree'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.bodyScanCloudAgree),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('bodyScan.cloud.decline'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.bodyScanCloudDecline),
          ),
        ],
      ),
    );
  }
}
