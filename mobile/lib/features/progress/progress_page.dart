import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
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
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).progressTotalWorkouts,
                  value: '${stats.total}',
                  gradient: AppPalette.tileGradients[0],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).homeThisWeek,
                  value: '${stats.thisWeek}',
                  gradient: AppPalette.tileGradients[1],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).progressCurrentStreak,
                  value: '${stats.currentStreakDays}d',
                  gradient: AppPalette.tileGradients[2],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).progressLongest,
                  value: '${stats.longestStreakDays}d',
                  gradient: AppPalette.tileGradients[4],
                ),
              ),
            ],
          ),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.gradient,
  });

  final String label;
  final String value;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: gradient),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

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
