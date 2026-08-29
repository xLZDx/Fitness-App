import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart' show FrostedScaffold;
import '../../shared/widgets/hud/hud_surface.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../ai_coach/ai_coach_context.dart';
import '../ai_coach/ai_coach_sheet.dart';
import 'data/equipment_models.dart';
import 'widgets/exercise_reference.dart';

/// What an exercise IS, with nothing about a workout in progress.
///
/// The other half of the split the audit's §7.3 asked for. `/workout/:id` was
/// doing both jobs: it described the movement AND drove a set — timers, rest,
/// mark-complete, schedule, suggested weight. Someone browsing the catalogue
/// to find out what a movement is got a screen full of controls for a session
/// they had not started.
///
/// Every section here comes from `exerciseReferenceSections`, the same
/// function the player calls. That is the whole point of the split: two
/// screens, one answer to "how is an exercise shown". A page that assembled
/// its own hero and its own video block would look identical on the day it
/// shipped and drift by the third change.
///
/// The one thing this page adds is the way OUT of it: a button that starts the
/// workout. Reference leads to doing; doing does not lead back to reference,
/// because the player already shows everything this page does.
class ExercisePage extends ConsumerWidget {
  const ExercisePage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FrostedScaffold(
      // R11d: no GlassAppBar. The design opens this screen with the movement's
      // own picture at full bleed (`App.tsx:2818`), and the hero carries both
      // the back control and the title — a bar above it would repeat the name
      // and cost the picture 92px.
      body: ExerciseResolutionView(
        exerciseId: exerciseId,
        builder: (context, item, body) => SmoothScrollList(
          padding: EdgeInsets.zero,
          children: [
            ExerciseImmersiveHero(exercise: item, body: body),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...exerciseReferenceSections(context, item, body),
                  const SizedBox(height: 20),
                  _ExerciseCoachEntry(exercise: item),
                  const SizedBox(height: 20),
                  AppPrimaryButton(
                    key: const Key('exercise.start'),
                    onPressed: () =>
                        GoRouter.of(context).push('/workout/${item.id}'),
                    label: AppLocalizations.of(context).exerciseStartWorkout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The AI coach, asked about a MOVEMENT rather than a machine.
///
/// `AiCoachSource.exercise` existed from the day the enum was written and had
/// no caller: both production entry points (`equipment_detail_page.dart`,
/// `scanner_page.dart`) pass `AiCoachSource.equipment`, so the second branch of
/// every switch in the coach prompt — including the one that tells the model
/// to explain how to judge a starting load instead of naming a weight (now
/// built server-side, see `functions/src/ai_coach_advice.ts`) — was reachable
/// only from its own tests. A prompt no screen can ask is not a feature, it is
/// a claim.
///
/// It sits inside [ExerciseResolutionView]'s builder deliberately. That builder
/// runs only for an exercise the eligibility layer allows, so an exercise
/// withheld for an injury, a screening answer or a clinician's instruction has
/// no coach entry point either — the refusal card is the whole screen. The
/// safety boundary is the widget tree here, not a check this widget performs
/// and could forget.
class _ExerciseCoachEntry extends StatelessWidget {
  const _ExerciseCoachEntry({required this.exercise});

  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return HudPanel(
      key: const Key('exercise.ai-coach'),
      onTap: () => AiCoachSheet.show(
        context,
        source: AiCoachSource.exercise,
        subjectId: exercise.id,
        subjectName: exercise.title,
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiCoachButton,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  l10n.aiCoachButtonHintExercise,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
