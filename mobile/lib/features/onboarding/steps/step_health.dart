import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final h = ref.watch(questionnaireDraftProvider).health;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          title: 'Health snapshot',
          subtitle: 'We use this to keep your plan safe — separate items with commas.',
          icon: Icons.favorite_outline,
          iconGradient: [AppPalette.auroraPink, AppPalette.auroraPeach],
        ),
        const FieldLabel('Pre-existing conditions'),
        GlassTextField(
          value: _joinTags(h.conditions),
          maxLines: 2,
          hint: 'e.g. asthma, diabetes',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(conditions: _splitTags(v)),
          ),
        ),
        const FieldLabel('Allergies'),
        GlassTextField(
          value: _joinTags(h.allergies),
          maxLines: 2,
          hint: 'e.g. peanuts, penicillin',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(allergies: _splitTags(v)),
          ),
        ),
        const FieldLabel('Current medications'),
        GlassTextField(
          value: _joinTags(h.medications),
          maxLines: 2,
          hint: 'e.g. ibuprofen, insulin',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(medications: _splitTags(v)),
          ),
        ),
        const FieldLabel('Past or current injuries'),
        GlassTextField(
          value: h.injuries.map((i) => '${i.bodyPart}: ${i.type}').join(', '),
          maxLines: 2,
          hint: 'knee: meniscus, lower back: strain',
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
        const FieldLabel('Physical limitations'),
        GlassTextField(
          value: _joinTags(h.physicalLimitations),
          maxLines: 2,
          hint: 'e.g. cannot lift overhead',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(physicalLimitations: _splitTags(v)),
          ),
        ),
        const FieldLabel('Recent surgeries'),
        GlassTextField(
          value: _joinTags(h.recentSurgeries),
          maxLines: 2,
          hint: 'e.g. ACL repair (2025)',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(recentSurgeries: _splitTags(v)),
          ),
        ),
        const FieldLabel('Blood pressure'),
        SingleChoiceChips<BloodPressure>(
          options: const [
            BloodPressure.low,
            BloodPressure.normal,
            BloodPressure.high
          ],
          labelOf: (bp) => switch (bp) {
            BloodPressure.low => 'Low',
            BloodPressure.normal => 'Normal',
            BloodPressure.high => 'High',
          },
          value: h.bloodPressure,
          onChanged: (bp) =>
              notifier.updateHealth((s) => s.copyWith(bloodPressure: bp)),
        ),
        const FieldLabel('Other health concerns'),
        GlassTextField(
          value: h.otherConcerns ?? '',
          maxLines: 3,
          hint: 'Anything else we should know',
          onChanged: (v) => notifier.updateHealth(
            (s) => s.copyWith(otherConcerns: v),
          ),
        ),
      ],
    );
  }
}
