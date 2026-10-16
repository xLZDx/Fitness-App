/// Choice sheet of the sync-conflict UI (S02 design 3.2, 6.2; story S02-12).
/// Shows summary fields only (no coordinates, heart rate or place text). The
/// only actions are the resolution choices: there is deliberately no delete
/// action. The sheet watches the presenter, so a second conflict updates it in
/// place and never stacks a second sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_tokens.dart';
import '../data/summary_projection.dart' show CandidateChoice;
import '../repository/sync_models.dart';
import '../state/sync_conflict_presenter.dart';

String formatSyncValue(Object? v) {
  if (v == null) return '-';
  if (v is num) {
    final d = v.toDouble();
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
  return v.toString();
}

String syncFieldLabel(AppLocalizations l10n, String field) => switch (field) {
      'movingTimeS' => l10n.activitySyncFieldMovingTimeS,
      'distanceM' => l10n.activitySyncFieldDistanceM,
      'ascentM' => l10n.activitySyncFieldAscentM,
      'descentM' => l10n.activitySyncFieldDescentM,
      'avgSpeedMps' => l10n.activitySyncFieldAvgSpeedMps,
      'avgCadence' => l10n.activitySyncFieldAvgCadence,
      'avgPowerW' => l10n.activitySyncFieldAvgPowerW,
      'normalizedPowerW' => l10n.activitySyncFieldNormalizedPowerW,
      'activeEnergyKcal' => l10n.activitySyncFieldActiveEnergyKcal,
      'steps' => l10n.activitySyncFieldSteps,
      'strokeCount' => l10n.activitySyncFieldStrokeCount,
      'poolLengthM' => l10n.activitySyncFieldPoolLengthM,
      'lapCount' => l10n.activitySyncFieldLapCount,
      'avgSwolf' => l10n.activitySyncFieldAvgSwolf,
      'routeTrimMeters' => l10n.activitySyncFieldRouteTrimMeters,
      _ => l10n.activitySyncFieldOther(field),
    };

class SyncConflictSheet extends ConsumerWidget {
  const SyncConflictSheet({super.key});

  static bool _open = false;

  /// Opens the sheet unless one is already open (the open one updates itself).
  static Future<void> show(BuildContext context) async {
    if (_open) return;
    _open = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const SyncConflictSheet(),
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final view = ref.watch(syncConflictPresenterProvider);
    final presenter = ref.read(syncConflictPresenterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HudTokens.screenGutter, 16, HudTokens.screenGutter, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.activitySyncSheetTitle,
                  key: const Key('activitySync.title'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: hud.textPrimary)),
            ),
            const SizedBox(height: 8),
            Text(l10n.activitySyncSheetIntro,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: hud.textSecondary)),
            if (view.lastFailed) ...[
              const SizedBox(height: 8),
              Text(l10n.activitySyncSaveFailed,
                  key: const Key('activitySync.failed'),
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: hud.danger)),
            ],
            const SizedBox(height: 12),
            if (!view.hasItems)
              Text(l10n.activitySyncEmpty,
                  key: const Key('activitySync.empty'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textPrimary)),
            for (final c in view.conflicts)
              _ConflictCard(
                conflict: c,
                busy: view.busy
                    .contains(SyncConflictPresenter.conflictKey(c.id)),
                onKeepDevice: () => presenter.keepDevice(c.id),
                onKeepCloud: () => presenter.keepCloud(c.id),
              ),
            for (final c in view.candidates)
              _CandidateCard(
                candidate: c,
                busy: view.busy
                    .contains(SyncConflictPresenter.candidateKey(c.id, c.field)),
                onChoice: (choice) =>
                    presenter.resolveCandidate(c.id, c.field, choice),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.busy,
    required this.onKeepDevice,
    required this.onKeepCloud,
  });

  final SyncConflict conflict;
  final bool busy;
  final VoidCallback onKeepDevice;
  final VoidCallback onKeepCloud;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return Card(
      key: Key('activitySync.conflict.${conflict.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.activitySyncConflictTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
            if (conflict.fields.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  conflict.cloudKnown
                      ? l10n.activitySyncConflictNoFields
                      : l10n.activitySyncCloudUnavailable,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textSecondary),
                ),
              ),
            for (final f in conflict.fields)
              Padding(
                key: Key('activitySync.field.${conflict.id}.${f.field}'),
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(syncFieldLabel(l10n, f.field),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: hud.textPrimary)),
                    Text(l10n.activitySyncDeviceValue(formatSyncValue(f.deviceValue)),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hud.textSecondary)),
                    Text(l10n.activitySyncCloudValue(formatSyncValue(f.cloudValue)),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hud.textSecondary)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: Key('activitySync.keepDevice.${conflict.id}'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy ? null : onKeepDevice,
              child: Text(l10n.activitySyncKeepDevice),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: Key('activitySync.keepCloud.${conflict.id}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy || !conflict.cloudKnown ? null : onKeepCloud,
              child: Text(l10n.activitySyncKeepCloud),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.busy,
    required this.onChoice,
  });

  final SyncCandidate candidate;
  final bool busy;
  final void Function(CandidateChoice) onChoice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final c = candidate;
    final recalc = c.reason == CandidateReason.recalculation;
    final id = '${c.id}.${c.field}';

    String label(CandidateChoice choice) => switch (choice) {
          CandidateChoice.useComputed => recalc
              ? l10n.activitySyncUseRecalculated
              : l10n.activitySyncUseComputed,
          CandidateChoice.keepMine => l10n.activitySyncKeepMine,
          CandidateChoice.useCloud => recalc
              ? l10n.activitySyncKeepCloudValue
              : l10n.activitySyncUseCloud,
        };

    // Stable order: computed, mine, cloud.
    final order = [
      CandidateChoice.useComputed,
      CandidateChoice.keepMine,
      CandidateChoice.useCloud,
    ].where(c.choices.contains);

    return Card(
      key: Key('activitySync.candidate.$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.activitySyncCandidateTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
            const SizedBox(height: 4),
            Text(syncFieldLabel(l10n, c.field),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: hud.textPrimary)),
            if (c.explicitValue != null)
              Text(l10n.activitySyncCandidateMine(formatSyncValue(c.explicitValue)),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textSecondary)),
            if (c.cloudValue != null)
              Text(l10n.activitySyncCandidateCloud(formatSyncValue(c.cloudValue)),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textSecondary)),
            Text(l10n.activitySyncCandidateComputed(formatSyncValue(c.computedValue)),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: hud.textSecondary)),
            const SizedBox(height: 12),
            for (final choice in order) ...[
              OutlinedButton(
                key: Key('activitySync.choice.${choice.name}.$id'),
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: busy ? null : () => onChoice(choice),
                child: Text(label(choice)),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
