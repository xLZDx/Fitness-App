import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

List<String> _splitTags(String input) => input
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String _joinTags(List<String> values) => values.join(', ');

/// Reads the injuries box, keeping entries that do not match "part: type".
///
/// P4-lite. This used to be `.where((s) => s.contains(':'))`, which discarded
/// every entry that did not carry a colon — so someone who typed "колено болит"
/// saw their words sitting in a filled-looking field while nothing at all
/// reached the profile. No error, no empty box, no way to notice.
///
/// An unparsed entry is now kept as an injury with an empty type. That is what
/// the user actually said, and `Injury.region` stays null, which already means
/// "nobody has mapped this yet" rather than "screened and safe".
///
/// **This does not make anything safer today, and should not be sold as if it
/// did.** `exercise_filter.dart` currently screens 0 of 1,887 exercises because
/// the catalogue carries no contraindication tags. The change makes the data
/// worth having by the time those tags exist.
///
/// [previous] is the list being edited. Since O6 an injury can carry a
/// [InjuryRegion] that was set by tapping the body map, and that region is not
/// in the text — rebuilding purely from the string would silently strip it the
/// first time anyone typed in this box.
List<Injury> parseInjuryInput(String input, [List<Injury> previous = const []]) {
  Injury? priorFor(String bodyPart) {
    final key = bodyPart.toLowerCase();
    for (final i in previous) {
      if (i.bodyPart.trim().toLowerCase() == key) return i;
    }
    return null;
  }

  final out = <Injury>[];
  for (final entry in input.split(',')) {
    if (entry.trim().isEmpty) continue;
    final colon = entry.indexOf(':');
    final bodyPart = (colon < 0 ? entry : entry.substring(0, colon)).trim();
    final type = colon < 0 ? '' : entry.substring(colon + 1).trim();
    final prior = priorFor(bodyPart);
    out.add(Injury(
      bodyPart: bodyPart,
      type: type,
      region: prior?.region,
      note: prior?.note,
      confirmed: prior?.confirmed ?? false,
    ));
  }
  return out;
}

/// The injuries box's text, from the stored list.
///
/// An entry with no type prints as just the body part: "колено болит: " would
/// put a colon the user never typed into their own words, and the next keystroke
/// would parse it back as a type of "".
String formatInjuryInput(List<Injury> injuries) => injuries
    .map((i) => i.type.isEmpty ? i.bodyPart : '${i.bodyPart}: ${i.type}')
    .join(', ');

class StepHealth extends ConsumerWidget {
  const StepHealth({super.key, this.showTitle = true});

  /// False when this is rendered inside O6's medical disclosure, which already
  /// carries a heading of its own. The fields themselves are untouched — the
  /// operator's instruction was that this screen is convenient as it is, so it
  /// moved without being rewritten.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final h = ref.watch(questionnaireDraftProvider).health;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          StepTitle(
            title: AppLocalizations.of(context).onboardingHealthSnapshot,
            subtitle: AppLocalizations.of(context).onboardingWeUseThisToKeepYour,
          ),
        FieldLabel(l10n.onbConditions),
        GlassTextField(
          value: _joinTags(h.conditions),
          maxLines: 2,
          hint: l10n.onbConditionsHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(conditions: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbAllergies),
        GlassTextField(
          value: _joinTags(h.allergies),
          maxLines: 2,
          hint: l10n.onbAllergiesHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(allergies: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbMedications),
        GlassTextField(
          value: _joinTags(h.medications),
          maxLines: 2,
          hint: l10n.onbMedicationsHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(medications: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbInjuries),
        GlassTextField(
          value: formatInjuryInput(h.injuries),
          maxLines: 2,
          hint: l10n.onbInjuriesHint,
          onChanged: (v) => notifier.updateHealth(
            (st) => st.copyWith(injuries: parseInjuryInput(v, st.injuries)),
          ),
        ),
        FieldLabel(l10n.onbLimitations),
        GlassTextField(
          value: _joinTags(h.physicalLimitations),
          maxLines: 2,
          hint: l10n.onbLimitationsHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(physicalLimitations: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbSurgeries),
        GlassTextField(
          value: _joinTags(h.recentSurgeries),
          maxLines: 2,
          hint: l10n.onbSurgeriesHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(recentSurgeries: _splitTags(v)),
          ),
        ),
        FieldLabel(l10n.onbBloodPressure),
        SingleChoiceChips<BloodPressure>(
          options: const [
            BloodPressure.low,
            BloodPressure.normal,
            BloodPressure.high
          ],
          labelOf: (bp) => switch (bp) {
            BloodPressure.low => l10n.onbBloodPressureLow,
            BloodPressure.normal => l10n.onbBloodPressureNormal,
            BloodPressure.high => l10n.onbBloodPressureHigh,
          },
          value: h.bloodPressure,
          onChanged: (bp) =>
              notifier.updateHealth((s) => s.copyWith(bloodPressure: bp)),
        ),
        FieldLabel(l10n.onbOtherHealth),
        GlassTextField(
          value: h.otherConcerns ?? '',
          maxLines: 3,
          hint: l10n.onbOtherHealthHint,
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(otherConcerns: v),
          ),
        ),
      ],
    );
  }
}
