/// Entry point of the guided scan on the progress photos page.
///
/// Shows the right thing for each [ScanAccess] state: the start/compare actions
/// when allowed, otherwise a neutral explanation (under 18), a pointer to the
/// profile (age unknown), the existing Supporter paywall, or the existing photo
/// consent step. Nothing here asks for a new consent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/hud/hud_surface.dart';
import '../scan_access.dart';
import 'scan_reminder_editor.dart';
import 'scan_gate_view.dart';

class ScanEntryCard extends ConsumerWidget {
  const ScanEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(scanAccessProvider);
    if (access == ScanAccess.signedOut) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Widget? action;
    VoidCallback? onTap;
    switch (access) {
      case ScanAccess.allowed:
        action = _Actions(
          onStart: () => GoRouter.of(context).push('/body-scan'),
          onCompare: () => GoRouter.of(context).push('/photos/compare'),
        );
      case ScanAccess.needsConsent:
        action = FilledButton(
          key: const Key('scan.entry.consent'),
          onPressed: () async {
            if (await runScanConsent(context, ref) && context.mounted) {
              GoRouter.of(context).push('/body-scan');
            }
          },
          child: Text(l10n.scanEntryStart),
        );
      case ScanAccess.needsSupporter:
        onTap = () => GoRouter.of(context).push('/subscription');
      case ScanAccess.ageUnknown:
        action = OutlinedButton(
          key: const Key('scan.entry.profile'),
          onPressed: () => GoRouter.of(context).push('/profile'),
          child: Text(l10n.scanEntryAgeUnknownAction),
        );
      case ScanAccess.underage:
      case ScanAccess.signedOut:
        break;
    }

    final String body = switch (access) {
      ScanAccess.allowed || ScanAccess.needsConsent => l10n.scanEntryBody,
      _ => scanAccessMessage(l10n, access),
    };

    return HudPanel(
      key: Key('scan.entry.${access.name}'),
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.scanEntryTitle,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodySmall),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
          if (access == ScanAccess.allowed) const ScanReminderEditor(),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onStart, required this.onCompare});
  final VoidCallback onStart;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const Key('scan.entry.start'),
          onPressed: onStart,
          icon: const Icon(Icons.accessibility_new),
          label: Text(l10n.scanEntryStart),
        ),
        OutlinedButton(
          key: const Key('scan.entry.compare'),
          onPressed: onCompare,
          child: Text(l10n.scanEntryCompare),
        ),
      ],
    );
  }
}
