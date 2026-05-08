import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/scroll_dim_list.dart';
import '../equipment/data/equipment_models.dart';
import '../equipment/state/equipment_providers.dart';

/// One filter chip on the Train tab. The id drives which provider feeds the
/// list; the label is what the user sees.
enum WorkoutsFilter { forYou, strength, cardio, atHome, all }

extension on WorkoutsFilter {
  String get label {
    switch (this) {
      case WorkoutsFilter.forYou:
        return 'For you';
      case WorkoutsFilter.strength:
        return 'Strength';
      case WorkoutsFilter.cardio:
        return 'Cardio';
      case WorkoutsFilter.atHome:
        return 'At Home';
      case WorkoutsFilter.all:
        return 'All';
    }
  }
}

/// Resolves a filter into the actual list of exercises to show. Pulls from
/// the recommended ("for you") feed and the raw catalog and slices by
/// equipment category.
final _filteredExercisesProvider =
    FutureProvider.family<List<ExerciseItem>, WorkoutsFilter>((ref, filter) async {
  switch (filter) {
    case WorkoutsFilter.forYou:
      return ref.watch(forYouExercisesProvider.future);
    case WorkoutsFilter.atHome:
      final all = await ref.watch(allExercisesProvider.future);
      return all.where((e) => e.equipmentId == null).toList(growable: false);
    case WorkoutsFilter.strength:
    case WorkoutsFilter.cardio:
      final repo = ref.watch(equipmentRepositoryProvider);
      final equipment = await repo.listEquipment();
      final wanted = filter == WorkoutsFilter.strength ? 'strength' : 'cardio';
      final out = <ExerciseItem>[];
      for (final eq in equipment.where((e) => e.category == wanted)) {
        out.addAll(await repo.exercisesFor(eq.id));
      }
      return List.unmodifiable(out);
    case WorkoutsFilter.all:
      return ref.watch(allExercisesProvider.future);
  }
});

class WorkoutsPage extends ConsumerStatefulWidget {
  const WorkoutsPage({super.key});

  @override
  ConsumerState<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends ConsumerState<WorkoutsPage> {
  WorkoutsFilter _selected = WorkoutsFilter.forYou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(_filteredExercisesProvider(_selected));

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
              itemCount: WorkoutsFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final filter = WorkoutsFilter.values[i];
                final selected = filter == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = filter),
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
                        filter.label,
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
          ...list.when(
            loading: () => const [_LoadingCard()],
            error: (e, _) => [
              GlassCard(child: Text('Could not load workouts: $e')),
            ],
            data: (items) {
              if (items.isEmpty) {
                return [
                  GlassCard(
                    child: Text(
                      _emptyMessage(_selected),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ];
              }
              final out = <Widget>[];
              for (final ex in items) {
                out.add(_ExerciseCard(exercise: ex));
                out.add(const SizedBox(height: 16));
              }
              return out;
            },
          ),
        ],
      ),
    );
  }

  String _emptyMessage(WorkoutsFilter f) {
    switch (f) {
      case WorkoutsFilter.forYou:
        return "We're still building your personalised feed. Try another filter while we add more content.";
      case WorkoutsFilter.atHome:
        return 'No body-weight workouts in the catalog yet.';
      case WorkoutsFilter.strength:
        return 'No strength exercises in the catalog yet.';
      case WorkoutsFilter.cardio:
        return 'No cardio exercises in the catalog yet.';
      case WorkoutsFilter.all:
        return 'The exercise catalog is empty.';
    }
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = AppPalette.tileGradients[
        exercise.id.hashCode.abs() % AppPalette.tileGradients.length];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => GoRouter.of(context).go('/workout/${exercise.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(colors: gradient),
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
                        exercise.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${exercise.durationMinutes} min',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  exercise.summary.isEmpty
                      ? exercise.muscles
                          .take(3)
                          .map((m) => m.replaceAll('_', ' '))
                          .join(' · ')
                      : exercise.summary,
                  maxLines: 2,
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
