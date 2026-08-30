import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../safety/data/health_flags.dart';
import '../../safety/widgets/eligibility_notice.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

/// Gate N — the health answers in a form a rule may act on.
///
/// ## Why this screen exists next to the free-text one
///
/// `step_health.dart` asks for conditions, allergies, medications, surgeries
/// and limitations as free text. Those answers were collected from the first
/// release, stored device-local, and read by nothing at all: only `injuries`
/// ever reached the exercise filter.
///
/// The tempting repair is to parse them. Gate M ruled that out — turning
/// "metoprolol" into a drug class and a drug class into a plan change is
/// clinical reasoning done by string matching, wrong in both directions and
/// silent. So the text is kept exactly as the user typed it, for them and for
/// anyone they show it to, and the same ground is covered again here with
/// closed answers.
///
/// The two screens are not redundant. One holds what the user wants recorded;
/// this one holds what the app is allowed to act on. Merging them would put a
/// free-text box next to a chip row and invite exactly the parsing this
/// forbids.
///
/// ## The legacy notice
///
/// A user who filled the old screen in and has not answered this one is in
/// [HealthNormalisationState.legacyUnreviewed]: the app holds health
/// information it must not read, and none it may. It says so rather than
/// guessing at the text or pretending the fields were never filled in.
class StepHealthFlags extends ConsumerWidget {
  const StepHealthFlags({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final health = ref.watch(questionnaireDraftProvider).health;
    final flags = health.flags;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    void update(HealthFlags Function(HealthFlags) f) =>
        notifier.updateHealth((h) => h.copyWith(flags: f(h.flags)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnbRefTitle(
          title: l10n.healthStepTitle,
          subtitle: l10n.healthStepIntro,
        ),
        if (health.normalisation == HealthNormalisationState.legacyUnreviewed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.healthLegacyNotice,
              key: const Key('onb.flags.legacy'),
              style: HudType.body(t, size: 12.5).overPhoto(t),
            ),
          ),
        const SizedBox(height: 16),
        FieldLabel(l10n.healthStepRestrictions),
        MultiChoiceChips<MovementRestriction>(
          key: const Key('onb.flags.restrictions'),
          options: MovementRestriction.values,
          labelOf: (r) => movementRestrictionText(l10n, r),
          values: flags.restrictions,
          onChanged: (next) => update((f) => f.copyWith(restrictions: next)),
        ),
        // Said here, on the screen where the choice is made, rather than only
        // at the point of refusal. A user who picks "jumping and landing" is
        // owed the fact that we cannot screen for it while they can still
        // decide what else to tell us.
        if (flags.unenforceableRestrictions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: EligibilityNotice(
              key: const Key('onb.flags.unscreenable'),
              reasons: [
                for (final r in flags.unenforceableRestrictions)
                  EligibilityReasonFor.unscreenable(r),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FieldLabel(l10n.healthStepBloodPressure),
        SingleChoiceChips<BloodPressureStatus>(
          key: const Key('onb.flags.bp'),
          options: BloodPressureStatus.values,
          labelOf: (v) => switch (v) {
            BloodPressureStatus.noKnownIssue => l10n.bpNoKnownIssue,
            BloodPressureStatus.diagnosedLow => l10n.bpDiagnosedLow,
            BloodPressureStatus.diagnosedHigh => l10n.bpDiagnosedHigh,
            BloodPressureStatus.managedWithClinician =>
              l10n.bpManagedWithClinician,
            BloodPressureStatus.unsure => l10n.bpUnsure,
          },
          value: flags.bloodPressure,
          onChanged: (v) => update((f) => f.copyWith(bloodPressure: v)),
        ),
        const SizedBox(height: 16),
        FieldLabel(l10n.healthStepSurgery),
        SingleChoiceChips<SurgeryStatus>(
          key: const Key('onb.flags.surgery'),
          options: SurgeryStatus.values,
          labelOf: (v) => switch (v) {
            SurgeryStatus.none => l10n.surgeryNone,
            SurgeryStatus.underRestrictions => l10n.surgeryUnderRestrictions,
            SurgeryStatus.clearedForNormalExercise =>
              l10n.surgeryClearedForNormalExercise,
            SurgeryStatus.unsure => l10n.surgeryUnsure,
          },
          value: flags.surgery,
          onChanged: (v) => update((f) => f.copyWith(surgery: v)),
        ),
        const SizedBox(height: 16),
        FieldLabel(l10n.healthStepClinician),
        SingleChoiceChips<ClinicianExerciseAdvice>(
          key: const Key('onb.flags.advice'),
          options: ClinicianExerciseAdvice.values,
          labelOf: (v) => switch (v) {
            ClinicianExerciseAdvice.noLimitsGiven => l10n.adviceNoLimitsGiven,
            ClinicianExerciseAdvice.limitsGiven => l10n.adviceLimitsGiven,
            ClinicianExerciseAdvice.advisedAgainstExercise =>
              l10n.adviceAdvisedAgainstExercise,
            ClinicianExerciseAdvice.notAsked => l10n.adviceNotAsked,
          },
          value: flags.clinicianAdvice,
          onChanged: (v) => update((f) => f.copyWith(clinicianAdvice: v)),
        ),
        const SizedBox(height: 16),
        // F014. Last, and a plain yes/no, because it is the only question here
        // whose answer does not describe a limitation the user lives with --
        // it describes a limitation of THIS APP. Offering "unsure" would be
        // asking someone to be uncertain about something they are not
        // uncertain about, and offering more granularity would collect a
        // medical detail nothing acts on. See `ProfessionalGuidanceNeed`.
        FieldLabel(l10n.healthStepProfessionalGuidance),
        SingleChoiceChips<ProfessionalGuidanceNeed>(
          key: const Key('onb.flags.guidance'),
          options: ProfessionalGuidanceNeed.values,
          labelOf: (v) => switch (v) {
            ProfessionalGuidanceNeed.none => l10n.guidanceNeedNone,
            ProfessionalGuidanceNeed.reported => l10n.guidanceNeedReported,
          },
          value: flags.professionalGuidance,
          onChanged: (v) =>
              update((f) => f.copyWith(professionalGuidance: v)),
        ),
      ],
    );
  }
}
