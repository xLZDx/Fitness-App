import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/safety_disclosure.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_thumb.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

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

Widget _harness(AssetEquipmentRepository repo, {SafetyContext? safety}) {
  final router = GoRouter(
    initialLocation: '/workouts',
    routes: [
      GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
      GoRoute(
        path: '/workout/:id',
        builder: (_, state) => Scaffold(
            body: Center(child: Text('player_${state.pathParameters['id']}'))),
      ),
      // Both stubs, so the test can tell WHICH of the two screens the list
      // opens rather than passing on either.
      GoRoute(
        path: '/exercise/:id',
        builder: (_, state) => Scaffold(
            body:
                Center(child: Text('exercise_${state.pathParameters['id']}'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
      // Gate N. The Train tab renders a stated refusal rather than an empty
      // list when the whole-person gate is closed, and an unscreened profile
      // closes it — so a harness that says nothing about screening renders the
      // refusal instead of the tab under test. `an unscreened user is refused`
      // covers the other side deliberately.
      safetyContextProvider.overrideWith((_) async =>
          safety ??
          SafetyContext(
              screening:
                  screen({for (final q in ParQQuestion.values) q: false}))),
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

/// The vertical exercise list. Same reasoning as `_chipRow`: the page has
/// more than one `Scrollable` once the chip row is present, so
/// `scrollUntilVisible`'s default (`find.byType(Scrollable)`, then
/// `.single`) throws instead of picking one.
final Finder _exerciseList = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// R11i: WorkoutsPage now opens on the Programs sub-tab (matching the
/// prototype's own default), so every test below that exercises the
/// Library filter chips/list must switch to it first — the chip row and
/// exercise list this whole file already tested did not move or change,
/// they just live behind a tap now.
Future<void> _pumpLibrary(WidgetTester tester, AssetEquipmentRepository repo,
    {SafetyContext? safety}) async {
  await tester.pumpWidget(_harness(repo, safety: safety));
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
      const vocab = {
        'adductors',
        'back',
        'biceps',
        'calves',
        'chest',
        'core',
        'forearms',
        'glutes',
        'hamstrings',
        'lats',
        'lower_back',
        'quads',
        'shoulders',
        'traps',
        'triceps'
      };
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

    // MVP Gate M2: Train is rebuilt on the HUD widget kit, whose scroll
    // region is `HudScreenBody` -- the same deliberate swap Home's own gate
    // made (`home_page_test.dart`), not a regression.
    testWidgets('shows a HudScreenBody for the workout list', (tester) async {
      await _pumpLibrary(tester, _seededRepo());
      expect(find.byType(HudScreenBody), findsOneWidget);
    });

    testWidgets('"For you" surfaces every catalog exercise (no profile)',
        (tester) async {
      await _pumpLibrary(tester, _seededRepo());
      expect(find.text('Easy run'), findsOneWidget);
      // F020 pushed the list down by one SafetyDisclosure card, so the
      // second and third exercises start below the fold -- scroll to them
      // rather than assert on raw pixel position, same reasoning as
      // `_tapChip`'s own comment on this exact pitfall.
      await tester.scrollUntilVisible(find.text('Back squat'), 200,
          scrollable: _exerciseList);
      expect(find.text('Back squat'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Push-ups'), 200,
          scrollable: _exerciseList);
      expect(find.text('Push-ups'), findsOneWidget);
    });

    testWidgets(
        'F020: the Library list carries the "screened by rules, not a '
        'clinician" disclosure', (tester) async {
      await _pumpLibrary(tester, _seededRepo());
      expect(find.byType(SafetyDisclosure), findsOneWidget);
    });

    /// G-B/B5 — every chip runs the whole eligibility layer, not just the
    /// injury filter.
    ///
    /// "For you" reads `rankedForYouProvider` -> `forYouExercisesProvider`,
    /// which already applied `eligibleExercises`. Every other chip read
    /// `safeCatalogProvider`, which applies `safeFor` — injuries and nothing
    /// else. A user under a movement restriction therefore saw the same
    /// exercise removed from one chip and present in the next, on one screen,
    /// with nothing to say which list was the honest one.
    group('B5: a movement restriction reaches every chip', () {
      AssetEquipmentRepository repoWithOverhead() =>
          AssetEquipmentRepository()
            ..seedForTests(
              equipment: const [
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
                  id: 'ohp',
                  title: 'Overhead press',
                  equipmentId: 'rack',
                  muscles: ['shoulders'],
                  difficulty: ExerciseDifficulty.beginner,
                  durationMinutes: 10,
                  summary: 'Pressing overhead',
                  steps: [],
                  // The tag `MovementRestriction.overhead` screens on.
                  contraindications: ['shoulder'],
                  video: {'men': 'https://cdn.example.com/ohp.mp4'},
                ),
                ExerciseItem(
                  id: 'lateral',
                  title: 'Lateral raise',
                  equipmentId: 'rack',
                  muscles: ['shoulders'],
                  difficulty: ExerciseDifficulty.beginner,
                  durationMinutes: 10,
                  summary: 'Not overhead',
                  steps: [],
                  video: {'men': 'https://cdn.example.com/lat.mp4'},
                ),
              ],
            );

      SafetyContext restricted() => SafetyContext(
            screening:
                screen({for (final q in ParQQuestion.values) q: false}),
            health: const HealthFlags(
              restrictions: {MovementRestriction.overhead},
            ),
          );

      testWidgets('the Shoulders chip drops the restricted movement',
          (tester) async {
        await _pumpLibrary(tester, repoWithOverhead(), safety: restricted());
        await _tapChip(tester, 'Shoulders');

        expect(find.text('Overhead press'), findsNothing);
        expect(find.text('Lateral raise'), findsOneWidget,
            reason: 'the chip must filter, not empty itself');
      });

      testWidgets('so does the All chip', (tester) async {
        // A separate branch of the same resolver, and the one a user reaches
        // when a muscle chip looks short.
        await _pumpLibrary(tester, repoWithOverhead(), safety: restricted());
        await _tapChip(tester, 'All');

        expect(find.text('Overhead press'), findsNothing);
        expect(find.text('Lateral raise'), findsOneWidget);
      });

      testWidgets('CONTROL: an unrestricted user sees both', (tester) async {
        await _pumpLibrary(tester, repoWithOverhead());
        await _tapChip(tester, 'Shoulders');

        expect(find.text('Overhead press'), findsOneWidget);
        expect(find.text('Lateral raise'), findsOneWidget);
      });
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
      //
      // B2a: English, because the harness locale is English. It read
      // 'Силовая база' until the titles moved into the ARB files.
      expect(find.text('Strength base'), findsOneWidget);
    });

    testWidgets('switching to Library and back preserves both tabs\' content',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('Strength base'), findsNothing);

      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();
      expect(find.text('Strength base'), findsOneWidget);
      expect(find.text('For you'), findsNothing);
    });

    testWidgets('no current-programme card when nothing is active',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workouts.currentProgramme')), findsNothing);
    });

    testWidgets(
        'an active programme shows the current-programme card with '
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

      expect(
          find.byKey(const Key('workouts.currentProgramme')), findsOneWidget);
      expect(find.textContaining('Week 2 of 8'), findsOneWidget);
    });

    // B5d-2. The catalogue was the only way in: a user who had answered 34
    // questions still had to pick one of six templates and hope it matched.
    group('the build-from-answers card', () {
      /// Pumps the Programs tab with [profile] as the stored questionnaire.
      ///
      /// `screeningProfileProvider` is overridden rather than seeded through a
      /// profile repository for the same reason the current-programme tests
      /// override `activeProgrammeProvider` directly: a broadcast-stream mock
      /// is a hang risk in a widget test, and what is under test here is the
      /// card, not how the profile was loaded.
      Future<void> pumpWith(WidgetTester tester, UserProfile? profile) async {
        final router = GoRouter(
          initialLocation: '/workouts',
          routes: [
            GoRoute(
                path: '/workouts', builder: (_, __) => const WorkoutsPage()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
              screeningProfileProvider.overrideWith((ref) async => profile),
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
      }

      testWidgets(
          'is absent when the questionnaire holds nothing to build from',
          (tester) async {
        await pumpWith(tester, const UserProfile(uid: 'alice'));

        expect(find.byKey(const Key('programme.fromAnswers')), findsNothing);
        // The templates are still the way in, so the tab is not left empty.
        expect(find.text('Strength base'), findsOneWidget);
      });

      testWidgets('is absent for a signed-out user', (tester) async {
        await pumpWith(tester, null);
        expect(find.byKey(const Key('programme.fromAnswers')), findsNothing);
      });

      testWidgets(
          'appears once the questionnaire has answers, and states the '
          'cadence it will actually build', (tester) async {
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(primary: ProgrammeGoal.muscle),
            level: FitnessLevel(tier: FitnessTier.advanced),
            // Four days asked for, three weekdays ticked: the card must say
            // three, because three is what the enrolment will generate.
            schedule:
                TrainingSchedule(daysPerWeek: 4, preferredWeekdays: [1, 3, 5]),
          ),
        );

        expect(find.byKey(const Key('programme.fromAnswers')), findsOneWidget);
        final card = find.byKey(const Key('programme.fromAnswers'));
        expect(find.descendant(of: card, matching: find.text('Muscle')),
            findsOneWidget);
        expect(find.descendant(of: card, matching: find.text('Advanced')),
            findsOneWidget);
        expect(
          find.descendant(
              of: card, matching: find.textContaining('3 days/week')),
          findsOneWidget,
          reason: 'the card promised a cadence the schedule would not deliver',
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('8 weeks')),
          findsOneWidget,
        );
      });

      testWidgets(
          'survives a goal-filter tap, since it is not one of the '
          'filtered templates', (tester) async {
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(primary: ProgrammeGoal.muscle),
          ),
        );
        expect(find.byKey(const Key('programme.fromAnswers')), findsOneWidget);

        // Scoped to the filter row on purpose: 'Strength' is also the goal
        // chip printed on the `strength_base` card, so an unscoped
        // `find.text` matches two widgets and `_tapChip` throws on the
        // ambiguity rather than tapping the wrong one.
        final filterChip =
            find.descendant(of: _chipRow, matching: find.text('Strength'));
        await tester.ensureVisible(filterChip);
        await tester.pumpAndSettle();
        await tester.tap(filterChip);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('programme.fromAnswers')), findsOneWidget);
        expect(find.text('Hypertrophy'), findsNothing,
            reason: 'the goal filter itself stopped working');
      });

      testWidgets('at 320dp with large text the card lays out without overflow',
          (tester) async {
        // The three chips are a Wrap for exactly this case — the template
        // cards' own header chips clipped here before Bug 5.
        tester.view.physicalSize = const Size(320, 1400);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(primary: ProgrammeGoal.weightLoss),
            level: FitnessLevel(tier: FitnessTier.beginner),
            schedule: TrainingSchedule(daysPerWeek: 4),
          ),
        );

        expect(find.byKey(const Key('programme.fromAnswers')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    // B5d-3. Six programmes sat in the order they happen to occupy in
    // `programmeTemplates`, so someone who had answered the questionnaire still
    // had to read all six and work out which was theirs.
    group('templates are ranked as recommendations', () {
      Future<void> pumpWith(WidgetTester tester, UserProfile? profile) async {
        final router = GoRouter(
          initialLocation: '/workouts',
          routes: [
            GoRoute(
                path: '/workouts', builder: (_, __) => const WorkoutsPage()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
              screeningProfileProvider.overrideWith((ref) async => profile),
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
      }

      /// Template card titles in the order they are laid out on screen.
      ///
      /// MVP Gate M2: `_ProgrammeTemplateCard`'s outer widget is now
      /// `HudPanel` (the HUD handoff reskin), not `GlassCard` — a deliberate
      /// architectural swap this gate makes, not a regression, so the finder
      /// follows the card to its new wrapper.
      List<String> renderedOrder(WidgetTester tester) {
        final cards = find.byWidgetPredicate((w) =>
            w is HudPanel &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>)
                .value
                .startsWith('programme.template.'));
        final ids = tester
            .widgetList<HudPanel>(cards)
            .map((w) => (w.key as ValueKey<String>).value)
            .toList();
        // Laid out top-to-bottom, so tree order is visual order here.
        return ids;
      }

      testWidgets(
          'an unanswered questionnaire leaves the catalogue order and '
          'claims nothing', (tester) async {
        await pumpWith(tester, const UserProfile(uid: 'alice'));

        expect(renderedOrder(tester).first, 'programme.template.strength_base');
        expect(find.byKey(const Key('programme.bestMatch')), findsNothing);
        expect(find.byKey(const Key('programme.fitReason')), findsNothing);
      });

      testWidgets('the best-fitting programme moves to the top and says why',
          (tester) async {
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(
                primary: ProgrammeGoal.muscle, focusZones: [FocusZone.arms]),
            level: FitnessLevel(tier: FitnessTier.intermediate),
            schedule: TrainingSchedule(daysPerWeek: 3),
          ),
        );

        expect(
            renderedOrder(tester).first, 'programme.template.shoulders_arms');
        // Exactly one badge — two "best" cards is not a recommendation.
        expect(find.byKey(const Key('programme.bestMatch')), findsOneWidget);
        expect(
          find.text('Matches your goal, level, schedule, focus areas'),
          findsOneWidget,
        );
      });

      testWidgets(
          'a single answer ranks by that answer alone, without '
          'claiming the others', (tester) async {
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(primary: ProgrammeGoal.comeback),
          ),
        );

        expect(
            renderedOrder(tester).first, 'programme.template.injury_comeback');
        expect(find.text('Matches your goal'), findsOneWidget);
        // Scoped to the reason lines: the build-from-answers card's own hint
        // legitimately contains the word "level", and an unscoped finder
        // catches that instead of what is under test.
        for (final text in tester
            .widgetList<Text>(find.byKey(const Key('programme.fitReason')))) {
          expect(text.data, 'Matches your goal',
              reason: 'claimed a match on a question that was never answered');
        }
      });

      testWidgets('no badge when two programmes fit equally well',
          (tester) async {
        // Answering only "three days a week" matches every 3-day template.
        // The app has no basis for calling one of them best, so it says so by
        // not saying anything.
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            schedule: TrainingSchedule(daysPerWeek: 3),
          ),
        );

        expect(find.byKey(const Key('programme.bestMatch')), findsNothing);
        expect(find.byKey(const Key('programme.fitReason')), findsWidgets,
            reason: 'the matches themselves are still worth showing');
      });

      testWidgets('ranking stays inside the goal filter the user set',
          (tester) async {
        await pumpWith(
          tester,
          const UserProfile(
            uid: 'alice',
            goals: FitnessGoals(primary: ProgrammeGoal.muscle),
            schedule: TrainingSchedule(daysPerWeek: 3),
          ),
        );

        final chip =
            find.descendant(of: _chipRow, matching: find.text('Strength'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();

        // A goal chip is the user narrowing the catalogue by hand; ranking
        // must not pull a better-fitting programme back across it.
        expect(renderedOrder(tester), ['programme.template.strength_base']);
      });
    });

    // B5c. The card named a programme and drew a bar; it never showed a single
    // movement, so what the week actually contains had to be taken on trust.
    group('the current-programme card shows the next day as pictures', () {
      Programme active() => Programme(
            id: 'prog_1',
            templateId: 'strength_base',
            title: 'Силовая база',
            goal: ProgrammeGoal.strength,
            level: ExerciseDifficulty.intermediate,
            weeks: 8,
            daysPerWeek: 4,
            startedAt: DateTime.now().subtract(const Duration(days: 8)),
          );

      ScheduledSession dayOf(List<String> ids) => ScheduledSession(
            id: 'day_1',
            exerciseId: ids.first,
            exerciseTitle: ids.first,
            scheduledFor: DateTime.now().add(const Duration(hours: 2)),
            durationMinutes: 40,
            programmeId: 'prog_1',
            extraExercises: [
              for (final id in ids.skip(1))
                WorkoutSessionExercise(exerciseId: id, exerciseTitle: id),
            ],
          );

      ExerciseItem item(String id) => ExerciseItem.fromJson({
            'id': id,
            'title': id,
            'durationMinutes': 10,
            'difficulty': 'beginner',
            'muscles': const ['quadriceps'],
            'steps': const ['a', 'b', 'c'],
          });

      Future<void> pumpCard(
        WidgetTester tester, {
        required List<String> ids,
        Set<String> injured = const {},
        Size size = const Size(400, 1400),
        double textScale = 1.0,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final programme = active();
        final router = GoRouter(
          initialLocation: '/workouts',
          routes: [
            GoRoute(
                path: '/workouts', builder: (_, __) => const WorkoutsPage()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
              activeProgrammeProvider.overrideWithValue(programme),
              activeProgrammeProgressProvider.overrideWithValue(
                deriveProgrammeProgress(programme, const []),
              ),
              upcomingSessionsProvider.overrideWithValue([dayOf(ids)]),
              // Overridden directly so the test states the safety verdict it
              // is testing, instead of building an injury profile and hoping
              // the catalogue produces the verdict by side effect.
              exerciseResolutionProvider.overrideWith((ref, id) async =>
                  injured.contains(id)
                      ? ExerciseResolution.hiddenForInjury(item(id))
                      : ExerciseResolution.found(item(id))),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light(),
              locale: kTestLocale,
              localizationsDelegates: kTestLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final thumbs = find.descendant(
        of: find.byKey(const Key('workouts.currentProgramme.thumbs')),
        matching: find.byType(ExerciseThumb),
      );

      testWidgets('one tile per exercise of the day', (tester) async {
        await pumpCard(tester, ids: ['squat', 'row', 'press']);

        expect(thumbs, findsNWidgets(3));
        expect(
          tester.widgetList<ExerciseThumb>(thumbs).map((t) => t.exercise?.id),
          ['squat', 'row', 'press'],
        );
      });

      testWidgets(
          'a contraindicated exercise keeps its slot but loses its '
          'picture', (tester) async {
        // The safety rule, at the one place it is easiest to break by accident:
        // a thumbnail is a picture of the movement, so drawing one for an
        // exercise the user must not do surfaces exactly what the filter
        // exists to withhold. The slot stays so the day's size is still
        // honest -- silently dropping it would under-report the day.
        await pumpCard(tester,
            ids: ['squat', 'row', 'press'], injured: {'row'});

        expect(thumbs, findsNWidgets(3), reason: 'the day is still three long');
        expect(
          tester.widgetList<ExerciseThumb>(thumbs).map((t) => t.exercise?.id),
          ['squat', null, 'press'],
          reason: 'the contraindicated exercise must reach the tile as null',
        );
      });

      testWidgets(
          'H4: a screen reader hears the exercise name per tile, and stays '
          'silent for the one withheld for injury', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCard(tester,
            ids: ['squat', 'row', 'press'], injured: {'row'});

        // `item()` seeds `title: id`, so the label is the id itself here.
        expect(tester.getSemantics(find.bySemanticsLabel('squat')).label,
            'squat');
        expect(tester.getSemantics(find.bySemanticsLabel('press')).label,
            'press');
        // The withheld tile must not announce the name it isn't showing a
        // picture of -- same reason `_ThumbPlaceholder` stays silent while
        // loading, applied to the exercise this slot is hiding.
        expect(find.bySemanticsLabel('row'), findsNothing);
        handle.dispose();
      });

      testWidgets('a long day is counted, not crammed, and never overflows',
          (tester) async {
        // 320px wide: the narrow phone where a fixed five tiles would not fit.
        // The previous gate shipped a real 31px overflow from an unbounded Row,
        // so this asserts the absence of one rather than assuming it.
        await pumpCard(
          tester,
          ids: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
          size: const Size(320, 1400),
        );

        expect(tester.takeException(), isNull);
        final drawn = tester.widgetList<ExerciseThumb>(thumbs).length;
        expect(drawn, lessThan(7), reason: 'seven tiles cannot fit 320px');
        expect(find.text('+${7 - drawn}'), findsOneWidget,
            reason: 'what is left out has to be stated, not dropped');
      });

      testWidgets('nor at 320dp with the largest text size', (tester) async {
        // The convention this card already has for its header chips
        // (`workouts/programme_card_chip_overflow_test.dart` — 320dp AND
        // textScale 1.6). The tiles are fixed-size but the "+N" beside them is
        // text, so it grows with the setting and the row has to still fit.
        await pumpCard(
          tester,
          ids: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
          size: const Size(320, 1400),
          textScale: 1.6,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('workouts.currentProgramme.thumbs')),
            findsOneWidget);
      });
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

      expect(find.text('Hypertrophy'), findsOneWidget);
      expect(find.text('Gym starter'), findsNothing);
    });

    testWidgets('tapping Start on a template reaches the enroll action',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start programme').first);
      await tester.pumpAndSettle();

      // No signed-in user is overridden in this harness, so the action fails
      // and the failure snackbar appears -- proof the tap reached
      // `ProgrammeAction.enroll` rather than doing nothing.
      //
      // The assertion is on the Retry action, not on the message. The message
      // used to be "Couldn't start this programme: $e" and carried the raw
      // Firestore exception into the UI; it is now a fixed localized string
      // shared with every other service failure, so matching on it would tie
      // this test to copy that says nothing about enrolment. The Retry button
      // is what makes this snackbar the *enrolment* failure specifically.
      expect(find.widgetWithText(SnackBar, 'Retry'), findsOneWidget);
    });

    testWidgets(
        'N01: a safety-blocked enrolment does not render as a service error, '
        'and offers no retry', (tester) async {
      // strength_base has a declared ProgrammeSpec, so this profile reaches
      // `buildProgramme`'s safety check and throws
      // ProgrammeNotViable(blockedBySafety) — not the "no signed-in user"
      // exception the sibling test above uses, which is why that one still
      // exercises the generic service-error branch and this one must not.
      final router = GoRouter(
        initialLocation: '/workouts',
        routes: [
          GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
          authUserProvider.overrideWith((_) => Stream.value(
              const AuthUser(uid: 'u1', displayName: 'Tester'))),
          // chestPain is a kBlockingQuestions member: this profile is
          // refused ALL training, not screened for one exercise.
          safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({
                for (final q in ParQQuestion.values)
                  q: q == ParQQuestion.chestPain,
              }))),
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
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start programme').first);
      await tester.pumpAndSettle();

      // Mutation check for this test: reverting the error branch to the old
      // single SnackBar makes this fail (finds the Retry snackbar, not the
      // dialog) — that is the point of asserting both sides.
      expect(find.widgetWithText(SnackBar, 'Retry'), findsNothing);
      expect(find.text(AppLocalizations.of(tester.element(find.byType(WorkoutsPage)))
          .errorServiceUnavailable), findsNothing);
      expect(find.byKey(const Key('programme.enrol.blocked')), findsOneWidget);
    });

    testWidgets(
        'F017: a chest-pain block on the Library list renders urgent '
        'wording, not the routine "no sessions" one', (tester) async {
      // This is the second of the two render sites F017 named — the first,
      // the onboarding SafetyRefusalCard, has its own dedicated test. This
      // one is EligibilityNotice, which every non-onboarding surface
      // (Train tab, this Library list, the N01 dialog above) renders
      // through, and which used to say the same "No sessions right now"
      // regardless of what caused the block.
      final router = GoRouter(
        initialLocation: '/workouts',
        routes: [
          GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
          safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({
                for (final q in ParQQuestion.values)
                  q: q == ParQQuestion.chestPain,
              }))),
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
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      final l10n =
          AppLocalizations.of(tester.element(find.byType(WorkoutsPage)));
      expect(find.text(l10n.eligTrainingBlockedUrgentTitle), findsOneWidget);
      expect(find.text(l10n.eligTrainingBlockedTitle), findsNothing);
    });
  });
}
