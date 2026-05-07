import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

enum _GoalKey {
  weightLoss,
  muscleGain,
  endurance,
  strength,
  flexibility,
  generalFitness,
}

class StepGoals extends ConsumerWidget {
  const StepGoals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(questionnaireDraftProvider).goals;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    final selected = <_GoalKey>{
      if (goals.weightLoss) _GoalKey.weightLoss,
      if (goals.muscleGain) _GoalKey.muscleGain,
      if (goals.endurance) _GoalKey.endurance,
      if (goals.strength) _GoalKey.strength,
      if (goals.flexibility) _GoalKey.flexibility,
      if (goals.generalFitness) _GoalKey.generalFitness,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          title: 'What do you want to work on?',
          subtitle: 'Pick as many as you like.',
        ),
        const SizedBox(height: 18),
        MultiChoiceChips<_GoalKey>(
          options: const [
            _GoalKey.weightLoss,
            _GoalKey.muscleGain,
            _GoalKey.endurance,
            _GoalKey.strength,
            _GoalKey.flexibility,
            _GoalKey.generalFitness,
          ],
          labelOf: (k) => switch (k) {
            _GoalKey.weightLoss => 'Weight loss',
            _GoalKey.muscleGain => 'Muscle gain',
            _GoalKey.endurance => 'Endurance',
            _GoalKey.strength => 'Strength',
            _GoalKey.flexibility => 'Flexibility',
            _GoalKey.generalFitness => 'General fitness',
          },
          values: selected,
          onChanged: (next) => notifier.updateGoals((g) => g.copyWith(
                weightLoss: next.contains(_GoalKey.weightLoss),
                muscleGain: next.contains(_GoalKey.muscleGain),
                endurance: next.contains(_GoalKey.endurance),
                strength: next.contains(_GoalKey.strength),
                flexibility: next.contains(_GoalKey.flexibility),
                generalFitness: next.contains(_GoalKey.generalFitness),
              )),
        ),
        const FieldLabel('Specific sport (optional)'),
        GlassTextField(
          value: goals.specificSport ?? '',
          hint: 'e.g. tennis, climbing, marathon',
          onChanged: (v) =>
              notifier.updateGoals((g) => g.copyWith(specificSport: v)),
        ),
      ],
    );
  }
}
