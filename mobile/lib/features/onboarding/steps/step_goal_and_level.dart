import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../profile/data/profile_models.dart';
import '../../programmes/data/programme.dart' show ProgrammeGoal;
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

/// O3 — screen 1 of the flow: the main goal, then the starting point.
///
/// ## Why two former screens are one
///
/// The design puts both on its first screen (`App.tsx:2387-2409`) and the
/// operator's instruction was to follow it. It also happens to be the right
/// shape: "what do you want" and "where are you now" are the two halves of one
/// question — a plan needs both or neither, and answering one without the other
/// produces nothing usable.
///
/// ## What did NOT move here
///
/// The old level screen also asked how many sessions a week the user trains
/// *now* and what exercises they already do. Those stay on this screen rather
/// than moving to O5's schedule: they describe the present, and O5 asks about
/// intent. Merging the two would destroy the only baseline a plan generator has
/// for judging how big a jump it is proposing.
///
/// The multi-select "what else interests you" list also stays. It is not a
/// duplicate of the primary goal — see [FitnessGoals.primary].
class StepGoalAndLevel extends ConsumerWidget {
  const StepGoalAndLevel({super.key});

  static const _goals = <ProgrammeGoal>[
    ProgrammeGoal.weightLoss,
    ProgrammeGoal.muscle,
    ProgrammeGoal.strength,
    ProgrammeGoal.endurance,
    ProgrammeGoal.form,
    ProgrammeGoal.comeback,
  ];

  static const _tiers = <FitnessTier>[
    FitnessTier.never,
    FitnessTier.beginner,
    FitnessTier.intermediate,
    FitnessTier.advanced,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(questionnaireDraftProvider);
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final goals = draft.goals;
    final level = draft.level;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnbRefTitle(
          title: l10n.onbGoalTitle,
          subtitle: l10n.onbGoalSubtitle,
        ),
        const SizedBox(height: 18),
        for (final g in _goals) ...[
          ChoiceCard(
            key: Key('onb.goal.${g.name}'),
            title: _goalTitle(l10n, g),
            subtitle: _goalSubtitle(l10n, g),
            icon: _goalIcon(g),
            selected: goals.primary == g,
            onTap: () => notifier.updateGoals((s) => s.copyWith(primary: g)),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 14),
        OnbRefTitle(
          title: l10n.onbLevelTitle,
          subtitle: l10n.onbLevelSubtitle,
        ),
        const SizedBox(height: 14),
        for (final (i, t) in _tiers.indexed) ...[
          ChoiceCard(
            key: Key('onb.tier.${t.name}'),
            title: _tierTitle(l10n, t),
            subtitle: _tierSubtitle(l10n, t),
            leading: TierDial(number: i + 1, selected: level.tier == t),
            selected: level.tier == t,
            onTap: () => notifier.updateLevel((s) => s.copyWith(tier: t)),
          ),
          const SizedBox(height: 10),
        ],
        // Kept from the old level screen, kept as free text, and kept OFF the
        // cards above: it is context for a coach, not an answer that selects a
        // programme, and pretending otherwise would mean inventing categories
        // for it.
        FieldLabel(l10n.onbCurrentExercises),
        GlassTextField(
          value: level.currentExercises.join(', '),
          maxLines: 2,
          hint: l10n.onbCurrentExercisesHint,
          onChanged: (v) => notifier.updateLevel(
            (s) => s.copyWith(currentExercises: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbSessionsPerWeek),
        GlassTextField(
          value: level.frequencyPerWeek?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '3',
          onChanged: (v) => notifier.updateLevel(
            (s) => s.copyWith(frequencyPerWeek: int.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbOtherGoals),
        MultiChoiceChips<_SecondaryGoal>(
          options: _SecondaryGoal.values,
          labelOf: (k) => switch (k) {
            _SecondaryGoal.weightLoss => l10n.onbGoalWeightLoss,
            _SecondaryGoal.muscleGain => l10n.onbGoalMuscleGain,
            _SecondaryGoal.endurance => l10n.onbGoalEndurance,
            _SecondaryGoal.strength => l10n.onbGoalStrength,
            _SecondaryGoal.flexibility => l10n.onbGoalFlexibility,
            _SecondaryGoal.generalFitness => l10n.onbGoalGeneral,
          },
          values: {
            if (goals.weightLoss) _SecondaryGoal.weightLoss,
            if (goals.muscleGain) _SecondaryGoal.muscleGain,
            if (goals.endurance) _SecondaryGoal.endurance,
            if (goals.strength) _SecondaryGoal.strength,
            if (goals.flexibility) _SecondaryGoal.flexibility,
            if (goals.generalFitness) _SecondaryGoal.generalFitness,
          },
          onChanged: (next) => notifier.updateGoals((g) => g.copyWith(
                weightLoss: next.contains(_SecondaryGoal.weightLoss),
                muscleGain: next.contains(_SecondaryGoal.muscleGain),
                endurance: next.contains(_SecondaryGoal.endurance),
                strength: next.contains(_SecondaryGoal.strength),
                flexibility: next.contains(_SecondaryGoal.flexibility),
                generalFitness: next.contains(_SecondaryGoal.generalFitness),
              )),
        ),
        FieldLabel(l10n.onbSport),
        GlassTextField(
          value: goals.specificSport ?? '',
          hint: l10n.onbSportHint,
          onChanged: (v) =>
              notifier.updateGoals((g) => g.copyWith(specificSport: v)),
        ),
      ],
    );
  }
}

/// The six booleans of [FitnessGoals], as one thing a chip row can select over.
///
/// Private and local: it exists so a `Set` can drive the chips, and it maps
/// one-to-one onto fields that already exist. Promoting it to a real enum in
/// the model would create a second vocabulary for goals, which is exactly what
/// [ProgrammeGoal] was extended to avoid.
enum _SecondaryGoal {
  weightLoss,
  muscleGain,
  endurance,
  strength,
  flexibility,
  generalFitness,
}

List<String> _splitTags(String input) => input
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String _goalTitle(AppLocalizations l, ProgrammeGoal g) => switch (g) {
      ProgrammeGoal.strength => l.onbGoalCardStrength,
      ProgrammeGoal.muscle => l.onbGoalCardMuscle,
      ProgrammeGoal.weightLoss => l.onbGoalCardWeightLoss,
      ProgrammeGoal.form => l.onbGoalCardForm,
      ProgrammeGoal.comeback => l.onbGoalCardComeback,
      ProgrammeGoal.endurance => l.onbGoalCardEndurance,
    };

String _goalSubtitle(AppLocalizations l, ProgrammeGoal g) => switch (g) {
      ProgrammeGoal.strength => l.onbGoalCardStrengthSub,
      ProgrammeGoal.muscle => l.onbGoalCardMuscleSub,
      ProgrammeGoal.weightLoss => l.onbGoalCardWeightLossSub,
      ProgrammeGoal.form => l.onbGoalCardFormSub,
      ProgrammeGoal.comeback => l.onbGoalCardComebackSub,
      ProgrammeGoal.endurance => l.onbGoalCardEnduranceSub,
    };

IconData _goalIcon(ProgrammeGoal g) => switch (g) {
      ProgrammeGoal.strength => Icons.fitness_center_rounded,
      ProgrammeGoal.muscle => Icons.accessibility_new_rounded,
      ProgrammeGoal.weightLoss => Icons.local_fire_department_rounded,
      ProgrammeGoal.form => Icons.self_improvement_rounded,
      ProgrammeGoal.comeback => Icons.replay_rounded,
      ProgrammeGoal.endurance => Icons.directions_run_rounded,
    };

String _tierTitle(AppLocalizations l, FitnessTier t) => switch (t) {
      FitnessTier.never => l.onbLevelNever,
      FitnessTier.beginner => l.onbLevelBeginner,
      FitnessTier.intermediate => l.onbLevelIntermediate,
      FitnessTier.advanced => l.onbLevelAdvanced,
    };

String _tierSubtitle(AppLocalizations l, FitnessTier t) => switch (t) {
      FitnessTier.never => l.onbLevelNeverSub,
      FitnessTier.beginner => l.onbLevelBeginnerSub,
      FitnessTier.intermediate => l.onbLevelIntermediateSub,
      FitnessTier.advanced => l.onbLevelAdvancedSub,
    };
