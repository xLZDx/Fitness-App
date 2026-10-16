/// Entry point of the sync-conflict sheet (S02 design 3.2, 6.2; story S02-12).
/// A small card for the Progress page, shown only when the cloud path is on
/// (`ACTIVITY_CLOUD_STREAMS`) and the presenter reports entries that need a
/// decision. Flag off: nothing is built and the presenter is never read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/activity_flags.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../state/sync_conflict_presenter.dart';
import 'sync_conflict_sheet.dart';

class ActivitySyncEntryCard extends ConsumerWidget {
  const ActivitySyncEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(activityFlagsProvider).cloudSync) {
      return const SizedBox.shrink();
    }
    final hasItems = ref.watch(syncConflictPresenterProvider).hasItems;
    if (!hasItems) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HudPanel(
        key: const Key('activitySync.entryCard'),
        padding: const EdgeInsets.all(16),
        onTap: () => SyncConflictSheet.show(context),
        child: Semantics(
          button: true,
          child: Text(l10n.activitySyncSheetTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
