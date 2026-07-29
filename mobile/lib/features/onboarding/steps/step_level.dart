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

class StepLevel extends ConsumerWidget {
  const StepLevel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(questionnaireDraftProvider).level;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingWhereAreYouNow,
          subtitle: AppLocalizations.of(context).onboardingYourStartingPointShapesHowAggressive,
          icon: Icons.fitness_center_outlined,
          iconGradient: [AppPalette.auroraBlue, AppPalette.auroraTeal],
        ),
        const FieldLabel('Sessions per week'),
        GlassTextField(
          value: level.frequencyPerWeek?.toString() ?? '',
          keyboardType: TextInputType.number,
          hint: '3',
          onChanged: (v) => notifier.updateLevel(
            (s) => s.copyWith(frequencyPerWeek: int.tryParse(v)),
          ),
        ),
        const FieldLabel('Exercises you currently do'),
        GlassTextField(
          value: level.currentExercises.join(', '),
          maxLines: 2,
          hint: 'running, yoga, weights',
          onChanged: (v) => notifier.updateLevel(
            (s) => s.copyWith(currentExercises: _splitTags(v)),
          ),
        ),
        const FieldLabel('Self-rated level'),
        SingleChoiceChips<FitnessTier>(
          options: const [
            FitnessTier.beginner,
            FitnessTier.intermediate,
            FitnessTier.advanced,
          ],
          labelOf: (t) => switch (t) {
            FitnessTier.beginner => 'Beginner',
            FitnessTier.intermediate => 'Intermediate',
            FitnessTier.advanced => 'Advanced',
          },
          value: level.tier,
          onChanged: (t) =>
              notifier.updateLevel((s) => s.copyWith(tier: t)),
        ),
        const FieldLabel('Comfortable with push-ups, squats, planks?'),
        SingleChoiceChips<BasicExerciseAbility>(
          options: const [
            BasicExerciseAbility.yes,
            BasicExerciseAbility.partial,
            BasicExerciseAbility.no,
          ],
          labelOf: (b) => switch (b) {
            BasicExerciseAbility.yes => 'Yes',
            BasicExerciseAbility.partial => 'Some',
            BasicExerciseAbility.no => 'Not yet',
          },
          value: level.basics,
          onChanged: (b) =>
              notifier.updateLevel((s) => s.copyWith(basics: b)),
        ),
      ],
    );
  }
}
