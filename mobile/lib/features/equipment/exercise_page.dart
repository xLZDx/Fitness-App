import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
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
      appBar: GlassAppBar(title: AppLocalizations.of(context).exerciseTitle),
      body: ExerciseResolutionView(
        exerciseId: exerciseId,
        builder: (context, item, body) => SmoothScrollList(
          padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
          children: [
            ...exerciseReferenceSections(context, item, body),
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
    );
  }
}
