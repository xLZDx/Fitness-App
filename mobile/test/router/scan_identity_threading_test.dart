import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/exercise_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// P2.G4 Step 7 -- the optional `scanId` threaded across the real 3-hop
/// router chain `/equipment/:id` -> `/exercise/:id` -> `/workout/:id`, each
/// hop forwarding it only when it itself received one (mirrors the existing
/// `?day=` pattern `workout_player_day_test.dart` already covers). This file
/// proves the two forwarding hops for real, through actual navigation and
/// actual query-string parsing -- not just that the fields exist -- while
/// staying additive: `scanner_page_test.dart` and
/// `scan_controller_test.dart` are untouched (see `core/DECISION_LOG.md`),
/// and this is a NEW file, not an edit to `exercise_page_test.dart` or
/// `equipment_detail_coach_gate_test.dart`.
///
/// The "no-context regression" half of Step 7's own requirement -- every
/// OTHER existing entry point to these pages (the AI planner, home page,
/// workouts page, workout summary) never gaining a `scanId` -- is proven by
/// `git diff --stat` showing zero changes to any of those files' own
/// pushes (`ai_planner_page.dart`, `home_page.dart`, `workouts_page.dart`,
/// `workout_summary_page.dart` all still push with no `scanId` query
/// param), plus their existing test suites re-running green with zero
/// modification (`core/DECISION_LOG.md`, 2026-09-12 checkpoint).
const _machine = EquipmentItem(
  id: 'leg_press',
  name: 'Leg Press',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

ExerciseItem _exercise(String id) => ExerciseItem.fromJson({
      'id': id,
      'title': 'Squat',
      'equipmentId': 'leg_press',
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': const <String>[],
      'steps': const ['Step'],
    });

void main() {
  group('EquipmentDetailPage -> /exercise/:id (hop 1)', () {
    testWidgets('forwards scanId when the page itself received one', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? landedOn;
      final router = GoRouter(
        initialLocation: '/equipment/leg_press?scanId=scan-abc',
        routes: [
          GoRoute(
            path: '/equipment/:id',
            builder: (context, state) => EquipmentDetailPage(
              equipmentId: state.pathParameters['id']!,
              scanId: state.uri.queryParameters['scanId'],
            ),
          ),
          GoRoute(
            path: '/exercise/:id',
            builder: (context, state) {
              landedOn = state.uri.toString();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentByIdProvider.overrideWith((ref, id) async => _machine),
          recommendedExercisesProvider.overrideWith(
            (ref, id) async => RecommendedExercises(
              items: [_exercise('ea_squat')],
              hiddenForInjury: 0,
            ),
          ),
          safetyContextProvider.overrideWith(
            (_) async => SafetyContext(
              screening: screen({for (final q in ParQQuestion.values) q: false}),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Squat'));
      await tester.pumpAndSettle();

      expect(landedOn, '/exercise/ea_squat?scanId=scan-abc');
    });

    testWidgets('forwards nothing when the page itself received no scanId',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? landedOn;
      final router = GoRouter(
        initialLocation: '/equipment/leg_press',
        routes: [
          GoRoute(
            path: '/equipment/:id',
            builder: (context, state) => EquipmentDetailPage(
              equipmentId: state.pathParameters['id']!,
              scanId: state.uri.queryParameters['scanId'],
            ),
          ),
          GoRoute(
            path: '/exercise/:id',
            builder: (context, state) {
              landedOn = state.uri.toString();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentByIdProvider.overrideWith((ref, id) async => _machine),
          recommendedExercisesProvider.overrideWith(
            (ref, id) async => RecommendedExercises(
              items: [_exercise('ea_squat')],
              hiddenForInjury: 0,
            ),
          ),
          safetyContextProvider.overrideWith(
            (_) async => SafetyContext(
              screening: screen({for (final q in ParQQuestion.values) q: false}),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Squat'));
      await tester.pumpAndSettle();

      expect(landedOn, '/exercise/ea_squat');
    });
  });

  group('ExercisePage -> /workout/:id (hop 2)', () {
    testWidgets('forwards scanId when the page itself received one', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? landedOn;
      final router = GoRouter(
        initialLocation: '/exercise/ea_squat?scanId=scan-xyz',
        routes: [
          GoRoute(
            path: '/exercise/:id',
            builder: (context, state) => ExercisePage(
              exerciseId: state.pathParameters['id']!,
              scanId: state.uri.queryParameters['scanId'],
            ),
          ),
          GoRoute(
            path: '/workout/:id',
            builder: (context, state) {
              landedOn = state.uri.toString();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          exerciseResolutionProvider.overrideWith(
            (ref, id) async => ExerciseResolution.found(_exercise('ea_squat')),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise.start')));
      await tester.pumpAndSettle();

      expect(landedOn, '/workout/ea_squat?scanId=scan-xyz');
    });

    testWidgets('forwards nothing when the page itself received no scanId',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? landedOn;
      final router = GoRouter(
        initialLocation: '/exercise/ea_squat',
        routes: [
          GoRoute(
            path: '/exercise/:id',
            builder: (context, state) => ExercisePage(
              exerciseId: state.pathParameters['id']!,
              scanId: state.uri.queryParameters['scanId'],
            ),
          ),
          GoRoute(
            path: '/workout/:id',
            builder: (context, state) {
              landedOn = state.uri.toString();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          exerciseResolutionProvider.overrideWith(
            (ref, id) async => ExerciseResolution.found(_exercise('ea_squat')),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise.start')));
      await tester.pumpAndSettle();

      expect(landedOn, '/workout/ea_squat');
    });
  });

  group('WorkoutPlayerPage', () {
    test('accepts and stores an optional scanId, defaulting to null', () {
      const withScan = WorkoutPlayerPage(exerciseId: 'x', scanId: 'scan-1');
      const withoutScan = WorkoutPlayerPage(exerciseId: 'x');
      expect(withScan.scanId, 'scan-1');
      expect(withoutScan.scanId, isNull);
    });
  });
}
