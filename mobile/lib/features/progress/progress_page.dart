import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../progress_photos/data/photo_timeline.dart';
import '../progress_photos/data/progress_photo.dart';
import '../progress_photos/state/progress_photos_providers.dart';
import '../progress_photos/widgets/photo_bitmap.dart';
import '../workouts/data/workout_log.dart';
import '../workouts/data/workout_session.dart';
import '../workouts/state/workout_session_providers.dart';
import 'data/progress_charts.dart';
import 'data/progress_stats.dart';

class ProgressPage extends ConsumerWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // F3.3 read-convergence: sourced from workout_sessions (via the
    // WorkoutLogEntry adapter view), not the legacy workout_logs stream.
    final logs = ref.watch(workoutSessionHistoryProvider);
    // `logs` is the recent window, not the history. The all-time count and the
    // streak record come from `workoutSessionTotalsProvider`; without it a
    // long-time user would watch their totals shrink to the window size.
    final stats = deriveProgress(
      logs,
      totals: ref.watch(workoutSessionTotalsProvider).valueOrNull,
    );

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).progressProgress),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 120),
        children: [
          // R11g: the design's three-across row of accent numbers
          // (`App.tsx:3957`), not the app's previous 2x2 grid of gradient
          // tiles. `thisWeek` and `longestStreakDays` have no slot in that
          // row and are kept as the line underneath rather than dropped —
          // a redesign is not a reason to stop showing real history.
          const _HeadlineStats(),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).progressLast8Weeks,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: SizedBox(
              height: 160,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context)
                            .progressLogAWorkoutToSeeYour,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    )
                  : _BarChart(values: stats.last8Weeks),
            ),
          ),
          const SizedBox(height: 24),
          const _VolumeSection(),
          const SizedBox(height: 24),
          const _ConsistencySection(),
          const SizedBox(height: 24),
          // R11g's real gap: the design gives Progress a photo block
          // (`App.tsx:3980-4010`) and the app had one working, encrypted
          // photo feature at `/photos` that nothing on this screen linked to.
          const _PhotoProgressSection(),
          const SizedBox(height: 24),
          const _RecordsSection(),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).progressRecentActivity,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            GlassCard(
              child: Text(
                AppLocalizations.of(context)
                    .progressTapMarkCompleteOnAnyWorkout,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            )
          else
            for (final log in logs.take(5)) ...[
              _RecentLogCard(log: log),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// Everything below reads whole sessions rather than the `WorkoutLogEntry`
/// window the page opens with: volume and records live in the SETS, and the
/// log-entry view carries one exercise with no set collection.
List<WorkoutSession> _sessionsOf(WidgetRef ref) =>
    ref.watch(workoutSessionsProvider).valueOrNull ?? const [];

/// A section heading, in the page's existing style.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(text,
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colors.textSecondary)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// The design's three headline numbers, in accent type.
///
/// Records use the same 30-day window [_RecordsSection] does, so the tile and
/// the list under it cannot disagree about how many there are.
class _HeadlineStats extends ConsumerWidget {
  const _HeadlineStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stats = deriveProgress(
      ref.watch(workoutSessionHistoryProvider),
      totals: ref.watch(workoutSessionTotalsProvider).valueOrNull,
    );
    final records = recentRecords(
      _sessionsOf(ref),
      DateTime.now().subtract(_RecordsSection._window),
    ).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _HeadlineStat(
                value: '${stats.total}',
                label: l10n.progressStatWorkouts,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeadlineStat(
                value: '${stats.currentStreakDays}',
                label: l10n.progressStatDays,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeadlineStat(
                value: '$records',
                label: l10n.progressStatRecords,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.progressWeekAndLongest(stats.thisWeek, stats.longestStreakDays),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colors.textSecondary),
        ),
      ],
    );
  }
}

class _HeadlineStat extends StatelessWidget {
  const _HeadlineStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colors.accentPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Before/after photos on the Progress screen, per `App.tsx:3980-4010`.
///
/// The photo feature itself is not new — `/photos` has an encrypted local
/// store, a month timeline and a compare picker. What was missing is the only
/// thing the design puts on THIS screen: a way in. Without it the feature was
/// reachable from one place, and the screen the design says should advertise
/// it said nothing.
class _PhotoProgressSection extends ConsumerWidget {
  const _PhotoProgressSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pair = ref.watch(defaultComparePairProvider);
    final photos =
        ref.watch(progressPhotosProvider).valueOrNull ?? const <ProgressPhoto>[];

    return Column(
      key: const Key('progress.photos'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          l10n.progressPhotoSection,
          trailing: photos.isEmpty
              ? null
              : TextButton(
                  onPressed: () => GoRouter.of(context).push('/photos'),
                  child: Text('${l10n.progressPhotoAll} →'),
                ),
        ),
        const SizedBox(height: 8),
        // Three states, not two: no photos at all, photos but nothing
        // comparable (one shot, or two at different angles — see
        // `defaultComparePair`), and a real pair.
        if (pair == null)
          _PhotoEmptyCta(
            hasPhotos: photos.isNotEmpty,
          )
        else
          _PhotoComparePreview(pair: pair),
      ],
    );
  }
}

class _PhotoEmptyCta extends StatelessWidget {
  const _PhotoEmptyCta({required this.hasPhotos});

  /// Photos exist but no two of them share an angle — the invitation is to
  /// take a matching one, not a first one.
  final bool hasPhotos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return InkWell(
      key: const Key('progress.photosEmpty'),
      borderRadius: BorderRadius.circular(18),
      onTap: () => GoRouter.of(context).push('/photos'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colors.outline,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 26, color: theme.colors.textSecondary),
            const SizedBox(height: 8),
            Text(
              hasPhotos
                  ? l10n.progressPhotoSection
                  : l10n.progressPhotoAddFirst,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.progressPhotoCompareOverTime,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoComparePreview extends StatelessWidget {
  const _PhotoComparePreview({required this.pair});
  final ComparePair pair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = l10n.localeName;
    final fmt = DateFormat.MMMd(locale);

    final before = pair.before.weightKg;
    final after = pair.after.weightKg;
    // Only when BOTH shots carry a weight: a delta against a missing number
    // is not a smaller delta, it is no delta at all.
    final delta = (before != null && after != null) ? after - before : null;

    return GlassCard(
      key: const Key('progress.photoCompare'),
      borderRadius: 18,
      padding: EdgeInsets.zero,
      onTap: () => GoRouter.of(context).push('/photos'),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 140,
              child: Row(
                children: [
                  Expanded(child: _PhotoThumb(photo: pair.before)),
                  const SizedBox(width: 1),
                  Expanded(child: _PhotoThumb(photo: pair.after)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.progressPhotoRange(
                          fmt.format(pair.before.takenAt),
                          fmt.format(pair.after.takenAt),
                        ),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colors.textSecondary),
                      ),
                      if (delta != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          l10n.progressPhotoWeightDelta(_signed(delta)),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            // Neither direction is praised: a gain is the goal
                            // for someone bulking and the opposite for someone
                            // cutting, and this screen does not know which.
                            color: theme.colors.textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: theme.colors.accentPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n.progressPhotoCompare,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colors.onAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `+1.4` / `-2.0`. Same rule as the volume trend badge.
  static String _signed(double kg) {
    final rounded = (kg * 10).round() / 10;
    return rounded > 0 ? '+$rounded' : '$rounded';
  }
}

/// One decrypted photo, or an honest placeholder.
///
/// The bytes can genuinely be missing: while the disk store is resolving the
/// repository is the mock, and `MockProgressPhotosRepository.bytesOf` throws
/// by design rather than returning an empty image that would render as a
/// broken tile with no explanation.
class _PhotoThumb extends ConsumerWidget {
  const _PhotoThumb({required this.photo});
  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(photoBytesProvider(photo)).when(
          data: (bytes) => PhotoBitmap(bytes: bytes),
          loading: () => ColoredBox(color: theme.colors.surfaceInteractive),
          error: (_, __) => ColoredBox(
            color: theme.colors.surfaceInteractive,
            child: Center(
              child: Text(
                AppLocalizations.of(context).progressPhotoNoPixels,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colors.textSecondary),
              ),
            ),
          ),
        );
  }
}

class _VolumeSection extends ConsumerWidget {
  const _VolumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final weeks = volumeByWeek(_sessionsOf(ref), now);
    final trend = volumeTrend(_sessionsOf(ref), now);
    final moved = weeks.any((w) => w.volumeKg > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          l10n.progressVolume,
          // No badge when there is no earlier volume to compare against: a
          // percentage against zero is either infinity or a lie.
          trailing: trend == null
              ? null
              : Text(
                  l10n.progressVsPreviousMonth(_signed(trend)),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: trend >= 0
                        ? AppPalette.auroraLime
                        : theme.colorScheme.error,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: SizedBox(
            height: 140,
            child: moved
                ? _BarChart(
                    values: [for (final w in weeks) w.volumeKg.round()],
                  )
                : Center(
                    child: Text(
                      l10n.progressVolumeNeedsWeights,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colors.textSecondary),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// `+18` / `-4`. The sign is the information; a bare "18%" after a bad month
  /// reads as praise.
  static String _signed(double fraction) {
    final pct = (fraction * 100).round();
    return pct > 0 ? '+$pct' : '$pct';
  }
}

class _ConsistencySection extends ConsumerWidget {
  const _ConsistencySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final days = monthActivity(_sessionsOf(ref), now);
    final month = DateFormat.MMMM(Localizations.localeOf(context).toString())
        .format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('${l10n.progressConsistency} — $month'),
        const SizedBox(height: 8),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: SizedBox(
            height: 60,
            child: _BarChart(values: days, showLabels: false),
          ),
        ),
      ],
    );
  }
}

class _RecordsSection extends ConsumerWidget {
  const _RecordsSection();

  /// The design's tile reads "3 рекорда" with no period. A month is the period
  /// the rest of this screen already works in, and a lifetime count would
  /// simply be the number of exercises ever done with a weight.
  static const _window = Duration(days: 30);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final records =
        recentRecords(_sessionsOf(ref), DateTime.now().subtract(_window));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.progressRecords),
        const SizedBox(height: 8),
        if (records.isEmpty)
          GlassCard(
            child: Text(
              l10n.progressNoRecordsYet,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          )
        else
          for (final r in records.take(5)) ...[
            GlassCard(
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      color: AppPalette.auroraLime),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r.exerciseTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          l10n.progressRecordLine(
                              _trim(r.weightKg), r.reps),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// `82.5` stays, `80.0` becomes `80`. Trailing zeros on a weight read as
  /// precision that was never measured.
  static String _trim(double kg) =>
      kg == kg.roundToDouble() ? kg.round().toString() : kg.toString();
}

// `_StatCard` (a gradient-bar tile, 2x2) lived here until R11g. The design's
// Progress screen has one row of three accent numbers instead — see
// `_HeadlineStats`. Deleted rather than kept unused: an orphaned widget is a
// second design nobody chose.

class _BarChart extends StatelessWidget {
  const _BarChart({required this.values, this.showLabels = true});
  final List<int> values;

  /// Whether each bar carries its number underneath.
  ///
  /// Off for the month chart: 31 numbers across a phone's width are unreadable
  /// at any font size, and the shape of the month is the whole point of that
  /// chart. It also keeps 31 zeros off the widget tree, which
  /// `progress_page_test.dart` counts when it asserts the four stat tiles read
  /// "0" — that assertion is about the tiles, and thirty-three matches meant
  /// the test had stopped being about anything.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = values.fold<int>(0, (a, b) => a > b ? a : b);
    final safeMax = maxValue == 0 ? 1 : maxValue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final h = (values[i] / safeMax) * constraints.maxHeight;
                        // `clamp(2, maxHeight)` throws (min > max) the
                        // moment a squeezed layout gives maxHeight < 2 --
                        // every current call site fixes a height >= 60, so
                        // this was latent, not reachable, but `clamp`
                        // asserts on its argument order regardless of
                        // whether the bug ever gets exercised.
                        final minH =
                            constraints.maxHeight < 2 ? constraints.maxHeight : 2.0;
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            height: h.clamp(minH, constraints.maxHeight),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: AppPalette.tileGradients[
                                    i % AppPalette.tileGradients.length],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (showLabels) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${values[i]}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentLogCard extends StatelessWidget {
  const _RecentLogCard({required this.log});
  final WorkoutLogEntry log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: AppPalette.tileGradients[log.exerciseId.hashCode.abs() %
                    AppPalette.tileGradients.length],
              ),
            ),
            child: const Icon(Icons.check_rounded,
                color: AppSemanticColors.onGradientInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.exerciseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).notificationsMin(
                      _formatDate(l10n, log.completedAt), log.durationMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(AppLocalizations l10n, DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final wDay = DateTime(when.year, when.month, when.day);
    final diff = today.difference(wDay).inDays;
    if (diff == 0) return l10n.commonToday;
    if (diff == 1) return l10n.commonYesterday;
    if (diff < 7) return l10n.commonDaysAgo(diff);
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}
