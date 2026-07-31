import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

class StepPersonal extends ConsumerWidget {
  const StepPersonal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final personal = ref.watch(questionnaireDraftProvider).personal;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingTellUsAboutYou,
          subtitle: AppLocalizations.of(context)
              .onboardingWeTailorYourPlanAroundThese,
          icon: Icons.person_outline,
          iconGradient: [AppPalette.auroraPink, AppPalette.auroraViolet],
        ),
        FieldLabel(l10n.onbAge),
        GlassTextField(
          value: personal.age?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '30',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(age: int.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbGender),
        SingleChoiceChips<Gender>(
          options: const [
            Gender.female,
            Gender.male,
            Gender.nonBinary,
            Gender.preferNotToSay
          ],
          labelOf: (g) => _genderLabel(l10n, g),
          value: personal.gender,
          onChanged: (g) =>
              notifier.updatePersonal((p) => p.copyWith(gender: g)),
        ),
        FieldLabel(l10n.onbHeightCm),
        GlassTextField(
          value: personal.heightCm?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '175',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(heightCm: int.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbWeightCurrent),
        GlassTextField(
          value: personal.weightCurrentKg?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: '72',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(weightCurrentKg: double.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbWeightTarget),
        GlassTextField(
          value: personal.weightTargetKg?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: '70',
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(weightTargetKg: double.tryParse(v)),
          ),
        ),
        FieldLabel(l10n.onbActivityLevel),
        SingleChoiceChips<ActivityLevel>(
          options: const [
            ActivityLevel.sedentary,
            ActivityLevel.moderatelyActive,
            ActivityLevel.active,
            ActivityLevel.veryActive,
          ],
          labelOf: (a) => _activityLabel(l10n, a),
          value: personal.activityLevel,
          onChanged: (a) =>
              notifier.updatePersonal((p) => p.copyWith(activityLevel: a)),
        ),
      ],
    );
  }
}

// The label functions take the localizations object rather than reading it
// from a context: they are top-level, so there is no context to read.
String _genderLabel(AppLocalizations l10n, Gender g) => switch (g) {
      Gender.female => l10n.onbGenderFemale,
      Gender.male => l10n.onbGenderMale,
      Gender.nonBinary => l10n.onbGenderNonBinary,
      Gender.preferNotToSay => l10n.onbGenderPreferNotToSay,
    };

String _activityLabel(AppLocalizations l10n, ActivityLevel a) => switch (a) {
      ActivityLevel.sedentary => l10n.onbActivitySedentary,
      ActivityLevel.moderatelyActive => l10n.onbActivityModerate,
      ActivityLevel.active => l10n.onbActivityActive,
      ActivityLevel.veryActive => l10n.onbActivityVery,
    };
