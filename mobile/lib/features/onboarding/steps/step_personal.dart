import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/body_metric_cards.dart';
import '../widgets/inputs.dart';
import '../widgets/measure_ruler.dart';

class StepPersonal extends ConsumerWidget {
  const StepPersonal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final personal = ref.watch(questionnaireDraftProvider).personal;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingTellUsAboutYou,
          subtitle: AppLocalizations.of(context)
              .onboardingWeTailorYourPlanAroundThese,
        ),
        // O8: the year of birth, on the same scale control as height and
        // weight, replacing a number field that asked for an age. An age is
        // true for one year; a birth year stays true. The scale also cannot
        // produce the 300-year-old a text field accepts without complaint.
        FieldLabel(l10n.onbBirthYear),
        MeasureRuler(
          key: const Key('onb.birthYearRuler'),
          value: personal.birthYear?.toDouble(),
          // The floor is a plausible oldest user rather than an arbitrary round
          // number; the ceiling is "old enough to train", which the app has to
          // assume anyway.
          min: 1930,
          max: (DateTime.now().year - 12).toDouble(),
          majorEvery: 10,
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(birthYear: v.round()),
          ),
        ),
        // Stated, not hidden. The month has never been asked, so anyone born
        // later in the year reads a year older until their birthday, and the
        // person best placed to notice that is the one reading it.
        if (personal.birthYear != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.onbAgeApprox(personal.age ?? 0),
              style: HudType.body(t, size: 12).overPhoto(t),
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
        // R11b: rulers, not number fields. The design uses a scale for all
        // three of these, and the reason is not decoration -- a ruler cannot
        // produce 1750 cm, cannot be left half-typed, and shows the
        // neighbouring values so someone unsure between 72 and 73 sees both.
        // A number field's failure modes are all silent.
        // Chrome only: the reference's slider cards wrap each measure in a
        // glass panel (`full_handoff_v1/...dc.html`, L122-148). `MeasureRuler`
        // itself -- drag math, snapping, ticks, values, keys -- is unchanged;
        // only the height/weight rows gain this wrapper, per GPT-PM's
        // Phase-1 boundary ("MeasureRuler behavior... frozen"). Birth year
        // and target weight stay bare, out of this gate's scope.
        HudPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(l10n.onbHeightCm),
              MeasureRuler(
                key: const Key('onb.heightRuler'),
                value: personal.heightCm?.toDouble(),
                min: 120,
                max: 220,
                unit: l10n.onbUnitCm,
                onChanged: (v) => notifier.updatePersonal(
                  (p) => p.copyWith(heightCm: v.round()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HudPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(l10n.onbWeightCurrent),
              MeasureRuler(
                key: const Key('onb.weightRuler'),
                value: personal.weightCurrentKg,
                min: 35,
                max: 200,
                step: 0.5,
                majorEvery: 10,
                unit: l10n.onbUnitKg,
                onChanged: (v) => notifier.updatePersonal(
                  (p) => p.copyWith(weightCurrentKg: v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BmiCard(
          heightCm: personal.heightCm,
          weightKg: personal.weightCurrentKg,
        ),
        FieldLabel(l10n.onbWeightTarget),
        MeasureRuler(
          key: const Key('onb.targetRuler'),
          value: personal.weightTargetKg,
          min: 35,
          max: 200,
          step: 0.5,
          majorEvery: 10,
          unit: l10n.onbUnitKg,
          onChanged: (v) => notifier.updatePersonal(
            (p) => p.copyWith(weightTargetKg: v),
          ),
        ),
        const SizedBox(height: 12),
        WeightDeltaCard(
          currentKg: personal.weightCurrentKg,
          targetKg: personal.weightTargetKg,
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
