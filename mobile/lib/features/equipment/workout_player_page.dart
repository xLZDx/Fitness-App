import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/scroll_dim_list.dart';
import '../workouts/data/workout_log.dart';
import '../workouts/state/workout_log_providers.dart';
import 'data/equipment_models.dart';
import 'state/equipment_providers.dart';

/// Looks up an exercise from the (preloaded) equipment catalog. Internal
/// helper so we don't need a separate FutureProvider just for this page.
final _exerciseByIdProvider =
    FutureProvider.family<ExerciseItem?, String>((ref, id) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  // Iterate every equipment + bodyweight pool — we only have a few hundred.
  final all = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in await repo.listEquipment()) ...await repo.exercisesFor(eq.id),
  ];
  for (final e in all) {
    if (e.id == id) return e;
  }
  return null;
});

class WorkoutPlayerPage extends ConsumerWidget {
  const WorkoutPlayerPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercise = ref.watch(_exerciseByIdProvider(exerciseId));

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Workout'),
      body: exercise.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (item) {
          if (item == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
              child: GlassCard(
                child: Text(
                  "We couldn't find that exercise.",
                  style: theme.textTheme.titleMedium,
                ),
              ),
            );
          }
          return ScrollDimList(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              _Hero(exercise: item),
              const SizedBox(height: 16),
              if (item.videoUrl != null)
                _VideoBlock(url: item.videoUrl!)
              else
                _NoVideoFallback(),
              const SizedBox(height: 16),
              _StepsCard(exercise: item),
              if (item.contraindications.isNotEmpty) ...[
                const SizedBox(height: 16),
                _CautionCard(item: item),
              ],
              const SizedBox(height: 20),
              _MarkCompleteButton(exercise: item),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: AppPalette.tileGradients[
                    exercise.id.hashCode.abs() % AppPalette.tileGradients.length],
              ),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(text: '${exercise.durationMinutes} min'),
                    _Pill(text: exercise.difficulty.name),
                    for (final m in exercise.muscles.take(3))
                      _Pill(text: m.replaceAll('_', ' ')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VideoBlock extends StatefulWidget {
  const _VideoBlock({required this.url});
  final String url;

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.play();
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() => _error = e);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return GlassCard(
        child: Text('Video unavailable: $_error'),
      );
    }
    if (!_ready) {
      return const GlassCard(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: _ctrl.value.aspectRatio == 0
            ? 16 / 9
            : _ctrl.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(_ctrl),
            // Tap-to-toggle play/pause.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _ctrl.value.isPlaying
                  ? _ctrl.pause()
                  : _ctrl.play()),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _ctrl.value.isPlaying
                    ? const SizedBox.shrink()
                    : Container(
                        color: Colors.black.withValues(alpha: 0.30),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 80),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoVideoFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraLime,
              ]),
            ),
            child: const Icon(Icons.menu_book_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No video yet — follow the steps below.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.exercise});
  final ExerciseItem exercise;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to do it',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(exercise.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              )),
          const SizedBox(height: 10),
          for (var i = 0; i < exercise.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(colors: [
                        AppPalette.auroraViolet,
                        AppPalette.auroraBlue,
                      ]),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(exercise.steps[i],
                        style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkCompleteButton extends ConsumerWidget {
  const _MarkCompleteButton({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(logWorkoutActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      final entry = WorkoutLogEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        completedAt: DateTime.now(),
        durationMinutes: exercise.durationMinutes,
      );
      await ref.read(logWorkoutActionProvider.notifier).log(entry);
      if (!context.mounted) return;
      final newState = ref.read(logWorkoutActionProvider);
      newState.when(
        data: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged "${exercise.title}" — nice work.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          GoRouter.of(context).go('/home');
        },
        error: (e, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        loading: () {},
      );
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [
            AppPalette.auroraTeal,
            AppPalette.auroraBlue,
          ]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.check_rounded, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              loading ? 'Saving…' : 'Mark complete',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CautionCard extends StatelessWidget {
  const _CautionCard({required this.item});
  final ExerciseItem item;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraPeach,
                AppPalette.auroraPink,
              ]),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Take care if you have…',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  item.contraindications
                      .map((c) => c.replaceAll('_', ' '))
                      .join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
