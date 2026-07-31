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
    final l10n = AppLocalizations.of(context);
    final m = ref.watch(questionnaireDraftProvider).motivation;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: AppLocalizations.of(context).onboardingHowDoYouLikeToTrain,
          subtitle:
              AppLocalizations.of(context).onboardingTheseTweakTheToneAndLength,
          icon: Icons.bolt_outlined,
          iconGradient: [AppPalette.auroraViolet, AppPalette.auroraPink],
        ),
        FieldLabel(l10n.onbMotivationPrompt),
        GlassTextField(
          value: m.motivation ?? '',
          maxLines: 3,
          hint: l10n.onbMotivationHint,
          onChanged: (v) => notifier.updateMotivation(
            (s) => s.copyWith(motivation: v),
          ),
        ),
        FieldLabel(l10n.onbEnvironment),
        MultiChoiceChips<WorkoutEnvironment>(
          options: const [
            WorkoutEnvironment.highIntensity,
            WorkoutEnvironment.relaxed,
            WorkoutEnvironment.groupClasses,
            WorkoutEnvironment.oneOnOne,
            WorkoutEnvironment.outdoor,
          ],
          labelOf: (e) => switch (e) {
            WorkoutEnvironment.highIntensity => l10n.onbEnvIntense,
            WorkoutEnvironment.relaxed => l10n.onbEnvRelaxed,
            WorkoutEnvironment.groupClasses => l10n.onbEnvGroup,
            WorkoutEnvironment.oneOnOne => l10n.onbEnvOneOnOne,
            WorkoutEnvironment.outdoor => l10n.onbEnvOutdoor,
          },
          values: m.environments.toSet(),
          onChanged: (next) => notifier.updateMotivation(
            (s) => s.copyWith(environments: next.toList()),
          ),
        ),
        FieldLabel(l10n.onbSessionLength),
        SingleChoiceChips<WorkoutDuration>(
          options: const [
            WorkoutDuration.under15,
            WorkoutDuration.m15to30,
            WorkoutDuration.m30to45,
            WorkoutDuration.m45to60,
            WorkoutDuration.over60,
          ],
          labelOf: (d) => switch (d) {
            WorkoutDuration.under15 => l10n.onbSession15,
            WorkoutDuration.m15to30 => l10n.onbSession1530,
            WorkoutDuration.m30to45 => l10n.onbSession3045,
            WorkoutDuration.m45to60 => l10n.onbSession4560,
            WorkoutDuration.over60 => l10n.onbSession60,
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
