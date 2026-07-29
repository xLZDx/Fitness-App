import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/shared/widgets/smooth_scroll_list.dart';

AssetEquipmentRepository _seededRepo() {
  return AssetEquipmentRepository()
    ..seedForTests(
      equipment: const [
        EquipmentItem(
          id: 'tread',
          name: 'Treadmill',
          manufacturer: 'X',
          category: 'cardio',
          description: '',
        ),
        EquipmentItem(
          id: 'rack',
          name: 'Rack',
          manufacturer: 'Y',
          category: 'strength',
          description: '',
        ),
      ],
      exercises: const [
        ExerciseItem(
          id: 'tread_run',
          title: 'Easy run',
          equipmentId: 'tread',
          muscles: ['quads'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 30,
          summary: 'Steady aerobic run',
          steps: [],
        ),
        ExerciseItem(
          id: 'rack_squat',
          title: 'Back squat',
          equipmentId: 'rack',
          muscles: ['quads'],
          difficulty: ExerciseDifficulty.intermediate,
          durationMinutes: 25,
          summary: 'Compound lower body',
          steps: [],
        ),
        ExerciseItem(
          id: 'pushup',
          title: 'Push-ups',
          equipmentId: null,
          muscles: ['chest'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 8,
          summary: 'Body-weight pushing',
          steps: [],
        ),
      ],
    );
}

Widget _harness(AssetEquipmentRepository repo) {
  final router = GoRouter(
    initialLocation: '/workouts',
    routes: [
      GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
      GoRoute(
        path: '/workout/:id',
        builder: (_, state) =>
            Scaffold(body: Center(child: Text('player_${state.pathParameters['id']}'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
  group('WorkoutsPage (live catalog)', () {
    testWidgets('renders all five filter chips with For you selected',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      for (final f in ['For you', 'Strength', 'Cardio', 'At Home', 'All']) {
        expect(find.text(f), findsOneWidget);
      }
    });

    testWidgets('shows a SmoothScrollList for the workout list',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();
      expect(find.byType(SmoothScrollList), findsOneWidget);
    });

    testWidgets('"For you" surfaces every catalog exercise (no profile)',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();
      expect(find.text('Easy run'), findsOneWidget);
      expect(find.text('Back squat'), findsOneWidget);
      expect(find.text('Push-ups'), findsOneWidget);
    });

    testWidgets('Cardio filter restricts to cardio-category equipment',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cardio'));
      await tester.pumpAndSettle();

      expect(find.text('Easy run'), findsOneWidget);
      expect(find.text('Back squat'), findsNothing);
      expect(find.text('Push-ups'), findsNothing);
    });

    testWidgets('Strength filter restricts to strength-category equipment',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();

      expect(find.text('Back squat'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Push-ups'), findsNothing);
    });

    testWidgets('At Home filter shows only body-weight exercises',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('At Home'));
      await tester.pumpAndSettle();

      expect(find.text('Push-ups'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
    });

    testWidgets('Tapping a card routes to /workout/:id',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push-ups'));
      await tester.pumpAndSettle();

      expect(find.text('player_pushup'), findsOneWidget);
    });
  });
}
