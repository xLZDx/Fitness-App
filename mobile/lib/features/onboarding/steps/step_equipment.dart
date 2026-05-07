import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

List<String> _splitTags(String input) => input
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

class StepEquipment extends ConsumerWidget {
  const StepEquipment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(questionnaireDraftProvider).equipment;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          title: 'What can you train with?',
          subtitle: 'We pick exercises that fit what you actually own.',
        ),
        const FieldLabel('Do you have access to a gym?'),
        SingleChoiceChips<bool>(
          options: const [true, false],
          labelOf: (b) => b ? 'Yes' : 'No',
          value: eq.hasGymAccess,
          onChanged: (v) => notifier.updateEquipment(
            (s) => s.copyWith(hasGymAccess: v),
          ),
        ),
        const FieldLabel('Equipment at home'),
        GlassTextField(
          value: eq.homeEquipment.join(', '),
          maxLines: 2,
          hint: 'e.g. dumbbells, kettlebell, mat',
          onChanged: (v) => notifier.updateEquipment(
            (s) => s.copyWith(homeEquipment: _splitTags(v)),
          ),
        ),
      ],
    );
  }
}
