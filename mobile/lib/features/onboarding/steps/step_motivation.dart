import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

class StepMotivation extends ConsumerWidget {
  const StepMotivation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(questionnaireDraftProvider).motivation;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingHowDoYouLikeToTrain,
          subtitle: AppLocalizations.of(context).onboardingTheseTweakTheToneAndLength,
          icon: Icons.bolt_outlined,
          iconGradient: [AppPalette.auroraViolet, AppPalette.auroraPink],
        ),
        const FieldLabel('What motivates you most?'),
        GlassTextField(
          value: m.motivation ?? '',
          maxLines: 3,
          hint: 'A few words about why you train',
          onChanged: (v) => notifier.updateMotivation(
            (s) => s.copyWith(motivation: v),
          ),
        ),
        const FieldLabel('Preferred environment'),
        MultiChoiceChips<WorkoutEnvironment>(
          options: const [
            WorkoutEnvironment.highIntensity,
            WorkoutEnvironment.relaxed,
            WorkoutEnvironment.groupClasses,
            WorkoutEnvironment.oneOnOne,
            WorkoutEnvironment.outdoor,
          ],
          labelOf: (e) => switch (e) {
            WorkoutEnvironment.highIntensity => 'High-intensity',
            WorkoutEnvironment.relaxed => 'Relaxed',
            WorkoutEnvironment.groupClasses => 'Group classes',
            WorkoutEnvironment.oneOnOne => '1-on-1',
            WorkoutEnvironment.outdoor => 'Outdoor',
          },
          values: m.environments.toSet(),
          onChanged: (next) => notifier.updateMotivation(
            (s) => s.copyWith(environments: next.toList()),
          ),
        ),
        const FieldLabel('Preferred session length'),
        SingleChoiceChips<WorkoutDuration>(
          options: const [
            WorkoutDuration.under15,
            WorkoutDuration.m15to30,
            WorkoutDuration.m30to45,
            WorkoutDuration.m45to60,
            WorkoutDuration.over60,
          ],
          labelOf: (d) => switch (d) {
            WorkoutDuration.under15 => 'Under 15 min',
            WorkoutDuration.m15to30 => '15–30 min',
            WorkoutDuration.m30to45 => '30–45 min',
            WorkoutDuration.m45to60 => '45–60 min',
            WorkoutDuration.over60 => 'Over an hour',
          },
          value: m.preferredDuration,
          onChanged: (d) => notifier.updateMotivation(
            (s) => s.copyWith(preferredDuration: d),
          ),
        ),
      ],
    );
  }
}
