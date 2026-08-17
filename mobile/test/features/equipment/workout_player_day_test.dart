import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/safety_disclosure.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// The player half of "a scheduled day is ONE workout".
///
/// B5b made a day hold several exercises; until this gate the player still
/// opened only exercise one and logged it under that exercise's own key, so a
/// four-exercise day either recorded one exercise or — once the others were
/// opened separately — four workouts. Both readings are wrong, and every
/// streak, count and weekly total read off them was wrong with them.
///
/// What is worth pinning is therefore not that a strip renders. It is the two
/// facts a user can be harmed by: the day's exercises are reachable from inside
/// the player, and everything logged in that day lands under ONE id.

ExerciseItem _exercise(String id, String title) => ExerciseItem.fromJson({
      'id': id,
      'title': title,
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': const ['quadriceps'],
      'steps': const ['Stand tall', 'Sit back', 'Drive up'],
    });

final _squat = _exercise('ea_air_squat', 'Air Squat');
final _row = _exercise('ea_row', 'Bent-over Row');
final _press = _exercise('ea_press', 'Overhead Press');

/// Carries the tag `MovementRestriction.overhead` screens on, so the
/// eligibility layer has something real to remove. N02's fixture.
final _overheadPress = ExerciseItem.fromJson({
  'id': 'ea_ohp',
  'title': 'Standing Overhead Press',
  'durationMinutes': 10,
  'difficulty': 'beginner',
  'muscles': const ['shoulders'],
  'steps': const ['Press overhead'],
  'contraindications': const ['shoulder'],
});

ScheduledSession _day({
  String id = 'day_1',
  List<ExerciseItem> exercises = const [],
}) =>
    ScheduledSession(
      id: id,
      exerciseId: exercises.first.id,
      exerciseTitle: exercises.first.title,
      scheduledFor: DateTime.utc(2026, 8, 14, 9),
      durationMinutes: 30,
      extraExercises: [
        for (final e in exercises.skip(1))
          WorkoutSessionExercise(exerciseId: e.id, exerciseTitle: e.title),
      ],
    );

WorkoutSession _daySessionWith(
  List<WorkoutSessionExercise> exercises, {
  String dayId = 'day_1',
}) =>
    WorkoutSession(
      id: daySessionId(dayId),
      title: exercises.first.exerciseTitle,
      exercises: exercises,
      startedAt: DateTime.utc(2026, 8, 14, 9),
      completedAt: DateTime.utc(2026, 8, 14, 9, 12),
      status: WorkoutSessionStatus.completed,
    );

const _squatLogged =
    WorkoutSessionExercise(exerciseId: 'ea_air_squat', exerciseTitle: 'Air Squat');

Widget _app(
  Widget child, {
  List<ScheduledSession> days = const [],
  List<WorkoutSession> logged = const [],
  // Non-null replaces the whole history stream, so a test can hold the first
  // snapshot back and reproduce the cold-start race.
  Stream<List<WorkoutSession>>? history,
  MockWorkoutSessionRepository? repo,
  Programme? programme,
  MockScheduledSessionRepository? sessionRepo,
  // N02: what the add-exercise picker draws from, and who it draws for.
  List<ExerciseItem>? catalog,
  SafetyContext? safety,
}) =>
    ProviderScope(
      overrides: [
        exerciseResolutionProvider.overrideWith((ref, id) async {
          final item = [_squat, _row, _press, _overheadPress]
              .where((e) => e.id == id)
              .first;
          return ExerciseResolution.found(item);
        }),
        if (catalog != null)
          safeCatalogProvider.overrideWith((_) async => catalog),
        if (safety != null)
          safetyContextProvider.overrideWith((_) async => safety),
        authUserProvider.overrideWith((_) => Stream.value(
            const AuthUser(uid: 'u1', displayName: 'Tester'))),
        if (repo != null) workoutSessionRepositoryProvider.overrideWithValue(repo),
        // Overridden as a stream rather than through the mock repository where
        // the test only reads: what is under test is what the player does with
        // the history, not how it is fetched.
        scheduledSessionsProvider.overrideWith((_) => Stream.value(days)),
        workoutSessionsProvider
            .overrideWith((_) => history ?? Stream.value(logged)),
        if (programme != null)
          activeProgrammeProvider.overrideWithValue(programme),
        if (sessionRepo != null)
          scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
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
  /// The page is long; a short viewport scrolls the strip out of the tree and
  /// every assertion below would be testing the viewport, not the widget.
  Future<void> tall(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('a day lists its exercises and says where in it you are',
      (t) async {
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_1'),
      days: [_day(exercises: [_squat, _row, _press])],
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.dayStrip')), findsOneWidget);
    // Exercise two of three — the position is what tells someone mid-workout
    // whether they are nearly done, and it is read off the plan, not off a
    // counter the page keeps for itself.
    expect(find.text('Exercise 2 of 3'), findsOneWidget);
    for (final title in const ['Air Squat', 'Bent-over Row', 'Overhead Press']) {
      expect(find.text(title), findsWidgets, reason: '$title is part of the day');
    }
  });

  testWidgets('opened without a day, the player shows no strip at all',
      (t) async {
    // The scan and deep-link paths. They have no day to belong to, and a strip
    // there would be inventing one.
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row'),
      days: [_day(exercises: [_squat, _row, _press])],
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.dayStrip')), findsNothing);
  });

  testWidgets(
      'F020: the player carries the same "screened by rules, not a '
      'clinician" disclosure the reference page does', (t) async {
    // workout_player_page.dart builds its own section list rather than
    // calling exerciseReferenceSections -- the function exercise_page.dart
    // uses -- so it needs its own proof the disclosure actually reached it,
    // not just a shared one on the other screen.
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row'),
      days: [_day(exercises: [_squat, _row, _press])],
    ));
    await t.pumpAndSettle();

    expect(find.byType(SafetyDisclosure), findsOneWidget);
  });

  testWidgets('a one-exercise day draws no strip -- there is nothing to walk',
      (t) async {
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_air_squat', dayId: 'day_1'),
      days: [_day(exercises: [_squat])],
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.dayStrip')), findsNothing);
  });

  testWidgets('an unknown day is silent rather than half-drawn', (t) async {
    // A stale deep link, or a day cancelled on another device. Drawing an empty
    // strip would claim the day exists and is empty; both are false.
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_missing'),
      days: [_day(exercises: [_squat, _row, _press])],
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.dayStrip')), findsNothing);
    expect(find.text('Bent-over Row'), findsWidgets,
        reason: 'the exercise itself still has to play');
  });

  testWidgets('what the day has already logged is read back from the session',
      (t) async {
    // The case the in-memory provider cannot cover: the log was written before
    // this route existed (another exercise of the same day, or a cold start
    // later in the day). If the strip only trusted `_loggedEntryProvider`, a
    // finished exercise would show as untouched the moment you walked back to
    // it.
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_1'),
      days: [_day(exercises: [_squat, _row, _press])],
      logged: [
        WorkoutSession(
          id: daySessionId('day_1'),
          title: 'Air Squat',
          exercises: const [
            WorkoutSessionExercise(
                exerciseId: 'ea_air_squat', exerciseTitle: 'Air Squat'),
          ],
          startedAt: DateTime.utc(2026, 8, 14, 9),
          completedAt: DateTime.utc(2026, 8, 14, 9, 12),
          status: WorkoutSessionStatus.completed,
        ),
      ],
    ));
    await t.pumpAndSettle();

    final strip = find.byKey(const Key('player.dayStrip'));
    expect(strip, findsOneWidget);
    // Struck through == done. Asserting on the decoration rather than on an
    // icon because it is the thing a user actually reads down the list.
    final squatRow = t.widget<Text>(find.descendant(
      of: strip,
      matching: find.text('Air Squat'),
    ));
    expect(squatRow.style?.decoration, TextDecoration.lineThrough,
        reason: 'the exercise the persisted session holds is finished');
    final rowRow = t.widget<Text>(find.descendant(
      of: strip,
      matching: find.text('Bent-over Row'),
    ));
    expect(rowRow.style?.decoration, isNot(TextDecoration.lineThrough),
        reason: 'the exercise being played now is not');
  });

  testWidgets('logging exercise two of a day keeps exercise one', (t) async {
    // The invariant the whole gate exists for, driven through the button and
    // the real save path rather than through `upsertExerciseById` alone. The
    // pure function can be perfect while the button assembles the wrong
    // session around it -- and `save()` is `doc(id).set(...)`, a full
    // overwrite, so "wrong session" means exercise one is gone.
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    // `runAsync` for every direct repository call: `save` opens with
    // `await Future.delayed(_latency)`
    // (`mock_workout_session_repository.dart:77-79`), and inside a widget
    // test's fake-async zone even a zero-duration delay only completes when
    // the clock is pumped -- so awaiting it before `pumpWidget` hangs the
    // test outright rather than failing it.
    await t.runAsync(
        () => repo.save('u1', _daySessionWith(const [_squatLogged])));

    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_1'),
      days: [_day(exercises: [_squat, _row, _press])],
      logged: [_daySessionWith(const [_squatLogged])],
      repo: repo,
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('player.markComplete')));
    // Not pumpAndSettle: logging starts the rest countdown, and a periodic
    // timer never settles.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    final stored = (await t.runAsync(() => repo.watch('u1').first))!;
    expect(stored, hasLength(1), reason: 'a day is ONE workout, not two rows');
    expect(
      stored.single.exercises.map((e) => e.exerciseId),
      containsAll(const ['ea_air_squat', 'ea_row']),
      reason: 'exercise one must survive exercise two being logged',
    );
  });

  testWidgets(
      'N02: the add-exercise picker offers nothing a movement restriction '
      'rules out', (t) async {
    // The highest-risk unscreened list in the app, and the reason it is:
    // whatever is tapped here is written straight into the logged session, so
    // no later screen re-evaluates it. The picker used to read
    // `safeCatalogProvider`, which applies `safeFor` -- the INJURY filter and
    // nothing else -- so a user whose profile says "no overhead work" was
    // offered every overhead movement in the catalogue.
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    await t.runAsync(
        () => repo.save('u1', _daySessionWith(const [_squatLogged])));

    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_1'),
      days: [_day(exercises: [_squat, _row])],
      logged: [_daySessionWith(const [_squatLogged])],
      repo: repo,
      catalog: [_press, _overheadPress],
      safety: SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        health: const HealthFlags(
          restrictions: {MovementRestriction.overhead},
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('player.addExercise')));
    await t.pumpAndSettle();

    expect(find.text('Standing Overhead Press'), findsNothing,
        reason: 'the restriction names exactly this movement');
    expect(find.text('Overhead Press'), findsOneWidget,
        reason: 'an untagged exercise must still be offered -- the fix must '
            'filter, not empty the picker');
  });

  testWidgets('a tap before the history has loaded waits instead of overwriting',
      (t) async {
    // The cold-start race, caught in review before it shipped. On a fresh
    // start the in-memory copy is empty by design and the persisted session is
    // still in flight, so a fast tap used to build the day's document out of
    // THIS exercise alone and overwrite the ones already logged -- silently,
    // under a "Logged! Nice work" snackbar.
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    await t.runAsync(
        () => repo.save('u1', _daySessionWith(const [_squatLogged])));

    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', dayId: 'day_1'),
      days: [_day(exercises: [_squat, _row, _press])],
      repo: repo,
      history: Stream.fromFuture(
        Future.delayed(const Duration(seconds: 2),
            () => [_daySessionWith(const [_squatLogged])]),
      ),
    ));
    await t.pumpAndSettle(const Duration(milliseconds: 300));

    await t.tap(find.byKey(const Key('player.markComplete')));
    await t.pump();
    // Mid-race: nothing may have been written yet, and above all exercise one
    // must not have been replaced.
    var stored = (await t.runAsync(() => repo.watch('u1').first))!;
    expect(stored.single.exercises.map((e) => e.exerciseId), ['ea_air_squat'],
        reason: 'no write may land while the day is still unknown');

    // Let the snapshot arrive; the tap then completes against the real day.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    stored = (await t.runAsync(() => repo.watch('u1').first))!;
    expect(stored, hasLength(1));
    expect(
      stored.single.exercises.map((e) => e.exerciseId),
      containsAll(const ['ea_air_squat', 'ea_row']),
      reason: 'the wait exists so that both exercises survive',
    );
  });

  testWidgets('"added to" names the programme, never its stored id', (t) async {
    // B5d-2's Act review. `Programme.title` holds the raw id, not a display
    // name (B2a) — so this snackbar had been reading "Added to strength_base",
    // and a questionnaire-built programme would have made it "Added to
    // from_answers". Pinned with the sentinel because that is the id whose
    // leak is least excusable, but the fix and this guard cover every
    // programme.
    await tall(t);
    final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
    addTearDown(sessionRepo.dispose);

    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row'),
      sessionRepo: sessionRepo,
      // R-03. This case is about the snackbar's WORDING, and it used to leave
      // the safety context at its default — an unscreened profile, which
      // blocks all training. That was harmless only while
      // `addExerciseToActiveProgramme` had no safety check of its own; now
      // that it does, the default fixture describes a user the page would have
      // answered with an `EligibilityNotice` instead of this button. Screening
      // the fixture user makes it describe the state it is actually about.
      safety: SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
      ),
      programme: Programme(
        id: 'p1',
        templateId: kProfileProgrammeId,
        title: kProfileProgrammeId,
        goal: ProgrammeGoal.form,
        level: ExerciseDifficulty.beginner,
        weeks: 8,
        daysPerWeek: 3,
        startedAt: DateTime.utc(2026, 8, 1),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('player.addToProgramme')));
    await t.pumpAndSettle();

    expect(find.text('Added to My programme'), findsOneWidget);
    expect(find.textContaining('from_answers'), findsNothing,
        reason: 'the raw stored id reached the user');
  });

  test('a day logs under an id derived from the day, not from the clock', () {
    // The invariant behind "one workout per day". `_loggedEntryProvider` is
    // autoDispose and the strip REPLACES the route, so the id cannot be minted
    // once and remembered; derived from the day, `save()`'s upsert lands on the
    // same document every time.
    expect(daySessionId('day_1'), daySessionId('day_1'));
    expect(daySessionId('day_1'), isNot(daySessionId('day_2')));
  });
}
