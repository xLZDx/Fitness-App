import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../workouts/data/workout_log.dart';
import '../workouts/state/workout_session_providers.dart';
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
  const _BarChart({required this.values});
  final List<int> values;

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
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            height: h.clamp(2, constraints.maxHeight),
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
                  const SizedBox(height: 6),
                  Text(
                    '${values[i]}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
