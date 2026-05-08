import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

class StepPersonal extends ConsumerWidget {
  const StepPersonal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personal = ref.watch(questionnaireDraftProvider).personal;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          title: 'Tell us about you',
          subtitle: 'We tailor your plan around these basics.',
          icon: Icons.person_outline,
          iconGradient: [AppPalette.auroraPink, AppPalette.auroraViolet],
        ),
        const FieldLabel('Age'),
        GlassTextField(
          value: personal.age?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '30',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(age: int.tryParse(v)),
          ),
        ),
        const FieldLabel('Gender'),
        SingleChoiceChips<Gender>(
          options: const [
            Gender.female,
            Gender.male,
            Gender.nonBinary,
            Gender.preferNotToSay
          ],
          labelOf: _genderLabel,
          value: personal.gender,
          onChanged: (g) =>
              notifier.updatePersonal((p) => p.copyWith(gender: g)),
        ),
        const FieldLabel('Height (cm)'),
        GlassTextField(
          value: personal.heightCm?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '175',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(heightCm: int.tryParse(v)),
          ),
        ),
        const FieldLabel('Current weight (kg)'),
        GlassTextField(
          value: personal.weightCurrentKg?.toString() ?? '',
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          hint: '72',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(weightCurrentKg: double.tryParse(v)),
          ),
        ),
        const FieldLabel('Target weight (kg, optional)'),
        GlassTextField(
          value: personal.weightTargetKg?.toString() ?? '',
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          hint: '70',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(weightTargetKg: double.tryParse(v)),
          ),
        ),
        const FieldLabel('Activity level'),
        SingleChoiceChips<ActivityLevel>(
          options: const [
            ActivityLevel.sedentary,
            ActivityLevel.moderatelyActive,
            ActivityLevel.active,
            ActivityLevel.veryActive,
          ],
          labelOf: _activityLabel,
          value: personal.activityLevel,
          onChanged: (a) =>
              notifier.updatePersonal((p) => p.copyWith(activityLevel: a)),
        ),
      ],
    );
  }
}

String _genderLabel(Gender g) => switch (g) {
      Gender.female => 'Female',
      Gender.male => 'Male',
      Gender.nonBinary => 'Non-binary',
      Gender.preferNotToSay => 'Prefer not to say',
    };

String _activityLabel(ActivityLevel a) => switch (a) {
      ActivityLevel.sedentary => 'Sedentary',
      ActivityLevel.moderatelyActive => 'Moderately active',
      ActivityLevel.active => 'Active',
      ActivityLevel.veryActive => 'Very active',
    };
