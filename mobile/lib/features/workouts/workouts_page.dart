import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/shell_insets.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../equipment/data/catalog_labels.dart';
import '../equipment/data/equipment_models.dart';
import '../equipment/state/equipment_providers.dart';
import '../form_check/state/form_check_providers.dart';
import '../personalisation/state/personalisation_providers.dart';
import '../programmes/data/programme.dart';
import '../programmes/data/programme_labels.dart';
import '../programmes/data/programme_templates.dart';
import '../programmes/state/programme_providers.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/scheduled_session.dart';
import 'state/offline_video_providers.dart';
import 'state/scheduled_session_providers.dart';
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
  // The exercises the Form Coach can actually judge. Operator: *"сделать
  // отдельную группу с разными упражнениями которые может контролировать аи
  // тренер"*.
  //
  // Second in the row on purpose — it is the feature the app is built around,
  // and a capability nobody can find is a capability nobody has. It is also
  // the smallest group by a wide margin, and that is the honest number rather
  // than a defect: see the resolver.
  formCoach,
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
    case WorkoutsFilter.formCoach:
      return l.workoutsFilterFormCoach;
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
    return videoFirst(await ref.watch(safeCatalogProvider.future));
  }
  if (filter == WorkoutsFilter.noEquipment) {
    final all = await ref.watch(safeCatalogProvider.future);
    // `!needsEquipment`, not `equipmentId == null`. The purchased library has
    // no machine ids at all, so the old test promised a no-equipment tab and
    // filled it with barbell work; the vendor's own equipment column is what
    // answers this until the mapping exists.
    return videoFirst(all.where((e) => !e.needsEquipment).toList());
  }
  if (filter == WorkoutsFilter.formCoach) {
    final all = await ref.watch(safeCatalogProvider.future);
    // `formCoachSupports`, not `poseTargetId != null`. The catalog tags 540
    // rows across eight movement patterns; the coach has been taught one of
    // them, so 37 of those 540 can actually be judged. Filtering on the tag
    // would fill a chip named after a feature with 503 exercises that do not
    // have it — the same dishonesty `formCoachSupports` was written to keep
    // off the exercise page, one screen earlier.
    //
    // The number grows by authoring pose targets, not by editing this line.
    return videoFirst(
        all.where((e) => formCoachSupports(e.poseTargetId)).toList());
  }
  if (filter == WorkoutsFilter.stretching) {
    final all = await ref.watch(safeCatalogProvider.future);
    return videoFirst(all.where((e) => e.isStretch).toList());
  }

  final muscles = kFilterMuscles[filter];
  if (muscles != null) {
    final all = await ref.watch(safeCatalogProvider.future);
    return videoFirst(
        all.where((e) => e.muscles.any(muscles.contains)).toList());
  }

  final categories = kFilterCategories[filter]!;
  final all = await ref.watch(safeCatalogProvider.future);
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

/// Which half of the Train tab is showing. R11i split what used to be one
/// flat exercise browser into the prototype's own two-tab shape
/// (`App.tsx`'s `WorkoutsScreen`, `subTab: 'programs' | 'library'`):
/// [programs] is the NEW half, built on Gate P's programme entity;
/// [library] is every pixel of the original tab, unchanged, just moved into
/// its own widget so it could sit behind a toggle instead of always being
/// what "Train" shows.
enum _WorkoutsSubTab { programs, library }

class WorkoutsPage extends ConsumerStatefulWidget {
  const WorkoutsPage({super.key});

  @override
  ConsumerState<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends ConsumerState<WorkoutsPage> {
  // The prototype opens on 'programs' -- the tab this app had nothing to
  // show on before Gate P, and the one that gives a new session on Home's
  // header something real to point at the moment it exists.
  _WorkoutsSubTab _subTab = _WorkoutsSubTab.programs;

  @override
  Widget build(BuildContext context) {
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).workoutsTrain),
      body: Column(
        children: [
          const SizedBox(height: 92),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SubTabToggle(
              selected: _subTab,
              onChanged: (t) => setState(() => _subTab = t),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _subTab == _WorkoutsSubTab.programs
                ? const _ProgramsTab()
                : const _LibraryTab(),
          ),
        ],
      ),
    );
  }
}

/// The toggle pill itself -- same visual language as the filter chips below
/// it (`AnimatedContainer`, accent gradient on the active side), because it
/// is the same kind of control: pick one of a small fixed set.
class _SubTabToggle extends StatelessWidget {
  const _SubTabToggle({required this.selected, required this.onChanged});
  final _WorkoutsSubTab selected;
  final ValueChanged<_WorkoutsSubTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colors.surfaceInteractive,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: _WorkoutsSubTab.values.map((tab) {
          final isSelected = tab == selected;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isSelected,
              child: GestureDetector(
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? theme.colors.accentPrimary : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tab == _WorkoutsSubTab.programs
                        ? l.workoutsSubTabPrograms
                        : l.workoutsSubTabLibrary,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? AppSemanticColors.onGradientInk
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// The original Train tab, byte-for-byte, minus the top padding the parent
/// [Column] now supplies (it used to be baked into this list's own padding,
/// back when this WAS the whole page).
class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();

  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  WorkoutsFilter _selected = WorkoutsFilter.forYou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(_filteredExercisesProvider(_selected));

    return SmoothScrollList(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
      children: [
        const _QuickToolsRow(),
        const SizedBox(height: 16),
        const _OfflinePrefetchCard(),
        const SizedBox(height: 16),
        SizedBox(
          // 48, not 44. The row is the app's main navigation between
          // exercise lists and 44dp is under every platform's minimum
          // target; the extra four pixels are the difference between a chip
          // a shaky hand can hit and one it cannot.
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: WorkoutsFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final filter = WorkoutsFilter.values[i];
              final selected = filter == _selected;
              return Semantics(
                // A GestureDetector announces nothing, so the whole filter
                // row read to a screen reader as a list of words with no
                // indication that any of them was tappable or which one was
                // active. `selected` is what makes the current filter
                // audible at all.
                button: true,
                selected: selected,
                child: GestureDetector(
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
                        workoutsFilterLabel(
                            AppLocalizations.of(context), filter),
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: selected
                              ? AppSemanticColors.onGradientInk
                              : theme.colorScheme.onSurface,
                        ),
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
          // The exception used to be interpolated straight into the card, so
          // a Firestore outage read as "[cloud_firestore/unavailable] The
          // service is currently unavailable. This is a most likely a
          // transient condition and may be corrected by retrying with a
          // backoff." — a backend sentence, in English, telling the user to
          // do something they have no button for. Now: what happened, and
          // the retry the message was describing.
          error: (e, _) => [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context).errorServiceUnavailable),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => ref
                          .invalidate(_filteredExercisesProvider(_selected)),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(AppLocalizations.of(context).errorRetry),
                    ),
                  ),
                ],
              ),
            ),
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
    // Same body the detail page will demonstrate on, so the thumbnail and the
    // clip behind it are not two different people.
    final body = ExerciseItem.bodyForGender(
        ref.watch(currentProfileProvider).valueOrNull?.personal.gender);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => GoRouter.of(context).push('/exercise/${exercise.id}'),
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
                        color: theme.colors.textSecondary,
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
}

/// Premium-gated "Download next week's videos for offline" card. Tapping
/// it triggers [OfflinePrefetchAction.prefetchNext7Days]; free users see
/// the upsell version that routes to /subscription.
class _OfflinePrefetchCard extends ConsumerWidget {
  const _OfflinePrefetchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier != SubscriptionTier.free;
    final action = ref.watch(offlinePrefetchActionProvider);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () async {
        // The plan may still be loading, and `isPremium` reads `free` while it
        // is. Deciding from that would send a paying user to the paywall for a
        // feature they already have, so the tap waits for the answer instead
        // of guessing from the default.
        if (!ref.read(entitlementResolvedProvider)) {
          try {
            await ref.read(currentSubscriptionProvider.future);
          } catch (_) {
            // Still unknown. Handled below: no pitch, no false unlock.
          }
        }
        if (!context.mounted) return;
        if (!ref.read(entitlementResolvedProvider)) return;
        if (ref.read(effectiveTierProvider) == SubscriptionTier.free) {
          GoRouter.of(context).push('/subscription');
          return;
        }
        // Explicit wiring: resolve the catalog, then hand prefetch a real
        // videoUrlsFor closure (shared resolver, same as the provider default).
        final catalog = await ref.read(safeCatalogProvider.future);
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
                color: AppSemanticColors.onGradientInk),
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
                    color: theme.colors.textSecondary,
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
              color: theme.colors.textSecondary,
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
            child: Icon(icon, color: AppSemanticColors.onGradientInk, size: 20),
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
                      color: theme.colors.textSecondary,
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

/// R11i's other half: the enrolled/browse-programmes screen the prototype's
/// Workouts tab opens on, built on Gate P's [Programme] entity.
class _ProgramsTab extends ConsumerStatefulWidget {
  const _ProgramsTab();

  @override
  ConsumerState<_ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends ConsumerState<_ProgramsTab> {
  // null = every goal, same "no filter selected" shape WorkoutsFilter.all
  // uses, kept as a real null rather than a synthetic sixth ProgrammeGoal so
  // the domain enum never has to carry a UI-only value.
  ProgrammeGoal? _goalFilter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final templates = _goalFilter == null
        ? programmeTemplates
        : programmeTemplates.where((t) => t.goal == _goalFilter).toList();

    return SmoothScrollList(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
      children: [
        const _CurrentProgrammeCard(),
        const SizedBox(height: 18),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: ProgrammeGoal.values.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final goal = i == 0 ? null : ProgrammeGoal.values[i - 1];
              final selected = goal == _goalFilter;
              return Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  onTap: () => setState(() => _goalFilter = goal),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: selected
                            ? theme.colors.accentPrimary
                            : theme.colors.outline,
                        width: 1.5,
                      ),
                      color: selected
                          ? theme.colors.accentPrimary.withValues(alpha: 0.12)
                          : theme.colors.surfaceElevated,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      goal == null ? l.workoutsFilterAll : _goalLabel(l, goal),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? theme.colors.accentPrimary
                            : theme.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (templates.isEmpty)
          GlassCard(child: Text(l.workoutsEmptyFiltered(_goalLabel(l, _goalFilter!))))
        else
          for (var i = 0; i < templates.length; i++) ...[
            _ProgrammeTemplateCard(template: templates[i]),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

/// [ProgrammeGoal] display labels. Own function rather than a
/// `CatalogLabels` method -- the goal vocabulary belongs to programmes, not
/// the exercise catalogue `CatalogLabels` otherwise speaks for.
/// The card wash for a programme, keyed by its goal.
///
/// Bug 6, second half. Two things were wrong with what this replaces.
///
/// The visible one: `AppPalette.tileGradients` are saturated two-hue aurora
/// ramps painted at full opacity, which is the look Ф1 already removed from
/// the background and the glass cards and which the design never had on these
/// headers either.
///
/// The one nobody had noticed: the gradient was picked by `index % 5` over the
/// **filtered** list, so tapping a goal chip renumbered the survivors and the
/// same programme changed colour. Keying off the goal makes a programme's
/// colour a property of the programme instead of a property of what else
/// happens to be on screen.
Color _goalHue(ProgrammeGoal goal) {
  switch (goal) {
    case ProgrammeGoal.strength:
      return AppPalette.programmeStrength;
    case ProgrammeGoal.muscle:
      return AppPalette.programmeMuscle;
    case ProgrammeGoal.weightLoss:
      return AppPalette.programmeWeightLoss;
    case ProgrammeGoal.form:
      return AppPalette.programmeForm;
    case ProgrammeGoal.comeback:
      return AppPalette.programmeComeback;
    case ProgrammeGoal.endurance:
      return AppPalette.programmeEndurance;
  }
}

String _goalLabel(AppLocalizations l, ProgrammeGoal goal) {
  switch (goal) {
    case ProgrammeGoal.strength:
      return l.programmeGoalStrength;
    case ProgrammeGoal.muscle:
      return l.programmeGoalMuscle;
    case ProgrammeGoal.weightLoss:
      return l.programmeGoalWeightLoss;
    case ProgrammeGoal.form:
      return l.programmeGoalForm;
    case ProgrammeGoal.comeback:
      return l.programmeGoalComeback;
    case ProgrammeGoal.endurance:
      return l.programmeGoalEndurance;
  }
}

/// "Текущая программа" -- title, week/percent bar, and a way into the next
/// session. Absent (not a placeholder) when nothing is active, same
/// convention [PlanProgress.isEmpty] uses on Home for the same reason: an
/// empty card reads as failure, not as "you have not started one yet".
class _CurrentProgrammeCard extends ConsumerWidget {
  const _CurrentProgrammeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programme = ref.watch(activeProgrammeProvider);
    final progress = ref.watch(activeProgrammeProgressProvider);
    if (programme == null || progress == null) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Earliest upcoming session belonging to THIS programme -- the same
    // "Спина и бицепс →" CTA the prototype's current-programme card shows,
    // sourced from real scheduled rows rather than a guessed "next day".
    // upcomingSessionsProvider is already sorted ascending, so `.first` is
    // the earliest.
    final matching = ref
        .watch(upcomingSessionsProvider)
        .where((s) => s.programmeId == programme.id);
    final ScheduledSession? next = matching.isEmpty ? null : matching.first;

    return GlassCard(
      key: const Key('workouts.currentProgramme'),
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.programmeCurrentProgramme,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colors.accentPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ProgrammeLabels.title(l, programme.templateId,
                stored: programme.title),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 4,
              backgroundColor: theme.colors.surfaceInteractive,
              valueColor: AlwaysStoppedAnimation<Color>(theme.colors.accentPrimary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${l.programmeWeekOfWeeks(progress.week, progress.weeks)} · '
            '${progress.percent}%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            _ProgrammeDayThumbs(session: next),
          ],
          const SizedBox(height: 14),
          if (next != null)
            GlassCard(
              key: const Key('workouts.currentProgramme.continue'),
              padding: EdgeInsets.zero,
              onTap: () => GoRouter.of(context)
                  .push('/workout/${next.exerciseId}?day=${next.id}'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                      colors: [AppPalette.auroraTeal, AppPalette.auroraBlue]),
                ),
                alignment: Alignment.center,
                child: Text(
                  // Same "+N" as Home's tile, and for the same reason — see
                  // `home_page.dart`.
                  //
                  // The label says how big the day is, and since the player's
                  // day gate the tap now delivers all of it: `?day=` below
                  // makes the player key its log by the day and draw the day
                  // strip, so the remaining exercises are reachable from
                  // inside instead of needing the add-exercise button
                  // (`workout_player_page.dart:60-72`, `daySessionId`).
                  //
                  // This comment previously said the opposite — that the tap
                  // opened only the first exercise — which was true when it
                  // was written and stopped being true one commit later.
                  '${resolveExerciseTitle(ref.watch(exerciseTitlesProvider), next.exerciseId, next.exerciseTitle)}${next.exerciseCount > 1 ? '  +${next.exerciseCount - 1}' : ''} →',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppSemanticColors.onGradientInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            Text(
              l.programmeNoUpcomingSession,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The next session's exercises, as pictures.
///
/// B5c. The card named the programme, drew a progress bar and offered a CTA,
/// and never showed a single movement — "Спина и бицепс" was a phrase you had
/// to take on trust. The posters are already bundled and already cut from the
/// clips (`ExerciseThumb`), so this costs no network, no new asset and no new
/// widget.
///
/// The exercises come from the real scheduled day, not from the template: a
/// [ProgrammeTemplate] carries goal, level, weeks, days and muscles and no
/// exercises at all (`programme_templates.dart:33-53`), so there is nothing
/// truthful to draw for a programme nobody has started yet.
class _ProgrammeDayThumbs extends ConsumerWidget {
  const _ProgrammeDayThumbs({required this.session});

  final ScheduledSession session;

  /// Past five the row reads as a texture rather than as exercises you can
  /// recognise, which is the only reason to show pictures at all.
  static const int _maxThumbs = 5;
  static const double _size = 44;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planned = session.exercises;
    if (planned.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // Measured rather than assumed. Five 44px tiles plus their gaps need 268px;
    // this card has ~328px on a 400px phone but only ~248px on a 320px one, so
    // a fixed five would overflow the narrow case — the same unbounded-Row
    // mistake that had just put 31px of the player's button off-screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = ((constraints.maxWidth + _gap) / (_size + _gap)).floor();
        final room = fits.clamp(1, _maxThumbs);
        // When something is being left out, the last slot goes to the count
        // rather than to one more picture: "+3" is information, a sixth tile
        // that silently stands for four exercises is not.
        //
        // The count is of ALL exercises not drawn, injury-screened or not —
        // the same unfiltered basis as the CTA's own "+N" above
        // (`next.exerciseCount - 1`). A "+N" that quietly excluded screened
        // exercises would make two numbers on one card disagree.
        final hidden = planned.length - room;
        final shown = hidden > 0 ? planned.take(room - 1) : planned.take(room);
        final remainder = planned.length - shown.length;

        return Row(
          key: const Key('workouts.currentProgramme.thumbs'),
          children: [
            for (final e in shown) ...[
              Builder(builder: (context) {
                final resolved =
                    ref.watch(exerciseResolutionProvider(e.exerciseId));
                // A tile still resolving is NOT the same as a tile with no
                // clip, and ExerciseThumb's gradient fallback means the
                // latter (`exercise_thumb.dart:15-19`). Handing it a null
                // while the catalogue is still loading would flash "no
                // demonstration filmed" at every exercise and then swap in
                // the poster — a wrong statement, briefly, on every open.
                if (resolved.isLoading) {
                  return _ThumbPlaceholder(size: _size);
                }
                // `visible`, not `exercise`. An exercise the user's own injury
                // list contraindicates must not have its picture on screen;
                // null falls through to the gradient tile, which carries
                // nothing about the movement. The slot survives, so the day's
                // size stays honest instead of the row quietly shrinking and
                // mis-stating how long the day is.
                return ExerciseThumb(
                  exercise: resolved.valueOrNull?.visible,
                  size: _size,
                );
              }),
              const SizedBox(width: _gap),
            ],
            if (remainder > 0)
              Text(
                '+$remainder',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A tile whose exercise has not resolved yet. Deliberately says nothing:
/// neither a poster nor the gradient that means "no clip filmed".
class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.31),
          color: Theme.of(context).colors.surfaceInteractive,
        ),
      );
}

/// One enrollable programme. The header wash comes from the programme's goal
/// ([_goalHue]); it used to rotate through [AppPalette.tileGradients] by list
/// position, which is what made a card change colour when the list was
/// filtered. `index` went with it — it had no other reader.
class _ProgrammeTemplateCard extends ConsumerWidget {
  const _ProgrammeTemplateCard({required this.template});
  final ProgrammeTemplate template;

  Future<void> _start(BuildContext context, WidgetRef ref, Programme? active) async {
    final l = AppLocalizations.of(context);
    if (active != null && active.templateId != template.id) {
      final confirmed = await _ConfirmSwitchSheet.show(
        context,
        ProgrammeLabels.title(l, active.templateId, stored: active.title),
      );
      if (confirmed != true || !context.mounted) return;
    }
    await ref.read(programmeActionProvider.notifier).enroll(template);
    if (!context.mounted) return;
    final state = ref.read(programmeActionProvider);
    state.when(
      data: (_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            l.programmeEnrolled(ProgrammeLabels.title(l, template.id))),
        behavior: SnackBarBehavior.floating,
      )),
      // Same reason as the list card above: `'$e'` put the raw Firestore
      // error in front of the user. The action is retryable and the snackbar
      // is where the retry belongs, so it carries one instead of the
      // exception text.
      error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.errorServiceUnavailable),
        behavior: SnackBarBehavior.floating,
        // `active: null` deliberately: the switch-confirmation sheet was
        // already answered on the first attempt, and asking again on a retry
        // of the same action would be a second dialog for one decision.
        action: SnackBarAction(
          label: l.errorRetry,
          onPressed: () => _start(context, ref, null),
        ),
      )),
      loading: () {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = ref.watch(activeProgrammeProvider);
    final loading = ref.watch(programmeActionProvider).isLoading;
    final isCurrent =
        active != null && active.templateId == template.id && active.status == ProgrammeStatus.active;
    final muscleLabel = template.isFullBody
        ? l.programmeFullBody
        : template.muscles.map((m) => CatalogLabels.muscle(l, m)).join(', ');
    final hue = _goalHue(template.goal);

    return GlassCard(
      key: Key('programme.template.${template.id}'),
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 76,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              // 0.20 -> 0.08 are the prototype's own `${p.color}33` and
              // `${p.color}15` (`App.tsx:4795`), read as alpha.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  hue.withValues(alpha: 0.20),
                  hue.withValues(alpha: 0.08),
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Bug 5, the "right-edge chip clipping" from the operator's
                // device walkthrough. A Row neither wraps nor scrolls, so two
                // content-sized chips that together want more than the card's
                // 256dp simply clipped the right-hand one -- measured at 70px
                // and 34px over on two of the six templates, at 320dp with the
                // text size Android's own accessibility settings reach.
                // `Flexible` is what lets the Row shrink them instead;
                // `spaceBetween` still pushes them apart whenever they fit.
                Flexible(
                    child: _TemplateChip(
                        CatalogLabels.difficulty(l, template.level))),
                const SizedBox(width: 8),
                Flexible(child: _TemplateChip(_goalLabel(l, template.goal))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ProgrammeLabels.title(l, template.id),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  muscleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
                Text(
                  l.programmeWeeksAndDaysPerWeek(
                      template.weeks, template.daysPerWeek),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: EdgeInsets.zero,
                  onTap: loading || isCurrent
                      ? null
                      : () => _start(context, ref, active),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isCurrent
                          ? null
                          : Border.all(color: theme.colors.outline, width: 1.5),
                      color: isCurrent ? theme.colors.surfaceInteractive : null,
                    ),
                    alignment: Alignment.center,
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            isCurrent ? l.programmeContinue : l.programmeStart,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
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
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    // Outlined, not a filled white pill. The header is no longer a bright
    // gradient (bug 6 above), so the pill-plus-dark-ink pairing stopped
    // working: measured on the new wash it scores 4.36 on the comeback hue and
    // 4.44 on strength, both under AA 4.5. Light text straight on the wash
    // scores 7.51-9.28. The prototype's own answer -- the hue as text on a
    // 15%-hue pill -- was measured too and is worse still, 1.61-2.30, the same
    // failure its `#3E3E50` nav labels had; parity does not extend to
    // illegibility.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        // Bounded for the same reason `_ScrimChip` in `exercise_reference.dart`
        // is: once the parent is allowed to squeeze the chip, an unbounded
        // Text inside it just moves the clip one level down.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// Confirms replacing the active programme -- enrolling in a second one
/// abandons the first (`ProgrammeAction.enroll`'s own doc comment), which is
/// a real state change worth a beat before committing to, not a silent
/// side-effect of tapping "Start programme" on a browse card.
class _ConfirmSwitchSheet extends StatelessWidget {
  const _ConfirmSwitchSheet({required this.currentTitle});
  final String currentTitle;

  static Future<bool?> show(BuildContext context, String currentTitle) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSwitchSheet(currentTitle: currentTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // `floating: true` -- same reason every other confirm/rate sheet in the
    // app uses it (`difficulty_rating_sheet.dart`): an ordinary GlassCard is
    // translucent, and a translucent card over the template list this sheet
    // opens on top of would read the list through the confirmation text.
    return Padding(
      // Bottom derived, not a flat 24: the Cancel/Start row sat under the
      // gesture indicator on the operator's phone.
      padding: EdgeInsets.fromLTRB(16, 24, 16, sheetBottomInset(context, base: 24)),
      child: GlassCard(
        floating: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.programmeSwitchWarning(currentTitle),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l.programmeStart),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
