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
          // Since 2026-08-03 a list only shows exercises it can demonstrate
          // with a clip, so a fixture without one renders an empty page and
          // every assertion below finds nothing.
          video: {'men': 'https://cdn.example.com/run.mp4'},
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
          video: {'men': 'https://cdn.example.com/squat.mp4'},
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
          video: {'men': 'https://cdn.example.com/pushup.mp4'},
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

/// The horizontally-scrolling filter chip row. Found by axis rather than by
/// position: the page also has the vertical exercise list, and which of the
/// two comes first in the tree is an implementation detail.
final Finder _chipRow = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
);

void main() {
  group('WorkoutsPage (live catalog)', () {
    testWidgets('renders equipment-type AND muscle-group filter chips',
        (tester) async {
      // Round 4 (S4): five chips could not navigate a 192-exercise catalog
      // across 48 machines, so the row gained muscle groups and split
      // equipment type into machines / free weights / cardio.
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      // The chip row scrolls horizontally, so only the leading ones are
      // laid out; assert on those plus the enum's own completeness below.
      for (final f in ['For you', 'Machines', 'Free weights']) {
        expect(find.text(f), findsOneWidget);
      }
      expect(WorkoutsFilter.values.length, greaterThan(10));
      expect(kFilterMuscles.keys, contains(WorkoutsFilter.chest));
      expect(kFilterMuscles.keys, contains(WorkoutsFilter.glutes));
      expect(kFilterCategories.keys, contains(WorkoutsFilter.freeWeights));
    });

    test('every muscle chip filters on tags the catalog vocabulary uses', () {
      const vocab = {'adductors', 'back', 'biceps', 'calves', 'chest', 'core',
          'forearms', 'glutes', 'hamstrings', 'lats', 'lower_back', 'quads',
          'shoulders', 'traps', 'triceps'};
      for (final entry in kFilterMuscles.entries) {
        expect(vocab, containsAll(entry.value),
            reason: '${entry.key} filters on a tag no exercise carries');
      }
    });

    test('every filter is either for-you, all, at-home, muscle or category',
        () {
      // A chip with no rule behind it would silently render an empty list.
      // This guard is why `stretching` could not be added as a label only —
      // it caught the half-finished version.
      const special = {
        WorkoutsFilter.forYou,
        WorkoutsFilter.all,
        WorkoutsFilter.noEquipment,
        WorkoutsFilter.stretching,
      };
      for (final f in WorkoutsFilter.values) {
        final covered = special.contains(f) ||
            kFilterMuscles.containsKey(f) ||
            kFilterCategories.containsKey(f);
        expect(covered, isTrue, reason: '$f has no filtering rule');
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

    testWidgets('Machines filter restricts to strength-category equipment',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Machines'));
      await tester.pumpAndSettle();

      expect(find.text('Back squat'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Push-ups'), findsNothing);
    });

    testWidgets('No equipment filter shows only body-weight exercises',
        (tester) async {
      // The chip read "At home" until 2026-08-04, which described a place the
      // filter never checked: it selects on `!needsEquipment`, so a kettlebell
      // swing in your kitchen is out and a hamstring stretch in a commercial
      // gym is in.
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('No equipment'), 120,
          scrollable: _chipRow);
      await tester.tap(find.text('No equipment'));
      await tester.pumpAndSettle();

      expect(find.text('Push-ups'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
    });

    testWidgets('a muscle chip filters by muscle tag, not by equipment',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      // 'Chest' must find the body-weight push-up, proving the muscle chips
      // slice on tags rather than on which machine the exercise belongs to.
      await tester.scrollUntilVisible(find.text('Chest'), 120,
          scrollable: _chipRow);
      await tester.tap(find.text('Chest'));
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
