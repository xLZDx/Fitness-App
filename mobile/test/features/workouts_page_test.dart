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
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
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
      // Both stubs, so the test can tell WHICH of the two screens the list
      // opens rather than passing on either.
      GoRoute(
        path: '/exercise/:id',
        builder: (_, state) => Scaffold(
            body: Center(
                child: Text('exercise_${state.pathParameters['id']}'))),
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

/// R11i: WorkoutsPage now opens on the Programs sub-tab (matching the
/// prototype's own default), so every test below that exercises the
/// Library filter chips/list must switch to it first — the chip row and
/// exercise list this whole file already tested did not move or change,
/// they just live behind a tap now.
Future<void> _pumpLibrary(WidgetTester tester, AssetEquipmentRepository repo) async {
  await tester.pumpWidget(_harness(repo));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Library'));
  await tester.pumpAndSettle();
}

/// Brings a chip into the viewport and taps it.
///
/// `scrollUntilVisible` alone is not enough and the difference cost four
/// failures when this row gained one chip: it stops as soon as the finder
/// matches, and a horizontal `ListView` builds a little beyond the edge, so the
/// chip is in the tree at an offset outside the 800pt test window. The tap then
/// lands nowhere with a warning rather than an error. `ensureVisible` is the
/// one that guarantees the widget is actually on screen.
Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.text(label);
  if (chip.evaluate().isEmpty) {
    await tester.scrollUntilVisible(chip, 120, scrollable: _chipRow);
  }
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  group('WorkoutsPage (live catalog)', () {
    testWidgets('renders equipment-type AND muscle-group filter chips',
        (tester) async {
      // Round 4 (S4): five chips could not navigate a 192-exercise catalog
      // across 48 machines, so the row gained muscle groups and split
      // equipment type into machines / free weights / cardio.
      await _pumpLibrary(tester, _seededRepo());

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
        // Its own arm for the same reason as `stretching`: it is neither a
        // muscle group nor an equipment type. It filters on
        // `formCoachSupports`, which is a fact about the app rather than about
        // the catalog.
        WorkoutsFilter.formCoach,
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
      await _pumpLibrary(tester, _seededRepo());
      expect(find.byType(SmoothScrollList), findsOneWidget);
    });

    testWidgets('"For you" surfaces every catalog exercise (no profile)',
        (tester) async {
      await _pumpLibrary(tester, _seededRepo());
      expect(find.text('Easy run'), findsOneWidget);
      expect(find.text('Back squat'), findsOneWidget);
      expect(find.text('Push-ups'), findsOneWidget);
    });

    testWidgets('Cardio filter restricts to cardio-category equipment',
        (tester) async {
      await _pumpLibrary(tester, _seededRepo());

      await _tapChip(tester, 'Cardio');

      expect(find.text('Easy run'), findsOneWidget);
      expect(find.text('Back squat'), findsNothing);
      expect(find.text('Push-ups'), findsNothing);
    });

    testWidgets('Machines filter restricts to strength-category equipment',
        (tester) async {
      await _pumpLibrary(tester, _seededRepo());

      await _tapChip(tester, 'Machines');

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
      await _pumpLibrary(tester, _seededRepo());

      await _tapChip(tester, 'No equipment');

      expect(find.text('Push-ups'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
    });

    testWidgets('a muscle chip filters by muscle tag, not by equipment',
        (tester) async {
      await _pumpLibrary(tester, _seededRepo());

      // 'Chest' must find the body-weight push-up, proving the muscle chips
      // slice on tags rather than on which machine the exercise belongs to.
      await _tapChip(tester, 'Chest');

      expect(find.text('Push-ups'), findsOneWidget);
      expect(find.text('Easy run'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
    });

    testWidgets('Tapping a card routes to /exercise/:id, not the player',
        (tester) async {
      // Changed with R3.2. Browsing the catalogue is a question — "what is
      // this movement" — and it used to be answered with the workout player:
      // set timers, rest, mark-complete and a schedule button, for a session
      // the user had not started. The reference page answers the question and
      // offers to start the workout from there.
      //
      // Both routes are stubbed in the harness, so this fails if the list
      // opens the player again rather than passing on whichever exists.
      await _pumpLibrary(tester, _seededRepo());

      await tester.tap(find.text('Push-ups'));
      await tester.pumpAndSettle();

      expect(find.text('exercise_pushup'), findsOneWidget);
      expect(find.text('player_pushup'), findsNothing);
    });
  });

  // R11i: the Programs/Library split. Every enrollment-write assertion lives
  // in `programme_action_test.dart` (which already proves the write path
  // end-to-end); this file only proves the PAGE shows what the entity says
  // and reaches the action when tapped.
  group('WorkoutsPage (Programs tab)', () {
    testWidgets('opens on Programs, showing the template catalogue',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Programs'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      // A static template title -- `programmeTemplates` needs no provider
      // override to render, so this is present the instant the page opens.
      expect(find.text('Силовая база'), findsOneWidget);
    });

    testWidgets('switching to Library and back preserves both tabs\' content',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('Силовая база'), findsNothing);

      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();
      expect(find.text('Силовая база'), findsOneWidget);
      expect(find.text('For you'), findsNothing);
    });

    testWidgets('no current-programme card when nothing is active',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workouts.currentProgramme')), findsNothing);
    });

    testWidgets('an active programme shows the current-programme card with '
        'its title and week', (tester) async {
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

      final router = GoRouter(
        initialLocation: '/workouts',
        routes: [
          GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
            // Plain sync Provider overrides -- no stream, no repository, no
            // hang risk (see home_page_test.dart's own note on why a
            // broadcast-stream mock repo is the wrong tool for this).
            activeProgrammeProvider.overrideWithValue(programme),
            activeProgrammeProgressProvider.overrideWithValue(
              deriveProgrammeProgress(programme, const []),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workouts.currentProgramme')), findsOneWidget);
      expect(find.textContaining('Week 2 of 8'), findsOneWidget);
    });

    testWidgets('the goal filter narrows the template list', (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      // 'Гипертрофия' is a Muscle-goal template; 'Старт в зале' is Form.
      // Selecting Muscle must keep one and drop the other. Scoped to the
      // filter row itself, not a bare `find.text('Muscle')` -- two of the
      // six templates ('Гипертрофия', 'Плечи и руки') carry that same goal
      // and print it on their own card via `_TemplateChip`, so the bare text
      // matches three widgets, not one.
      final muscleChip =
          find.descendant(of: _chipRow, matching: find.text('Muscle'));
      await tester.scrollUntilVisible(muscleChip, 80, scrollable: _chipRow);
      await tester.ensureVisible(muscleChip);
      await tester.tap(muscleChip);
      await tester.pumpAndSettle();

      expect(find.text('Гипертрофия'), findsOneWidget);
      expect(find.text('Старт в зале'), findsNothing);
    });

    testWidgets('tapping Start on a template reaches the enroll action',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start programme').first);
      await tester.pumpAndSettle();

      // No signed-in user is overridden in this harness, so the action
      // surfaces the same signed-out error `programme_action_test.dart`
      // pins directly -- proof the tap reached `ProgrammeAction.enroll`
      // rather than doing nothing.
      expect(find.textContaining('Couldn\'t start this programme'),
          findsOneWidget);
    });
  });
}
