import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/scroll_dim_list.dart';

class _Workout {
  const _Workout(this.title, this.duration, this.subtitle, this.gradient);
  final String title;
  final String duration;
  final String subtitle;
  final List<Color> gradient;
}

class WorkoutsPage extends StatefulWidget {
  const WorkoutsPage({super.key});

  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  static const _filters = ['For you', 'Strength', 'Cardio', 'Mobility', 'Yoga'];

  static const _byFilter = <List<_Workout>>[
    [
      _Workout('Push day', '40 min', 'Bench · Row · Press · Pulls',
          [AppPalette.auroraPeach, AppPalette.auroraPink]),
      _Workout('Hill repeats', '32 min', '6 × 400m intervals',
          [AppPalette.auroraViolet, AppPalette.auroraBlue]),
      _Workout('Mobility flow', '20 min', 'Hip + ankle mobility',
          [AppPalette.auroraTeal, AppPalette.auroraLime]),
      _Workout('Sun salutations', '18 min', 'Beginner-friendly vinyasa',
          [AppPalette.auroraPink, AppPalette.auroraPeach]),
      _Workout('Active recovery', '20 min', 'Easy pace + breathing',
          [AppPalette.auroraBlue, AppPalette.auroraTeal]),
    ],
    [
      _Workout('5×5 compound', '45 min', 'Squat · Bench · Deadlift',
          [AppPalette.auroraViolet, AppPalette.auroraPink]),
      _Workout('Upper push', '35 min', 'Bench · OHP · Triceps',
          [AppPalette.auroraPeach, AppPalette.auroraPink]),
      _Workout('Lower power', '40 min', 'Squats + plyo + RDL',
          [AppPalette.auroraTeal, AppPalette.auroraLime]),
      _Workout('Pull day', '38 min', 'Rows · Pull-ups · Curls',
          [AppPalette.auroraViolet, AppPalette.auroraBlue]),
    ],
    [
      _Workout('HIIT burn', '22 min', 'Treadmill + plyo',
          [AppPalette.auroraViolet, AppPalette.auroraBlue]),
      _Workout('Steady run', '40 min', 'Zone 2 endurance',
          [AppPalette.auroraBlue, AppPalette.auroraTeal]),
      _Workout('Bike intervals', '30 min', '5×3min hard / 2min easy',
          [AppPalette.auroraTeal, AppPalette.auroraLime]),
      _Workout('Row sprints', '20 min', '500m × 6',
          [AppPalette.auroraPink, AppPalette.auroraPeach]),
    ],
    [
      _Workout('Hip + ankle flow', '15 min', 'Foam roll + dynamic stretch',
          [AppPalette.auroraTeal, AppPalette.auroraLime]),
      _Workout('Spine mobility', '12 min', 'Cat-cow + thoracic rotations',
          [AppPalette.auroraBlue, AppPalette.auroraTeal]),
      _Workout('Full body release', '20 min', 'Foam roller routine',
          [AppPalette.auroraPink, AppPalette.auroraPeach]),
      _Workout('Shoulder reset', '10 min', 'Band work + scapular drills',
          [AppPalette.auroraViolet, AppPalette.auroraPink]),
    ],
    [
      _Workout('Sun salutations', '18 min', 'Beginner-friendly vinyasa',
          [AppPalette.auroraPink, AppPalette.auroraPeach]),
      _Workout('Vinyasa flow', '30 min', 'Intermediate sequence',
          [AppPalette.auroraViolet, AppPalette.auroraBlue]),
      _Workout('Yin yoga', '40 min', 'Long holds + breathing',
          [AppPalette.auroraTeal, AppPalette.auroraLime]),
      _Workout('Power yoga', '35 min', 'Strength-focused flow',
          [AppPalette.auroraPeach, AppPalette.auroraPink]),
    ],
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _byFilter[_selected];

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Train'),
      body: ScrollDimList(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = i == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: selected
                          ? LinearGradient(
                              colors: AppPalette.tileGradients[i % 5])
                          : null,
                      color: selected
                          ? null
                          : Colors.white.withValues(alpha: 0.32),
                    ),
                    child: Center(
                      child: Text(
                        _filters[i],
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          for (final w in list) ...[
            _WorkoutCard(w),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard(this.w);
  final _Workout w;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(colors: w.gradient),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 28),
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
                        w.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      w.duration,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  w.subtitle,
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
