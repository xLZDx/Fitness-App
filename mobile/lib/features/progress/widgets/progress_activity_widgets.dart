/// The Progress activity widgets of S03-14 (contract S-7, 10.5, 11; design 3.4
/// to 3.6, F-15, F-40, F-41): the quiet Sources slot (S-7a), the journal error
/// panel and the "All activity" block (S-7b). They read only the journal
/// providers; no number mixes with the workout-history numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/activity_flags.dart';
import '../../../core/router/s03_routes.dart' show kSourcesPath;
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/wiring/activity_wiring.dart';
import '../../../shared/widgets/hud/hud_metric.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../activity/data/activity_aggregates.dart';
import '../../activity/repository/journal_models.dart' show JournalSyncState;
import '../../activity/state/activity_dashboard_providers.dart';
import '../../activity/state/journal_availability.dart';
import '../../modes/data/mode_models.dart' show AppMode;
import '../../modes/state/mode_providers.dart';
import 'progress_activity_format.dart';

/// What the Progress activity area shows.
enum ProgressActivityKind {
  /// Sources row only (loading, empty, not enabled).
  slotOnly,

  /// The "All activity" block (open and at least one session).
  block,

  /// Error panel with a Try again button.
  errorRetry,

  /// Error panel with the message only (`failedToOpen`, not retriable).
  errorNoRetry,
}

/// Which retry the error panel runs.
enum ProgressRetryTarget { bind, reload }

class ProgressActivityView {
  const ProgressActivityView(this.kind,
      {this.retry = ProgressRetryTarget.bind, this.notRestored = 0});

  final ProgressActivityKind kind;
  final ProgressRetryTarget retry;

  /// Count for the recovery notice (0 = none).
  final int notRestored;

  @override
  bool operator ==(Object other) =>
      other is ProgressActivityView &&
      other.kind == kind &&
      other.retry == retry &&
      other.notRestored == notRestored;

  @override
  int get hashCode => Object.hash(kind, retry, notRestored);
}

/// The state mapping of design 3.6 for Progress.
final progressActivityViewProvider = Provider<ProgressActivityView>((ref) {
  final avail = ref.watch(journalAvailabilityProvider);
  switch (avail) {
    case JournalNotEnabled():
    case JournalBinding():
      return const ProgressActivityView(ProgressActivityKind.slotOnly);
    case JournalFailedToOpen():
      return const ProgressActivityView(ProgressActivityKind.errorNoRetry);
    case JournalGaveUp():
      return const ProgressActivityView(ProgressActivityKind.errorRetry,
          retry: ProgressRetryTarget.bind);
    case JournalOpen():
      final snap = ref.watch(activityDigestSnapshotProvider);
      if (snap == null) {
        if (ref.watch(activityDigestsProvider).hasError) {
          return const ProgressActivityView(ProgressActivityKind.errorRetry,
              retry: ProgressRetryTarget.reload);
        }
        return const ProgressActivityView(ProgressActivityKind.slotOnly);
      }
      return ProgressActivityView(
        snap.digests.isEmpty
            ? ProgressActivityKind.slotOnly
            : ProgressActivityKind.block,
        notRestored: snap.notRestoredCount,
      );
  }
});

/// Opens Sources.
void _openSources(BuildContext context) =>
    GoRouter.of(context).push(kSourcesPath);

/// S-7a: the quiet slot. One navigation row, plus the recovery notice when
/// activities were lost (a true statement, never "nothing recorded").
class ProgressSourcesSlot extends ConsumerWidget {
  const ProgressSourcesSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lost = ref.watch(
        progressActivityViewProvider.select((v) => v.notRestored));
    return Column(
      key: const Key('progress.slot.sources'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SourcesRow(
          title: l10n.progressSourcesRow,
          subtitle: l10n.progressSourcesHint,
        ),
        if (lost > 0) ...[
          const SizedBox(height: 8),
          _Note(l10n.activityRecoveryNotice(lost)),
        ],
      ],
    );
  }
}

class _SourcesRow extends StatelessWidget {
  const _SourcesRow({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return HudPanel(
      secondary: true,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: HudSettingRow(
        icon: Icons.hub_outlined,
        title: title,
        subtitle: subtitle,
        divider: false,
        mergeSemantics: true,
        onTap: () => _openSources(context),
        showFocusRing: true,
        hoverStyle: true,
        cursor: true,
      ),
    );
  }
}

/// The Sources row of the "All activity" block, shown on its own when the
/// block sits in the left column of the two-pane layout.
class ProgressBlockSourcesRow extends StatelessWidget {
  const ProgressBlockSourcesRow({super.key});

  @override
  Widget build(BuildContext context) => _SourcesRow(
        key: const Key('progress.block.sources'),
        title: AppLocalizations.of(context).progressSourcesRow,
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colors.textSecondary,
      ),
    );
  }
}

/// C-12 error panel with Try again (no raw exception text).
class ProgressJournalErrorPanel extends ConsumerWidget {
  const ProgressJournalErrorPanel({super.key, required this.view});

  final ProgressActivityView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bindBusy =
        ref.watch(activityBindStatusProvider.select((s) => s.bindBusy));
    final reloading = view.retry == ProgressRetryTarget.reload &&
        ref.watch(activityDigestsProvider).isLoading;
    final busy = bindBusy || reloading;
    final retriable = view.kind == ProgressActivityKind.errorRetry;
    return HudPanel(
      key: const Key('progress.journalError'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.activityJournalFailed,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colors.textSecondary),
          ),
          if (retriable) ...[
            const SizedBox(height: 12),
            HudButton(
              key: const Key('progress.journalRetry'),
              label: l10n.activityJournalRetry,
              enabled: !busy,
              minHeight: 48,
              showFocusRing: true,
              hoverStyle: true,
              cursor: true,
              onPressed: busy
                  ? null
                  : () {
                      if (view.retry == ProgressRetryTarget.bind) {
                        ref
                            .read(activityBindStatusProvider.notifier)
                            .retryNow();
                      } else {
                        ref.read(activityDigestsProvider.notifier).refresh();
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}

/// Predicate for the "Estimate" marker of a tile field (`time`, `distance`).
/// No value is an estimate in S03; the marker is a component capability.
typedef ProgressEstimateField = bool Function(String field);

bool _neverEstimate(String field) => false;

/// S-7b "All activity" block. [showSourcesRow] false leaves the row to the
/// caller (two-pane layout puts it in the right column).
class ProgressActivityBlock extends ConsumerWidget {
  const ProgressActivityBlock({
    super.key,
    this.showSourcesRow = true,
    this.isEstimateField = _neverEstimate,
  });

  final bool showSourcesRow;
  final ProgressEstimateField isEstimateField;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final snap = ref.watch(activityDigestSnapshotProvider);
    final week = ref.watch(activityWeekTilesProvider);
    final recent = ref.watch(activityRecentProvider);
    final mode = ref.watch(selectedModeProvider);
    final tiles = orderTilesForMode(week.tiles, mode);
    final failedAt = snap?.lastLoadFailedAt;
    final lost = snap?.notRestoredCount ?? 0;
    final locale = l10n.localeName;
    final headingStyle =
        theme.textTheme.titleLarge?.copyWith(color: theme.colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.progressAllActivity,
              key: const Key('progress.allActivity'), style: headingStyle),
        ),
        if (failedAt != null) ...[
          const SizedBox(height: 8),
          _StaleLine(at: failedAt),
        ],
        if (lost > 0) ...[
          const SizedBox(height: 8),
          _Note(l10n.activityRecoveryNotice(lost)),
          const SizedBox(height: 2),
          _Note(l10n.activityMayBeIncomplete),
        ],
        const SizedBox(height: 12),
        Text(l10n.progressThisWeek,
            key: const Key('progress.thisWeek'),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colors.textSecondary)),
        const SizedBox(height: 8),
        if (tiles.isEmpty)
          HudPanel(
            child: Text(
              l10n.progressThisWeekEmpty,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          )
        else
          LayoutBuilder(builder: (context, c) {
            const gap = 12.0;
            final cols = progressTileColumns(c.maxWidth);
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles)
                  SizedBox(
                    width: w,
                    child: ProgressWeekTile(
                      tile: t,
                      isEstimateField: isEstimateField,
                    ),
                  ),
              ],
            );
          }),
        const SizedBox(height: 16),
        Text(l10n.progressRecent,
            key: const Key('progress.recent'), style: headingStyle),
        const SizedBox(height: 8),
        HudPanel(
          secondary: true,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++)
                _ActivityRow(
                  key: Key('progress.recent.row.${recent[i].id}'),
                  digest: recent[i],
                  locale: locale,
                  divider: i != recent.length - 1,
                ),
            ],
          ),
        ),
        if (showSourcesRow) ...[
          const SizedBox(height: 12),
          const ProgressBlockSourcesRow(),
        ],
      ],
    );
  }
}

/// "Showing data from <time>" with Try again (RV-11).
class _StaleLine extends ConsumerWidget {
  const _StaleLine({required this.at});
  final DateTime at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loading = ref.watch(activityDigestsProvider).isLoading;
    final time = DateFormat.Hm(l10n.localeName).format(at.toLocal());
    return Row(
      key: const Key('progress.stale'),
      children: [
        Expanded(
          child: Text(
            l10n.activityStaleNotice(time),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ),
        TextButton(
          key: const Key('progress.staleRetry'),
          onPressed: loading
              ? null
              : () => ref.read(activityDigestsProvider.notifier).refresh(),
          child: Text(l10n.activityJournalRetry),
        ),
      ],
    );
  }
}

String _groupName(AppLocalizations l10n, SportGroup g) => switch (g) {
      SportGroup.walkHike => l10n.sportGroupWalkHike,
      SportGroup.run => l10n.sportGroupRun,
      SportGroup.ride => l10n.sportGroupRide,
      SportGroup.swim => l10n.sportGroupSwim,
      SportGroup.row => l10n.sportGroupRow,
      SportGroup.other => l10n.sportGroupOther,
    };

IconData _groupIcon(SportGroup g) => switch (g) {
      SportGroup.walkHike => Icons.directions_walk,
      SportGroup.run => Icons.directions_run,
      SportGroup.ride => Icons.directions_bike,
      SportGroup.swim => Icons.pool,
      SportGroup.row => Icons.rowing,
      SportGroup.other => Icons.fitness_center,
    };

/// The label text of a source key (contract 8.1).
String progressSourceLabelText(AppLocalizations l10n, SourceLabelKey k) =>
    switch (k) {
      SourceLabelKey.app => l10n.sourceLabelApp,
      SourceLabelKey.healthConnect => l10n.sourceHealthConnect,
      SourceLabelKey.healthKit => l10n.sourceLabelHealthPlatform,
      SourceLabelKey.watch => l10n.sourceWatch,
      SourceLabelKey.sensor => l10n.sourceLabelSensor,
      SourceLabelKey.healthPlatform => l10n.sourceLabelHealthPlatform,
      SourceLabelKey.service => l10n.sourceLabelService,
      SourceLabelKey.companionApp => l10n.sourceLabelCompanionApp,
      SourceLabelKey.fileImport => l10n.sourceLabelFileImport,
      SourceLabelKey.unknown => l10n.sourceLabelUnknown,
    };

/// C-6 Discipline tile: sessions, time, distance of one group this week.
class ProgressWeekTile extends StatelessWidget {
  const ProgressWeekTile({
    super.key,
    required this.tile,
    this.isEstimateField = _neverEstimate,
  });

  final WeekTile tile;
  final ProgressEstimateField isEstimateField;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = l10n.localeName;
    final noData = l10n.activityNoData;
    final hintStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colors.textSecondary);

    String withEstimate(String field, String v) =>
        isEstimateField(field) ? '$v (${l10n.activityEstimate})' : v;

    final time = tile.hasTime
        ? withEstimate(
            'time', l10n.commonMinutes(progressMinutesOf(tile.timeSeconds)))
        : noData;
    final dist = tile.hasDistance
        ? withEstimate('distance',
            formatProgressDistance(tile.distanceM, locale, l10n.activityUnitKm))
        : noData;

    return MergeSemantics(
      child: HudPanel(
        key: Key('progress.tile.${progressGroupKeyName(tile.group)}'),
        secondary: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_groupIcon(tile.group),
                    size: 18, color: theme.colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _groupName(l10n, tile.group),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            HudMetricRow(
              label: l10n.activityTileSessions,
              value: formatProgressCount(tile.sessions, locale),
            ),
            HudMetricRow(
              label: l10n.activityTileTime,
              value: time,
              divider: !tile.timePartial,
            ),
            if (tile.timePartial)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l10n.activityTimeFrom(tile.timeContributing, tile.sessions),
                  style: hintStyle,
                ),
              ),
            HudMetricRow(
              label: l10n.activityTileDistance,
              value: dist,
              divider: false,
            ),
            if (tile.distancePartial)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l10n.activityDistanceFrom(
                      tile.distanceContributing, tile.sessions),
                  style: hintStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// C-4 Activity row (informational, no tap).
class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({
    super.key,
    required this.digest,
    required this.locale,
    required this.divider,
  });

  final SessionDigest digest;
  final String locale;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zone = ref.watch(activityZoneProvider);
    final cloud = ref.watch(activityFlagsProvider).cloudSync;
    final utc = digest.startUtc;
    final local = zone == null ? utc.toLocal() : zone(utc.toUtc());
    final date = DateFormat.MMMd(locale).add_Hm().format(local);
    final noData = l10n.activityNoData;
    final t = digest.movingTimeS;
    final m = digest.distanceM;
    final src = sourceLabelOf(digest);
    var source = progressSourceLabelText(l10n, src.key);
    if (src.moreSources > 0) {
      source = '$source ${l10n.activitySourcesMore(src.moreSources)}';
    }
    final notes = <String>[
      if (digest.streamLost) l10n.activityStreamLost,
      if (cloud)
        switch (digest.syncState) {
          JournalSyncState.pending => l10n.syncChipPending,
          JournalSyncState.uploadFailed => l10n.syncChipFailed,
          JournalSyncState.syncConflict => l10n.syncChipConflict,
          JournalSyncState.synced => '',
        },
    ].where((s) => s.isNotEmpty).toList();
    final metrics = '$date · '
        '${t == null ? noData : l10n.commonMinutes(progressMinutesOf(t))} · '
        '${m == null ? noData : formatProgressDistance(m, locale, l10n.activityUnitKm)}';
    final subtitle = [metrics, source, ...notes].join('\n');

    return MergeSemantics(
      child: HudSettingRow(
        icon: _groupIcon(digest.sportGroup),
        title: _groupName(l10n, digest.sportGroup),
        subtitle: subtitle,
        divider: divider,
        trailing: const SizedBox.shrink(),
      ),
    );
  }
}

/// The selected mode, for tests that want to assert the tile order seam.
AppMode? progressSelectedModeOf(WidgetRef ref) =>
    ref.read(selectedModeProvider);
