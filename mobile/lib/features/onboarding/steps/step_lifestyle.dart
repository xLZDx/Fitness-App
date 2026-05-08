import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

class StepLifestyle extends ConsumerWidget {
  const StepLifestyle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(questionnaireDraftProvider).lifestyle;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          title: 'Lifestyle & habits',
          subtitle: 'Recovery, nutrition, and stress all feed into your plan.',
          icon: Icons.restaurant_outlined,
          iconGradient: [AppPalette.auroraTeal, AppPalette.auroraLime],
        ),
        const FieldLabel('Dietary preferences'),
        MultiChoiceChips<DietaryPreference>(
          options: const [
            DietaryPreference.vegetarian,
            DietaryPreference.vegan,
            DietaryPreference.glutenFree,
            DietaryPreference.dairyFree,
            DietaryPreference.halal,
            DietaryPreference.kosher,
            DietaryPreference.none,
          ],
          labelOf: (d) => switch (d) {
            DietaryPreference.vegetarian => 'Vegetarian',
            DietaryPreference.vegan => 'Vegan',
            DietaryPreference.glutenFree => 'Gluten-free',
            DietaryPreference.dairyFree => 'Dairy-free',
            DietaryPreference.halal => 'Halal',
            DietaryPreference.kosher => 'Kosher',
            DietaryPreference.none => 'No restrictions',
          },
          values: l.diet.toSet(),
          onChanged: (next) =>
              notifier.updateLifestyle((s) => s.copyWith(diet: next.toList())),
        ),
        const FieldLabel('Smoking'),
        SingleChoiceChips<SmokingHabit>(
          options: const [
            SmokingHabit.never,
            SmokingHabit.former,
            SmokingHabit.occasional,
            SmokingHabit.regular,
          ],
          labelOf: (s) => switch (s) {
            SmokingHabit.never => 'Never',
            SmokingHabit.former => 'Former',
            SmokingHabit.occasional => 'Occasional',
            SmokingHabit.regular => 'Regular',
          },
          value: l.smoking,
          onChanged: (s) =>
              notifier.updateLifestyle((st) => st.copyWith(smoking: s)),
        ),
        const FieldLabel('Alcohol'),
        SingleChoiceChips<AlcoholHabit>(
          options: const [
            AlcoholHabit.none,
            AlcoholHabit.light,
            AlcoholHabit.moderate,
            AlcoholHabit.heavy,
          ],
          labelOf: (a) => switch (a) {
            AlcoholHabit.none => 'None',
            AlcoholHabit.light => 'Light',
            AlcoholHabit.moderate => 'Moderate',
            AlcoholHabit.heavy => 'Heavy',
          },
          value: l.alcohol,
          onChanged: (a) =>
              notifier.updateLifestyle((st) => st.copyWith(alcohol: a)),
        ),
        const FieldLabel('Sleep (hours per night)'),
        GlassTextField(
          value: l.sleepHoursPerNight?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '7',
          onChanged: (v) => notifier.updateLifestyle(
            (s) => s.copyWith(sleepHoursPerNight: int.tryParse(v)),
          ),
        ),
        const FieldLabel('Stress level (1–10)'),
        Slider(
          min: 1,
          max: 10,
          divisions: 9,
          value: (l.stressLevel ?? 5).toDouble(),
          label: '${l.stressLevel ?? 5}',
          onChanged: (v) => notifier.updateLifestyle(
            (s) => s.copyWith(stressLevel: v.round()),
          ),
        ),
        const FieldLabel('Occupation'),
        SingleChoiceChips<OccupationActivity>(
          options: const [
            OccupationActivity.sedentary,
            OccupationActivity.lightlyActive,
            OccupationActivity.active,
            OccupationActivity.veryActive,
          ],
          labelOf: (o) => switch (o) {
            OccupationActivity.sedentary => 'Sedentary',
            OccupationActivity.lightlyActive => 'Lightly active',
            OccupationActivity.active => 'Active',
            OccupationActivity.veryActive => 'Very active',
          },
          value: l.occupation,
          onChanged: (o) =>
              notifier.updateLifestyle((st) => st.copyWith(occupation: o)),
        ),
      ],
    );
  }
}
