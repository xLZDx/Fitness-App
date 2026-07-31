import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

class StepLifestyle extends ConsumerWidget {
  const StepLifestyle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final l = ref.watch(questionnaireDraftProvider).lifestyle;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingLifestyleHabits,
          subtitle: AppLocalizations.of(context)
              .onboardingRecoveryNutritionAndStressAllFeed,
          icon: Icons.restaurant_outlined,
          iconGradient: [AppPalette.auroraTeal, AppPalette.auroraLime],
        ),
        FieldLabel(l10n.onbDiet),
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
            DietaryPreference.vegetarian => l10n.onbDietVegetarian,
            DietaryPreference.vegan => l10n.onbDietVegan,
            DietaryPreference.glutenFree => l10n.onbDietGlutenFree,
            DietaryPreference.dairyFree => l10n.onbDietDairyFree,
            DietaryPreference.halal => l10n.onbDietHalal,
            DietaryPreference.kosher => l10n.onbDietKosher,
            DietaryPreference.none => l10n.onbDietNone,
          },
          values: l.diet.toSet(),
          onChanged: (next) =>
              notifier.updateLifestyle((s) => s.copyWith(diet: next.toList())),
        ),
        FieldLabel(l10n.onbSmoking),
        SingleChoiceChips<SmokingHabit>(
          options: const [
            SmokingHabit.never,
            SmokingHabit.former,
            SmokingHabit.occasional,
            SmokingHabit.regular,
          ],
          labelOf: (s) => switch (s) {
            SmokingHabit.never => l10n.onbSmokingNever,
            SmokingHabit.former => l10n.onbSmokingFormer,
            SmokingHabit.occasional => l10n.onbSmokingOccasional,
            SmokingHabit.regular => l10n.onbSmokingRegular,
          },
          value: l.smoking,
          onChanged: (s) =>
              notifier.updateLifestyle((st) => st.copyWith(smoking: s)),
        ),
        FieldLabel(l10n.onbAlcohol),
        SingleChoiceChips<AlcoholHabit>(
          options: const [
            AlcoholHabit.none,
            AlcoholHabit.light,
            AlcoholHabit.moderate,
            AlcoholHabit.heavy,
          ],
          labelOf: (a) => switch (a) {
            AlcoholHabit.none => l10n.onbAlcoholNone,
            AlcoholHabit.light => l10n.onbAlcoholLight,
            AlcoholHabit.moderate => l10n.onbAlcoholModerate,
            AlcoholHabit.heavy => l10n.onbAlcoholHeavy,
          },
          value: l.alcohol,
          onChanged: (a) =>
              notifier.updateLifestyle((st) => st.copyWith(alcohol: a)),
        ),
        FieldLabel(l10n.onbSleepHours),
        GlassTextField(
          value: l.sleepHoursPerNight?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '7',
          onChanged: (v) => notifier.updateLifestyle(
            (s) => s.copyWith(sleepHoursPerNight: int.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbStressLevel),
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
        FieldLabel(l10n.onbOccupation),
        SingleChoiceChips<OccupationActivity>(
          options: const [
            OccupationActivity.sedentary,
            OccupationActivity.lightlyActive,
            OccupationActivity.active,
            OccupationActivity.veryActive,
          ],
          labelOf: (o) => switch (o) {
            OccupationActivity.sedentary => l10n.onbActivitySedentary,
            OccupationActivity.lightlyActive => l10n.onbActivityLight,
            OccupationActivity.active => l10n.onbActivityActive,
            OccupationActivity.veryActive => l10n.onbActivityVery,
          },
          value: l.occupation,
          onChanged: (o) =>
              notifier.updateLifestyle((st) => st.copyWith(occupation: o)),
        ),
      ],
    );
  }
}
