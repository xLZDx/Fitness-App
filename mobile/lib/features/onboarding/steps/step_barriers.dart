import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

/// Applies the one rule [TrainingBarrier.none] carries: it cannot be held
/// together with a barrier.
///
/// Whichever of the two was just tapped wins, so the control never argues with
/// the tap — picking "nothing stops me" clears the list, and naming a barrier
/// afterwards drops "nothing stops me". A pure function so the rule can be
/// asserted without a widget.
List<TrainingBarrier> resolveBarrierSelection(
  Set<TrainingBarrier> next,
  Set<TrainingBarrier> previous,
) {
  final justAdded = next.difference(previous);
  final Set<TrainingBarrier> chosen;
  if (justAdded.contains(TrainingBarrier.none)) {
    chosen = {TrainingBarrier.none};
  } else if (justAdded.isNotEmpty) {
    // A real barrier was named: "nothing stops me" can no longer be true.
    chosen = {...next}..remove(TrainingBarrier.none);
  } else {
    // Nothing was added — this is a de-selection, and de-selecting one chip is
    // no reason to silently drop another.
    chosen = next;
  }
  return [
    // Enum order, not tap order: the list is persisted and compared, and two
    // identical answers must not serialise differently. Same rule as O4's kit.
    for (final b in TrainingBarrier.values)
      if (chosen.contains(b)) b,
  ];
}

/// O7 — what gets in the way.
///
/// Replaced the "motivation" screen rather than being added beside it. That
/// screen's real question was already this one, asked as free text; the text
/// box survives underneath for what the closed set cannot hold, on the same
/// principle as O4's equipment field.
class StepBarriers extends ConsumerWidget {
  const StepBarriers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final m = ref.watch(questionnaireDraftProvider).motivation;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: l10n.onbBarriersTitle,
          subtitle: l10n.onbBarriersSubtitle,
        ),
        const SizedBox(height: 8),
        MultiChoiceChips<TrainingBarrier>(
          options: TrainingBarrier.values,
          labelOf: (b) => _barrierLabel(l10n, b),
          values: m.barriers.toSet(),
          onChanged: (next) => notifier.updateMotivation(
            (s) => s.copyWith(
              barriers: resolveBarrierSelection(next, m.barriers.toSet()),
            ),
          ),
        ),
        FieldLabel(l10n.onbEnvironment),
        MultiChoiceChips<WorkoutEnvironment>(
          options: const [
            WorkoutEnvironment.highIntensity,
            WorkoutEnvironment.relaxed,
            WorkoutEnvironment.groupClasses,
            WorkoutEnvironment.oneOnOne,
            WorkoutEnvironment.outdoor,
          ],
          labelOf: (e) => switch (e) {
            WorkoutEnvironment.highIntensity => l10n.onbEnvIntense,
            WorkoutEnvironment.relaxed => l10n.onbEnvRelaxed,
            WorkoutEnvironment.groupClasses => l10n.onbEnvGroup,
            WorkoutEnvironment.oneOnOne => l10n.onbEnvOneOnOne,
            WorkoutEnvironment.outdoor => l10n.onbEnvOutdoor,
          },
          values: m.environments.toSet(),
          onChanged: (next) => notifier.updateMotivation(
            (s) => s.copyWith(environments: next.toList()),
          ),
        ),
        FieldLabel(l10n.onbMotivationPrompt),
        GlassTextField(
          value: m.motivation ?? '',
          maxLines: 3,
          hint: l10n.onbMotivationHint,
          onChanged: (v) => notifier.updateMotivation(
            (s) => s.copyWith(motivation: v),
          ),
        ),
      ],
    );
  }
}

String _barrierLabel(AppLocalizations l, TrainingBarrier b) => switch (b) {
      TrainingBarrier.exerciseChoice => l.onbBarrierExerciseChoice,
      TrainingBarrier.machineUse => l.onbBarrierMachineUse,
      TrainingBarrier.techniqueDoubt => l.onbBarrierTechniqueDoubt,
      TrainingBarrier.time => l.onbBarrierTime,
      TrainingBarrier.consistency => l.onbBarrierConsistency,
      TrainingBarrier.discomfort => l.onbBarrierDiscomfort,
      TrainingBarrier.none => l.onbBarrierNone,
    };
