import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

List<String> _splitTags(String input) => input
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String _joinTags(List<String> values) => values.join(', ');

class StepHealth extends ConsumerWidget {
  const StepHealth({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final h = ref.watch(questionnaireDraftProvider).health;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingHealthSnapshot,
          subtitle: AppLocalizations.of(context).onboardingWeUseThisToKeepYour,
          icon: Icons.favorite_outline,
          iconGradient: [AppPalette.auroraPink, AppPalette.auroraPeach],
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
          value: h.injuries.map((i) => '${i.bodyPart}: ${i.type}').join(', '),
          maxLines: 2,
          hint: l10n.onbInjuriesHint,
          onChanged: (v) {
            final injuries = v
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.contains(':'))
                .map((s) {
              final parts = s.split(':');
              return Injury(
                bodyPart: parts[0].trim(),
                type: parts.skip(1).join(':').trim(),
              );
            }).toList();
            notifier.updateHealth((st) => st.copyWith(injuries: injuries));
          },
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
