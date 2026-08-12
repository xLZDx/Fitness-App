import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    final eq = ref.watch(questionnaireDraftProvider).equipment;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingWhatCanYouTrainWith,
          subtitle:
              AppLocalizations.of(context).onboardingWePickExercisesThatFitWhat,
        ),
        FieldLabel(l10n.onbGymAccess),
        SingleChoiceChips<bool>(
          options: const [true, false],
          labelOf: (b) => b ? 'Yes' : 'No',
          value: eq.hasGymAccess,
          onChanged: (v) => notifier.updateEquipment(
            (s) => s.copyWith(hasGymAccess: v),
          ),
        ),
        FieldLabel(l10n.onbHomeEquipment),
        GlassTextField(
          value: eq.homeEquipment.join(', '),
          maxLines: 2,
          hint: l10n.onbHomeEquipmentHint,
          onChanged: (v) => notifier.updateEquipment(
            (s) => s.copyWith(homeEquipment: _splitTags(v)),
          ),
        ),
      ],
    );
  }
}
