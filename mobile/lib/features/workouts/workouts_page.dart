import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../equipment/data/catalog_labels.dart';
import '../equipment/data/equipment_models.dart';
import '../equipment/state/equipment_providers.dart';
import '../personalisation/state/personalisation_providers.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'state/offline_video_providers.dart';
import '../equipment/widgets/exercise_thumb.dart';
import '../profile/state/profile_providers.dart';

/// One filter chip on the Train tab. The id drives which provider feeds the
/// list; the label is localized in [workoutsFilterLabel].
///
/// Round 4 (S4) added the muscle groups and the equipment-type groups: with
/// the catalog at 192 exercises across 48 machines, five chips was not
/// enough to find anything (operator: "добавь больше груп для сортировки в
/// зависимости от тренажеров и группы мышц").
enum WorkoutsFilter {
  forYou,
  // Equipment type.
  machines,
  freeWeights,
  cardio,
  // Was `atHome` until 2026-08-04. It never filtered on where you are: a
  // kettlebell swing in your kitchen still needs a kettlebell, and a hamstring
  // stretch in a commercial gym still needs nothing. It filters on
  // `!needsEquipment`, and 476 of the 1,887 shipped exercises are that.
  // Operator: *"создай отдельную группу для 436 и назови «без оборудования»"*.
  noEquipment,
  // Muscle groups, ordered the way a gym-goer thinks about a split.
  chest,
  back,
  legs,
  glutes,
  shoulders,
  arms,
  core,
  // Not a muscle group and not an equipment type, so it gets its own arm of
  // the resolver. 65 exercises the catalog already flagged and nothing could
  // ask for — operator: "не вижу новые упражнения на растяжку егу и пилатес
  // в списке категорий". One chip rather than three: yoga is one exercise and
  // Pilates is three, which is not a category, it is a rounding error.
  stretching,
  all,
}

/// Muscle tags each muscle-group chip covers. Uses the same vocabulary as
/// `ExerciseItem.muscles`, so a chip can never filter on a tag the catalog
/// does not use.
const Map<WorkoutsFilter, Set<String>> kFilterMuscles = {
  WorkoutsFilter.chest: {'chest'},
  WorkoutsFilter.back: {'back', 'lats', 'traps', 'lower_back'},
  WorkoutsFilter.legs: {'quads', 'hamstrings', 'calves', 'adductors'},
  WorkoutsFilter.glutes: {'glutes'},
  WorkoutsFilter.shoulders: {'shoulders'},
  WorkoutsFilter.arms: {'biceps', 'triceps', 'forearms'},
  WorkoutsFilter.core: {'core'},
};

/// Equipment categories each equipment-type chip covers, matching the
/// `category` field in equipment.json.
const Map<WorkoutsFilter, Set<String>> kFilterCategories = {
  WorkoutsFilter.machines: {'strength'},
  WorkoutsFilter.freeWeights: {'free_weights'},
  WorkoutsFilter.cardio: {'cardio'},
};

String workoutsFilterLabel(AppLocalizations l, WorkoutsFilter f) {
  switch (f) {
    case WorkoutsFilter.forYou:
      return l.workoutsFilterForYou;
    case WorkoutsFilter.machines:
      return l.workoutsFilterMachines;
    case WorkoutsFilter.freeWeights:
      return l.workoutsFilterFreeWeights;
    case WorkoutsFilter.cardio:
      return l.workoutsFilterCardio;
    case WorkoutsFilter.noEquipment:
      return l.workoutsFilterNoEquipment;
    case WorkoutsFilter.chest:
      return l.workoutsFilterChest;
    case WorkoutsFilter.back:
      return l.workoutsFilterBack;
    case WorkoutsFilter.legs:
      return l.workoutsFilterLegs;
    case WorkoutsFilter.glutes:
      return l.workoutsFilterGlutes;
    case WorkoutsFilter.shoulders:
      return l.workoutsFilterShoulders;
    case WorkoutsFilter.arms:
      return l.workoutsFilterArms;
    case WorkoutsFilter.core:
      return l.workoutsFilterCore;
    case WorkoutsFilter.stretching:
      return l.workoutsFilterStretching;
    case WorkoutsFilter.all:
      return l.workoutsFilterAll;
  }
}

/// Exercises that can show a clip first, the rest after — order preserved
/// inside each group.
///
/// Operator: *"Оставшиеся 168 убрать в конец списков"*. A stable partition
/// rather than a sort, so it composes with the "For you" ranking instead of
/// replacing it: the ranker still decides which muscles come first, this only
/// decides that a demonstrated exercise outranks an undemonstrated one at the
/// same rank.
///
/// Public and pure so the behaviour can be tested without a catalog.
List<ExerciseItem> videoFirst(List<ExerciseItem> items) => [
      ...items.where((e) => e.hasVideo),
      ...items.where((e) => !e.hasVideo),
    ];

/// Resolves a filter into the actual list of exercises to show. Pulls from
/// the recommended ("for you") feed and the raw catalog and slices by
/// equipment category or muscle tag.
final _filteredExercisesProvider =
    FutureProvider.family<List<ExerciseItem>, WorkoutsFilter>(
        (ref, filter) async {
  if (filter == WorkoutsFilter.forYou) {
    // Ranked, not merely filtered. `rankedForYouProvider` puts the muscles the
    // user has trained least in the last weeks at the top; before it was wired
    // up here the tab called "For you" showed every user the same order, and
    // the whole personalisation folder — a fitness model built from every
    // logged set, a ranker, and tests for both — was watched by nothing.
    return videoFirst(await ref.watch(rankedForYouProvider.future));
  }
  if (filter == WorkoutsFilter.all) {
    return videoFirst(await ref.watch(allExercisesProvider.future));
  }
  if (filter == WorkoutsFilter.noEquipment) {
    final all = await ref.watch(allExercisesProvider.future);
    // `!needsEquipment`, not `equipmentId == null`. The purchased library has
    // no machine ids at all, so the old test promised a no-equipment tab and
    // filled it with barbell work; the vendor's own equipment column is what
    // answers this until the mapping exists.
    return videoFirst(all.where((e) => !e.needsEquipment).toList());
  }
  if (filter == WorkoutsFilter.stretching) {
    final all = await ref.watch(allExercisesProvider.future);
    return videoFirst(all.where((e) => e.isStretch).toList());
  }

  final muscles = kFilterMuscles[filter];
  if (muscles != null) {
    final all = await ref.watch(allExercisesProvider.future);
    return videoFirst(
        all.where((e) => e.muscles.any(muscles.contains)).toList());
  }

  final categories = kFilterCategories[filter]!;
  final all = await ref.watch(allExercisesProvider.future);
  final equipment =
      await ref.watch(equipmentRepositoryProvider).listEquipment();
  final wantedIds = {
    for (final eq in equipment)
      if (categories.contains(eq.category)) eq.id,
  };
  return videoFirst(all
      .where((e) => e.equipmentId != null && wantedIds.contains(e.equipmentId))
      .toList());
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
      appBar: GlassAppBar(title: AppLocalizations.of(context).workoutsTrain),
      body: SmoothScrollList(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
                        workoutsFilterLabel(
                            AppLocalizations.of(context), filter),
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
              GlassCard(
                  child: Text(AppLocalizations.of(context)
                      .workoutsCouldNotLoadWorkouts(e))),
            ],
            data: (items) {
              if (items.isEmpty) {
                return [
                  GlassCard(
                    child: Text(
                      _emptyMessage(context, _selected),
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

  String _emptyMessage(BuildContext context, WorkoutsFilter f) {
    final l = AppLocalizations.of(context);
    if (f == WorkoutsFilter.forYou) return l.workoutsEmptyForYou;
    if (f == WorkoutsFilter.all) return l.workoutsEmptyAll;
    // Every other chip is a slice of the catalog, so one message naming the
    // slice covers them all — 12 near-identical strings would just be 12
    // things to keep translated.
    return l.workoutsEmptyFiltered(workoutsFilterLabel(l, f));
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

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Same body the detail page will demonstrate on, so the thumbnail and the
    // clip behind it are not two different people.
    final body = ExerciseItem.bodyForGender(
        ref.watch(currentProfileProvider).valueOrNull?.personal.gender);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => GoRouter.of(context).push('/workout/${exercise.id}'),
      child: Row(
        children: [
          ExerciseThumb(exercise: exercise, size: 52, body: body),
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
                      AppLocalizations.of(context)
                          .equipmentMin(exercise.durationMinutes),
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
                          .map((m) => CatalogLabels.muscle(
                              AppLocalizations.of(context), m))
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
          GoRouter.of(context).push('/subscription');
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
                      ? AppLocalizations.of(context)
                          .workoutsOfflineDownloadTitle
                      : AppLocalizations.of(context).workoutsOfflineLockedTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  action.isLoading
                      ? AppLocalizations.of(context).workoutsOfflineDownloading
                      : action.hasError
                          ? AppLocalizations.of(context)
                              .workoutsOfflineFailed('${action.error}')
                          : AppLocalizations.of(context).workoutsOfflineHint,
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
            label: AppLocalizations.of(context).formcheckFormCoach,
            subtitle: AppLocalizations.of(context).workoutsOnDevicePoseCheck,
            gradient: const [
              AppPalette.auroraPeach,
              AppPalette.auroraPink,
            ],
            onTap: () => GoRouter.of(context).push('/form-check'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTool(
            icon: Icons.photo_camera_outlined,
            label: AppLocalizations.of(context).workoutsRecognise,
            subtitle: AppLocalizations.of(context).workoutsPhotoEquipment,
            gradient: const [
              AppPalette.auroraViolet,
              AppPalette.auroraBlue,
            ],
            // The Scan tab owns the camera + classifier; the old standalone
            // /recognise page fed raw JPEG bytes into an NV21-metadata
            // InputImage and died with InputImageConverterError on-device.
            onTap: () => GoRouter.of(context).go('/scan'),
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
