import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/shared/widgets/smooth_scroll_list.dart';

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

ExerciseItem _ex(String id, String title, List<String> primary) => ExerciseItem(
      id: id,
      title: title,
      equipmentId: null,
      muscles: primary,
      primaryMuscles: primary,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
    );

Widget _buildApp({
  MockScheduledSessionRepository? scheduleRepo,
  MockProgrammeRepository? programmeRepo,
  // A direct StreamProvider override, not routed through a repository --
  // see the test that uses this for why (a broadcast-stream repo left the
  // whole suite hanging until the global 10-minute timeout, the exact trap
  // this file's own comment already names for scheduled sessions).
  List<Programme>? programmes,
  AuthUser? user,
  List<ExerciseItem>? catalog,
  /// Gate M. The home Suggestions section refuses when the pre-exercise screen
  /// cannot clear the user, and an unscreened profile is blocked — so a
  /// harness that says nothing about screening renders a refusal instead of
  /// the section under test. Defaulting to `clear` here keeps every existing
  /// case about what it was about; `an unscreened user gets the refusal, not
  /// an empty state` covers the other side deliberately.
  SafetyContext? safety,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/scan',
          builder: (_, __) => const Scaffold(body: Text('scan-stub'))),
      GoRoute(
          path: '/plan',
          builder: (_, __) => const Scaffold(body: Text('plan-stub'))),
      GoRoute(
        path: '/workout/:id',
        builder: (_, state) => Scaffold(
            body: Text('player_${state.pathParameters['id']}')),
      ),
      GoRoute(
          path: '/posture',
          builder: (_, __) => const Scaffold(body: Text('posture-stub'))),
    ],
  );
  return ProviderScope(
    overrides: [
      if (scheduleRepo != null)
        scheduledSessionRepositoryProvider
            .overrideWithValue(scheduleRepo),
      if (programmeRepo != null)
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
      if (programmes != null)
        programmesProvider.overrideWith((ref) => Stream.value(programmes)),
      if (user != null)
        authUserProvider.overrideWith((_) => Stream.value(user)),
      // Pinned so the Suggestions section is deterministic. The ranking itself
      // is covered by suggestion_builder_test; this file checks the wiring
      // from provider through card to navigation.
      if (catalog != null)
        forYouExercisesProvider.overrideWith((_) async => catalog),
      safetyContextProvider.overrideWith((_) async =>
          safety ??
          SafetyContext(
              screening: screen({for (final q in ParQQuestion.values) q: false}))),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  // R11a rebuilt this screen against the real design source
  // (`App.tsx:2441-2548`). The assertions below moved with it: the old ones
  // pinned an app bar reading "Home", a "Ready to train?" hero and three
  // quick-stat tiles, none of which the design has. What each section is
  // derived FROM is covered in `home/home_dashboard_test.dart`; this file
  // checks that the screen renders it and that its CTAs reach real routes.
  group('HomePage (default empty)', () {
    testWidgets('renders the greeting header, hero and week section',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byKey(const Key('home.greeting')), findsOneWidget);
      expect(find.byKey(const Key('home.heroEmpty')), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsOneWidget);
      expect(find.byKey(const Key('home.quickScan')), findsOneWidget);
      expect(find.byKey(const Key('home.week')), findsOneWidget);
    });

    testWidgets('the greeting shows the first name only', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp(
        user: const AuthUser(uid: 'u1', displayName: 'Ivan Korostelev'),
      ));
      await tester.pump();

      expect(find.text('Ivan'), findsOneWidget);
      expect(find.text('Ivan Korostelev'), findsNothing,
          reason: 'a full name in 34pt display type is a document, not a hello');
    });

    testWidgets('an anonymous user is greeted by a word, not by a blank',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(
          _buildApp(user: const AuthUser(uid: 'u2', displayName: '')));
      await tester.pump();

      expect(find.text('Athlete'), findsOneWidget);
    });

    testWidgets('the plan bar is absent when nothing is scheduled',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byKey(const Key('home.planProgress')), findsNothing,
          reason: 'a 0% bar over an empty week reads as failure');
    });

    testWidgets('the recovery strip is absent with no history', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byKey(const Key('home.recovery')), findsNothing,
          reason: 'you cannot be recovered from work you never did');
    });

    testWidgets('the week totals carry the design\'s three labels',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('workouts'), findsOneWidget);
      expect(find.text('kg lifted'), findsOneWidget);
      expect(find.text('records'), findsOneWidget);
    });

    testWidgets('uses a SmoothScrollList for the home content', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(SmoothScrollList), findsOneWidget);
    });

    // Replaces a test that asserted five hardcoded titles ("Upper body
    // power", "HIIT cardio burn", ...). Those cards were static strings with
    // `onTap: () {}` — the test passed while the feature did nothing.
    testWidgets('suggestions come from the catalog and open the workout',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp(catalog: [
        _ex('barbell_full_squat', 'Barbell Full Squat', ['quads']),
        _ex('pull_up', 'Pull-up', ['lats']),
      ]));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Barbell Full Squat'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Barbell Full Squat'), findsOneWidget);
      expect(find.text('Pull-up'), findsOneWidget);
      expect(find.byKey(const Key('suggestions-empty')), findsNothing);

      await tester.tap(find.byKey(const Key('suggestion-barbell_full_squat')));
      await tester.pumpAndSettle();

      expect(find.text('player_barbell_full_squat'), findsOneWidget,
          reason: 'the card must reach the real exercise, not nothing');
    });

    testWidgets('an empty catalog shows an honest empty state, not filler',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp(catalog: const []));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('suggestions-empty')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('suggestions-empty')), findsOneWidget);
    });

    testWidgets('an unscreened user gets the refusal, not an empty state',
        (tester) async {
      // The other side of the default above, and the point of Gate M: the
      // section that would have said "nothing to suggest right now" says the
      // real reason instead. `homeSuggestionsEmpty` is a true statement about
      // the catalogue and a false one about why this user has no session.
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp(
        catalog: [_ex('push-up', 'Push-up', const ['chest'])],
        safety: SafetyContext(screening: kUnscreened),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('home.suggestions.refused')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('home.suggestions.refused')), findsOneWidget);
      expect(find.byKey(const Key('suggestions-empty')), findsNothing);
    });

    testWidgets('the quick-scan card navigates to /scan', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      await tester.tap(find.byKey(const Key('home.quickScan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('scan-stub'), findsOneWidget);
    });

    testWidgets('the empty hero offers the planner instead of a dead button',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('Today\'s adaptive plan').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('plan-stub'), findsOneWidget);
    });

    testWidgets('Posture card navigates to /posture', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byKey(const Key('home.postureCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.postureCard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('posture-stub'), findsOneWidget);
    });
  });

  // Note: the upcoming-card widget integration test was removed; its logic
  // is fully exercised by `filterUpcoming` and `formatScheduleLabel` unit
  // tests. Driving an in-memory repo through the live StreamProvider chain
  // hangs `pumpAndSettle` because the broadcast stream stays open.

  // Gate P: the header bar prefers an active programme over the plain
  // schedule bar. `programme_test.dart` and `programme_action_test.dart`
  // cover the arithmetic and the write path; this is the one place proving
  // Home actually renders what enrolling produces.
  group('HomePage (active programme)', () {
    testWidgets('shows the programme title and week instead of the plain bar',
        (tester) async {
      final programme = Programme(
        id: 'prog_1',
        templateId: 'strength_base',
        title: 'Силовая база',
        goal: ProgrammeGoal.strength,
        level: ExerciseDifficulty.intermediate,
        weeks: 8,
        daysPerWeek: 4,
        startedAt: DateTime.now().subtract(const Duration(days: 8)),
      );

      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp(
        user: const AuthUser(uid: 'u1', displayName: 'Ivan'),
        programmes: [programme],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('home.programmeProgress')), findsOneWidget);
      expect(find.byKey(const Key('home.planProgress')), findsNothing,
          reason: 'an active programme replaces the plain bar, not both');
      // Day 8 since start (kTestLocale is 'en') reads as week 2 of 8.
      //
      // B2a, 2026-08-13: this used to assert 'Силовая база' — a Russian
      // string under an English harness, which is precisely the defect the
      // operator photographed. The title now resolves from `templateId`
      // through `ProgrammeLabels`, so the assertion follows the locale and
      // would fail again if a template title were ever hardcoded back.
      expect(find.textContaining('Strength base · Week 2 of 8'), findsOneWidget);
    });
  });

  group('A8 — narrow screens', () {
    testWidgets('renders at 320 dp without overflowing', (tester) async {
      // The audit measured a 19 px overflow on the Home CTA at this width,
      // and the Android integration suite fails on it. 320 dp is not
      // hypothetical: it is a Galaxy A-series in display-size "large", and
      // the prototype the screen was rebuilt from has a ~390 dp viewport, so
      // nothing in the design process would have caught it.
      //
      // Asserted via `takeException` rather than by measuring the button:
      // a RenderFlex overflow is reported as a framework exception, so this
      // fails on ANY overflow the screen grows later, not only this one.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildApp(
        user: const AuthUser(uid: 'u1', displayName: 'Ivan'),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
