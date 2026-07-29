import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/health/widgets/health_sync_card.dart';
import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/scroll_dim_list.dart';
import '../moments/data/moment.dart';
import '../moments/state/moment_providers.dart';
import '../moments/widgets/day3_welcome_modal.dart';
import '../progress/data/progress_stats.dart';
import '../recovery/widgets/deload_banner.dart';
import '../workouts/data/scheduled_session.dart';
import '../workouts/state/scheduled_session_providers.dart';
import '../workouts/state/workout_log_providers.dart';

class _Suggestion {
  const _Suggestion(this.title, this.duration, this.subtitle, this.gradient);
  final String title;
  final String duration;
  final String subtitle;
  final List<Color> gradient;
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  static const _suggestions = <_Suggestion>[
    _Suggestion('Upper body power', '35 min', 'Bench, row, overhead press',
        [AppPalette.auroraPeach, AppPalette.auroraPink]),
    _Suggestion('HIIT cardio burn', '22 min', 'Treadmill intervals + plyometrics',
        [AppPalette.auroraViolet, AppPalette.auroraBlue]),
    _Suggestion('Mobility & recovery', '15 min', 'Foam roll + stretching flow',
        [AppPalette.auroraPink, AppPalette.auroraPeach]),
    _Suggestion('Full body strength', '45 min', 'Squat, deadlift, press',
        [AppPalette.auroraTeal, AppPalette.auroraLime]),
    _Suggestion('Active recovery', '20 min', 'Easy pace + breathing',
        [AppPalette.auroraBlue, AppPalette.auroraTeal]),
  ];

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _maybeShowDay3Triggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_maybeShowDay3Triggered || !mounted) return;
      _maybeShowDay3Triggered = true;
      final repo = ref.read(momentRepositoryProvider);
      await repo.bumpLaunchCount();
      final shown = await repo.hasShown(MomentId.day3Welcome);
      final launches = await repo.launchCount();
      final firstLaunch = await repo.firstLaunchAt();
      final ok = shouldShowDay3Welcome(
        accountCreatedAt: firstLaunch ?? DateTime.now(),
        launchCount: launches,
        alreadyShown: shown,
      );
      if (!ok || !mounted) return;
      await Day3WelcomeModal.show(context);
      await repo.markShown(MomentId.day3Welcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(workoutLogsProvider).valueOrNull ?? const [];
    final stats = deriveProgress(logs);
    final upcoming = ref.watch(upcomingSessionsProvider);

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Home'),
      body: ScrollDimList(
        padding: const EdgeInsets.fromLTRB(20, 88, 20, 110),
        children: [
          _HeroCard(),
          const SizedBox(height: 16),
          const _AiPlanCard(),
          const SizedBox(height: 16),
          const HealthSyncCard(),
          const SizedBox(height: 12),
          const DeloadBanner(),
          _SectionHeader('Today'),
          const SizedBox(height: 12),
          _TodayCard(upcoming: upcoming),
          if (upcoming.length > 1) ...[
            const SizedBox(height: 24),
            _SectionHeader('Upcoming'),
            const SizedBox(height: 12),
            for (final s in upcoming.skip(1).take(3)) ...[
              _UpcomingCard(session: s),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 32),
          _SectionHeader('Quick stats'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Workouts',
                  value: '${stats.total}',
                  gradient: AppPalette.tileGradients[0],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Streak',
                  value: '${stats.currentStreakDays}d',
                  gradient: AppPalette.tileGradients[1],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'This week',
                  value: '${stats.thisWeek}',
                  gradient: AppPalette.tileGradients[2],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _SectionHeader('Suggestions'),
          const SizedBox(height: 14),
          for (final s in HomePage._suggestions) ...[
            _SuggestionCard(s),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
      ),
    );
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.icon, required this.gradient});
  final IconData icon;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(colors: gradient),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.upcoming});
  final List<ScheduledSession> upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (upcoming.isEmpty) {
      return GlassCard(
        child: Row(
          children: [
            _GradientTile(
              icon: Icons.event_outlined,
              gradient: const [
                AppPalette.auroraTeal,
                AppPalette.auroraLime,
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('No workouts scheduled',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Pick a plan or scan a machine to start.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.60),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final next = upcoming.first;
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/workout/${next.exerciseId}'),
      child: Row(
        children: [
          _GradientTile(
            icon: Icons.event_available_outlined,
            gradient: const [
              AppPalette.auroraViolet,
              AppPalette.auroraBlue,
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(next.exerciseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${formatScheduleLabel(next.scheduledFor)} · ${next.durationMinutes} min',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.55)),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.session});
  final ScheduledSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () =>
          GoRouter.of(context).push('/workout/${session.exerciseId}'),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: AppPalette.tileGradients[
                    session.exerciseId.hashCode.abs() %
                        AppPalette.tileGradients.length],
              ),
            ),
            child:
                const Icon(Icons.event_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.exerciseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${formatScheduleLabel(session.scheduledFor)} · ${session.durationMinutes} min',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a friendly schedule label: "Today 07:00", "Tomorrow 18:30",
/// "Wed 14:00", or "May 20 · 09:00" beyond the next week.
String formatScheduleLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final target = DateTime(t.year, t.month, t.day);
  final diff = target.difference(today).inDays;
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');

  if (diff == 0) return 'Today $hh:$mm';
  if (diff == 1) return 'Tomorrow $hh:$mm';
  if (diff > 1 && diff < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[t.weekday - 1]} $hh:$mm';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[t.month - 1]} ${t.day} · $hh:$mm';
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(this.s);
  final _Suggestion s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: s.gradient),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.duration,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppPalette.auroraTeal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'GOOD MORNING',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ready to train?',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Scan a machine or pick a plan curated for you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => GoRouter.of(context).go('/scan'),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraViolet,
                  AppPalette.auroraBlue,
                ]),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.auroraBlue.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'Scan equipment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: gradient),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// "Today's plan" CTA. Routes to the AI workout generator. The killer
/// feature was hidden behind a URL until this card existed.
class _AiPlanCard extends StatelessWidget {
  const _AiPlanCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/plan'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraBlue,
              ]),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's adaptive plan",
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Built from your intake, ratings, and recovery signals.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
        ],
      ),
    );
  }
}
