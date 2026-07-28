import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/scroll_dim_list.dart';
import '../equipment/data/equipment_models.dart';
import '../equipment/state/equipment_providers.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'state/offline_video_providers.dart';

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
          const _QuickToolsRow(),
          const SizedBox(height: 16),
          const _OfflinePrefetchCard(),
          const SizedBox(height: 16),
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

/// Premium-gated "Download next week's videos for offline" card. Tapping
/// it triggers [OfflinePrefetchAction.prefetchNext7Days]; free users see
/// the upsell version that routes to /subscription.
class _OfflinePrefetchCard extends ConsumerWidget {
  const _OfflinePrefetchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier != SubscriptionTier.free;
    final action = ref.watch(offlinePrefetchActionProvider);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () async {
        if (!isPremium) {
          GoRouter.of(context).go('/subscription');
          return;
        }
        // Explicit wiring: resolve the catalog, then hand prefetch a real
        // videoUrlsFor closure (shared resolver, same as the provider default).
        final catalog = await ref.read(allExercisesProvider.future);
        await ref
            .read(offlinePrefetchActionProvider.notifier)
            .prefetchNext7Days(videoUrlsFor: videoUrlResolverFor(catalog));
      },
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraBlue,
              ]),
            ),
            child: const Icon(Icons.download_for_offline_outlined,
                color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium
                      ? 'Download next 7 days for offline'
                      : 'Offline downloads · Supporter+',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  action.isLoading
                      ? 'Downloading…'
                      : action.hasError
                          ? 'Last run failed: ${action.error}'
                          : 'Gym wifi is hostile — cache videos at home.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          if (action.isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              isPremium ? Icons.cloud_download_outlined : Icons.lock_outline,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
        ],
      ),
    );
  }
}

/// Two side-by-side tools above the filter row: Form coach + Recognise.
/// Both are page routes that previously had no nav surface.
class _QuickToolsRow extends StatelessWidget {
  const _QuickToolsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickTool(
            icon: Icons.center_focus_strong_outlined,
            label: 'Form coach',
            subtitle: 'On-device pose check',
            gradient: const [
              AppPalette.auroraPeach,
              AppPalette.auroraPink,
            ],
            onTap: () => GoRouter.of(context).go('/form-check'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTool(
            icon: Icons.photo_camera_outlined,
            label: 'Recognise',
            subtitle: 'Photo → equipment',
            gradient: const [
              AppPalette.auroraViolet,
              AppPalette.auroraBlue,
            ],
            onTap: () => GoRouter.of(context).go('/recognise'),
          ),
        ),
      ],
    );
  }
}

class _QuickTool extends StatelessWidget {
  const _QuickTool({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(colors: gradient),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
