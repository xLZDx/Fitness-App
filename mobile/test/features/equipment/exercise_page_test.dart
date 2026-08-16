import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/exercise_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/safety_disclosure.dart';
import 'package:fitness_app/features/ai_coach/ai_coach_context.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// R3.2 — the half of the split that is a page rather than a move.
///
/// The audit's §7.3 warned that adding `/exercise/:id` while the player kept
/// the same content would fork "how to show an exercise" into two sources of
/// truth. So the thing worth testing is not that the page renders — it is that
/// the SEPARATION holds: the reference page shows the description and none of
/// the controls for a workout in progress.
final _item = ExerciseItem.fromJson(const {
  'id': 'ea_air_squat',
  'title': 'Air Squat',
  'durationMinutes': 10,
  'difficulty': 'beginner',
  'muscles': ['quadriceps'],
  'steps': ['Stand tall', 'Sit back', 'Drive up'],
  'poseTargetId': 'squat',
});

Widget _page(Widget child, {ExerciseResolution? resolution}) => ProviderScope(
      overrides: [
        exerciseResolutionProvider.overrideWith(
          (ref, id) async => resolution ?? ExerciseResolution.found(_item),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  testWidgets('the exercise page describes the movement', (t) async {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(const ExercisePage(exerciseId: 'ea_air_squat')));
    await t.pumpAndSettle();

    expect(find.text('Air Squat'), findsOneWidget);
    expect(find.byKey(const Key('exercise.start')), findsOneWidget,
        reason: 'reference has to lead somewhere, or it is a dead end');
  });

  testWidgets(
      'F020: the page carries the "screened by rules, not a clinician" '
      'disclosure', (t) async {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(const ExercisePage(exerciseId: 'ea_air_squat')));
    await t.pumpAndSettle();

    expect(find.byType(SafetyDisclosure), findsOneWidget);
  });

  testWidgets('it carries none of the controls for a set in progress',
      (t) async {
    // The actual rule of the split. These belong to a workout that has been
    // started; putting them in front of someone reading what a movement IS is
    // the state R3 exists to end.
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(const ExercisePage(exerciseId: 'ea_air_squat')));
    await t.pumpAndSettle();

    for (final gone in const [
      'Mark complete',
      'Add to schedule',
      'Rest timer',
    ]) {
      expect(find.text(gone), findsNothing, reason: '"$gone" is doing, not describing');
    }
  });

  testWidgets('a withheld exercise says so on this page too', (t) async {
    // The wording that must not diverge between the two screens. Telling
    // someone "we couldn't find that exercise" when their own injury list is
    // hiding it is false, and hides the one fact they can act on.
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(
      const ExercisePage(exerciseId: 'ea_air_squat'),
      resolution: ExerciseResolution.hiddenForInjury(_item),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('Air Squat'), findsWidgets);
    expect(find.byKey(const Key('exercise.start')), findsNothing,
        reason: 'nothing to start when the exercise is withheld');
  });

  testWidgets('a screening refusal is named, not disguised as a 404',
      (t) async {
    // Withheld for something other than an injury used to fall past the
    // injury branch into "we couldn't find that exercise" — a second copy of
    // the same lie, told for a different reason.
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(
      const ExercisePage(exerciseId: 'ea_air_squat'),
      resolution: ExerciseResolution.withheld(_item, const [
        EligibilityReason(BlockReason.screening,
            question: ParQQuestion.chestPain),
      ]),
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('exercise.withheld')), findsOneWidget);
    expect(find.text("We couldn't find that exercise."), findsNothing);
    expect(find.byKey(const Key('exercise.ai-coach')), findsNothing,
        reason: 'no coach entry point for work the app is refusing');
  });

  testWidgets('the AI coach can be asked about a movement', (t) async {
    // `AiCoachSource.exercise` had no production caller: the prompt branch for
    // a movement — the one that tells the model to teach a load judgement
    // instead of naming a weight — was reachable only from its own tests.
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(_page(const ExercisePage(exerciseId: 'ea_air_squat')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('exercise.ai-coach')), findsOneWidget);
  });

  test('every AiCoachSource is passed by some screen in lib/', () {
    // Measured, not declared. A hand-written list of "sources we route" would
    // pass on the day it was written and rot exactly like the dead branch it
    // replaces, so this reads the source tree: for each enum value, some file
    // under lib/ other than the enum's own must name it.
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            !f.path.split(Platform.pathSeparator).join('/').endsWith(
                'features/ai_coach/ai_coach_context.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'run me from mobile/');

    // Comments do not count. The first version of this test matched the
    // doc comment on `_ExerciseCoachEntry` — which names the enum value while
    // explaining that it had no caller — and so passed against a build where
    // the entry point had been mutated away.
    String code(File f) => f
        .readAsLinesSync()
        .map((l) => l.trimLeft().startsWith('//') ? '' : l)
        .join('\n');

    for (final source in AiCoachSource.values) {
      final needle = 'AiCoachSource.${source.name}';
      final callers = files
          .where((f) => code(f).contains(needle))
          .map((f) => f.path)
          .toList();
      expect(callers, isNotEmpty,
          reason: '$needle has no caller: buildCoachPrompt has a branch for '
              'it that no screen can reach, which is a claim and not a '
              'feature');
    }
  });

  test('both screens exist and are distinct types', () {
    // Cheap, and it is the thing a future refactor is most likely to undo:
    // collapsing one back into the other and leaving a single screen doing
    // both jobs again.
    //
    // `isA<X>()` on an instance of X is a tautology and passed happily against
    // `class WorkoutPlayerPage extends ExercisePage` — the exact collapse this
    // is here to catch. Mutual exclusion is the property that is not free.
    expect(const ExercisePage(exerciseId: 'x'), isA<ExercisePage>());
    expect(const WorkoutPlayerPage(exerciseId: 'x'), isA<WorkoutPlayerPage>());
    expect(const WorkoutPlayerPage(exerciseId: 'x'), isNot(isA<ExercisePage>()));
    expect(const ExercisePage(exerciseId: 'x'), isNot(isA<WorkoutPlayerPage>()));
  });
}
