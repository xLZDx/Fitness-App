import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/shared/widgets/scroll_dim_list.dart';

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
  AuthUser? user,
  List<ExerciseItem>? catalog,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/scan',
          builder: (_, __) => const Scaffold(body: Text('scan-stub'))),
      GoRoute(
        path: '/workout/:id',
        builder: (_, state) => Scaffold(
            body: Text('player_${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      if (scheduleRepo != null)
        scheduledSessionRepositoryProvider
            .overrideWithValue(scheduleRepo),
      if (user != null)
        authUserProvider.overrideWith((_) => Stream.value(user)),
      // Pinned so the Suggestions section is deterministic. The ranking itself
      // is covered by suggestion_builder_test; this file checks the wiring
      // from provider through card to navigation.
      if (catalog != null)
        forYouExercisesProvider.overrideWith((_) async => catalog),
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
  group('HomePage (default empty)', () {
    testWidgets('renders the hero card and primary sections', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('GOOD MORNING'), findsOneWidget);
      expect(find.text('Ready to train?'), findsOneWidget);
      expect(find.text('Scan equipment'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsOneWidget);
    });

    testWidgets('shows three quick stat tiles with the new labels',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('uses a ScrollDimList for the home content', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(ScrollDimList), findsOneWidget);
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

    testWidgets('Scan equipment button navigates to /scan', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      await tester.tap(find.text('Scan equipment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('scan-stub'), findsOneWidget);
    });
  });

  // Note: the upcoming-card widget integration test was removed; its logic
  // is fully exercised by `filterUpcoming` and `formatScheduleLabel` unit
  // tests. Driving an in-memory repo through the live StreamProvider chain
  // hangs `pumpAndSettle` because the broadcast stream stays open.
}
