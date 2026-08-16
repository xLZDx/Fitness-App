import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../ai_coach/ai_coach_context.dart';
import '../ai_coach/ai_coach_sheet.dart';
import '../../shared/widgets/glass.dart';
import 'data/catalog_labels.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../workouts/widgets/plate_calculator.dart';
import '../workouts/widgets/warmup_calculator.dart';
import '../safety/state/eligibility_providers.dart' show safetyContextProvider;
import 'data/equipment_models.dart';
import 'widgets/safety_disclosure.dart';
import 'state/equipment_providers.dart';
import 'widgets/equipment_report_sheet.dart';
import 'widgets/exercise_thumb.dart';

class EquipmentDetailPage extends ConsumerWidget {
  const EquipmentDetailPage({super.key, required this.equipmentId});

  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eq = ref.watch(equipmentByIdProvider(equipmentId));
    final ex = ref.watch(recommendedExercisesProvider(equipmentId));

    // N04 (G-B/B4). The whole-person gate, which this screen did not apply.
    // `exercise_page.dart` gets one structurally — its coach entry sits inside
    // `ExerciseResolutionView`'s builder, which runs only for an exercise the
    // eligibility layer allows — but this page and the scanner reach
    // `AiCoachSheet` directly, so a user the app refuses all training could
    // still ask for and receive a sets-and-reps prescription.
    //
    // `blockedByAStatedAnswer` rather than `!allowsAnyTraining`, deliberately:
    // see that getter's own doc. The latter is fail-closed on an UNANSWERED
    // questionnaire, so gating on it would hide the coach from every user who
    // has not onboarded — a much larger change than N04 describes, and one
    // whose cost lands on people who have told us nothing that refuses them.
    // N04 is about a user who was refused, not one who was never asked.
    //
    // Null while resolving: hidden until the answer is real. Showing first and
    // retracting is the direction that cannot be undone once tapped.
    final safety = ref.watch(safetyContextProvider).valueOrNull;
    final mayTrain = safety != null && !safety.blockedByAStatedAnswer;

    return FrostedScaffold(
      // R11d: no GlassAppBar. The design opens on the machine's own picture at
      // full bleed (`App.tsx:3014-3040`) with the back control and the name
      // drawn over it; a bar above that repeats the name and costs 92px of the
      // only picture the screen has.
      body: eq.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(AppLocalizations.of(context).equipmentCouldNotLoad(e))),
        data: (item) {
          if (item == null) {
            return _NotFound(equipmentId: equipmentId);
          }
          return SmoothScrollList(
            padding: EdgeInsets.zero,
            children: [
              _EquipmentImmersiveHero(item: item),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              Text(
                '${CatalogLabels.manufacturer(AppLocalizations.of(context), item.manufacturer)}'
                ' · '
                '${CatalogLabels.category(AppLocalizations.of(context), item.category)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // The design's suitability signal (`App.tsx:3057-3065`), from the
              // screening that already runs for this machine's exercises rather
              // than from a new judgement about the machine itself.
              _SuitabilityCard(equipmentId: item.id),
              const SizedBox(height: 12),
              const _ToolsRow(),
              const SizedBox(height: 16),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).equipmentAbout, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(item.description,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppTertiaryButton(
                        icon: Icons.report_gmailerrorred_outlined,
                        label: AppLocalizations.of(context)
                            .equipmentReportBrokenEquipment,
                        onPressed: () async {
                          final sent = await EquipmentReportSheet.show(
                            context,
                            equipmentId: item.id,
                            equipmentName: item.name,
                          );
                          if (sent == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(AppLocalizations.of(context).equipmentReportSentToMaintenanceThanks),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // The visible AI: one tap, machine-specific technique advice in
              // the interface language. Recognition may also be cloud-backed,
              // but this is where the user can SEE an AI working for them.
              //
              // N04: hidden outright for a whole-person block rather than
              // shown-and-refused. The sheet's answer IS the prescription, so
              // an entry point that opens and then declines is a worse version
              // of the same offer -- and the refusal itself already has a
              // home, on the screens that state it with its reason.
              if (mayTrain)
                GlassCard(
                  key: const Key('equipment-ai-coach'),
                  onTap: () => AiCoachSheet.show(
                    context,
                    source: AiCoachSource.equipment,
                    subjectId: item.id,
                    subjectName: item.name,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context).aiCoachButton,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              AppLocalizations.of(context).aiCoachButtonHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).equipmentRecommendedExercises,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ...ex.when(
                loading: () => [const _ExerciseShimmer()],
                error: (e, _) => [
                  GlassCard(child: Text(AppLocalizations.of(context).equipmentCouldNotLoadExercises(e))),
                ],
                data: (rec) {
                  if (rec.items.isEmpty) {
                    // `hiddenForInjury > 0` is the only thing that may blame
                    // an injury here. It was reachable through a branch that
                    // could not fire -- with no exercise tagged, nothing is
                    // ever hidden -- so the empty list always meant the other
                    // thing and never said so.
                    return [
                      const SafetyDisclosure(compact: true),
                      GlassCard(
                        child: Text(
                          rec.hiddenForInjury > 0
                              ? AppLocalizations.of(context).equipmentAllConflictWithInjuries
                              : AppLocalizations.of(context).equipmentNoCuratedYet,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ];
                  }
                  final widgets = <Widget>[const SafetyDisclosure()];
                  if (rec.hiddenForInjury > 0) {
                    widgets.add(_FilteredHint(count: rec.hiddenForInjury));
                    widgets.add(const SizedBox(height: 12));
                  }
                  for (final e in rec.items) {
                    widgets.add(_ExerciseCard(exercise: e));
                    widgets.add(const SizedBox(height: 12));
                  }
                  return widgets;
                },
              ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The design's 240px machine header (`App.tsx:3014-3040`).
///
/// Same construction as `ExerciseImmersiveHero` and deliberately not shared
/// with it: the picture source differs (a provider lookup here, an asset path
/// on the model there) and the two heroes carry different chips. A common
/// widget taking six nullable parameters to serve both would be harder to read
/// than the eighty lines it saved.
class _EquipmentImmersiveHero extends ConsumerWidget {
  const _EquipmentImmersiveHero({required this.item});
  final EquipmentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;
    final hero = ref.watch(equipmentHeroImageProvider(item.id)).valueOrNull;
    final top = MediaQuery.paddingOf(context).top;

    final fallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.auroraViolet, AppPalette.auroraBlue],
        ),
      ),
      child: const Center(
        child: Icon(Icons.fitness_center,
            size: 56, color: AppSemanticColors.onGradientInk),
      ),
    );

    return SizedBox(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hero == null)
            fallback
          else if (hero.startsWith('http'))
            Image.network(
              hero,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : fallback,
            )
          else
            Image.asset(hero,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    colors.backgroundPrimary,
                    colors.backgroundPrimary.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 12,
            child: Material(
              color: colors.cameraOverlay,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => GoRouter.of(context).pop(),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Colors.white,
                      semanticLabel: l10n.commonBack),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Suits you" / "Check with a coach", from the injury screening that already
/// runs over this machine's curated exercises.
///
/// Deliberately NOT a claim about the machine. The app screens EXERCISES
/// against the user's logged injuries (`exercise_filter.dart`); saying a bench
/// "suits you" is shorthand for "everything we would put you on here passed
/// that screening". When something did not pass, the card says so and points
/// at a human rather than reassuring — a safety signal must not be the
/// cheerful default.
class _SuitabilityCard extends ConsumerWidget {
  const _SuitabilityCard({required this.equipmentId});
  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rec = ref.watch(recommendedExercisesProvider(equipmentId)).valueOrNull;
    // Nothing to say until the screening has actually run. An unresolved
    // provider rendering "suits you" would be the reassurance-by-default this
    // card exists to avoid.
    if (rec == null || rec.items.isEmpty) return const SizedBox.shrink();

    final flagged = rec.hiddenForInjury > 0;
    final tone = flagged ? theme.colors.warning : theme.colors.success;

    return Container(
      key: const Key('equipment.suitability'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            flagged
                ? Icons.report_problem_outlined
                : Icons.check_circle_outline_rounded,
            color: tone,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flagged
                      ? l10n.equipmentCheckWithCoach
                      : l10n.equipmentSuitableForYou,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: tone),
                ),
                const SizedBox(height: 2),
                Text(
                  flagged
                      ? l10n.equipmentCheckBecauseInjury
                      : l10n.equipmentSuitableBecause,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Machine thumbnail: a real photograph of the machine in use when the
/// catalog has one, the gradient-and-icon placeholder when it does not.
///
/// The placeholder is deliberately still there rather than hidden: 11
/// mostly-cardio machines have no vendored photo at all, and an empty slot
/// would read as a broken image.
// `_EquipmentThumb` (a 56px rounded tile in the old header card) lived here
// until R11d. Its one caller was the header the immersive hero replaced, and
// its picture logic — provider lookup, http-vs-asset branch, gradient
// fallback — moved into `_EquipmentImmersiveHero` unchanged. Deleted rather
// than kept: an unused widget rendering the same image at a different size is
// how "one design" becomes two.

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/exercise/${exercise.id}'),
      child: Row(
        children: [
          ExerciseThumb(exercise: exercise, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Transparency for the operator's "полностью заполняем
                    // карточку тренажёра" ask: real vendored exercises and
                    // AI-generated fallbacks must not look identical.
                    if (exercise.id.startsWith('ai::')) ...[
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 11, color: theme.colorScheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              AppLocalizations.of(context).equipmentAiTag,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      AppLocalizations.of(context).equipmentMin(exercise.durationMinutes),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  exercise.summary,
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

class _FilteredHint extends StatelessWidget {
  const _FilteredHint({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraBlue,
              ]),
            ),
            child: const Icon(Icons.health_and_safety_outlined,
                color: AppSemanticColors.onGradientInk, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).equipmentInjuryFilteredOut(count),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseShimmer extends StatelessWidget {
  const _ExerciseShimmer();
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

/// Plate-calculator + warm-up calculator chips. Identical UX to the
/// Workout Player's tools row — pulled here so users can pre-load
/// plates before starting a session.
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: const Column(
            children: [
              PlateCalculator(),
              SizedBox(height: 14),
              WarmupCalculator(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.fitness_center_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentPlates),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
        ActionChip(
          avatar:
              const Icon(Icons.local_fire_department_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentWarmUp),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.equipmentId});
  final String equipmentId;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_outlined, size: 60),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context).equipmentWeDonTHaveInOur(equipmentId),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context).equipmentTryScanningADifferentCodeOr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
