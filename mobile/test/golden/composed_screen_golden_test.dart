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
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

import '../support/golden_fonts.dart';

/// A minimal, deterministic catalogue -- not imported from
/// `workouts_page_test.dart` because its own `_seededRepo` is file-private
/// (Dart privacy is per-library), and this golden intentionally wants the
/// smallest fixture that renders a non-empty Programs tab, not that file's
/// larger assertion-driven fixture set.
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
          video: {'men': 'https://cdn.example.com/run.mp4'},
        ),
      ],
    );
}

/// MVP1.G3 OBS-1 item 6 -- composed-screen visual regression coverage.
///
/// `hud_golden_test.dart` deliberately excludes a full-screen composition
/// (its own doc comment names `HomePage` explicitly) -- this file is that
/// follow-up, scoped to the two highest-traffic screens that mix legacy
/// `GlassCard`/`AuroraBackground` chrome with the newer `Hud*` widget family:
/// Home and Workouts (Programs tab, its default sub-tab per R11i). This is
/// exactly the surface class where the shipped WCAG contrast failure (see
/// core/MASTER_PLAN_2026-08-26.md Sec3) actually occurred -- a bug two
/// isolated-widget goldens and a manual review both missed, because neither
/// looks at how the pieces sit together.
///
/// Deliberately NOT in scope: turning this into the HUD redesign/migration
/// project (`core/MASTER_PLAN_2026-08-26.md`'s own item 7) -- this pins
/// TODAY's composition as a regression guard, it does not judge whether that
/// composition is the right one.
///
/// Both screens are pinned in their default/empty data state for the same
/// reason `hud_golden_test.dart` pins primitive states rather than every
/// possible one: a golden's job is catching an unintended pixel shift, not
/// enumerating product states (that is `home_page_test.dart` and
/// `workouts_page_test.dart`'s job, by assertion rather than pixel).
void main() {
  setUpAll(loadHudGoldenFonts);

  Future<void> settle(WidgetTester tester) async {
    // Composed screens carry more in-flight animations (frost blur, page
    // transition, list-item entrance) than a single primitive does --
    // several settle passes bound at a generous total budget, matching this
    // screen class's own existing tests' pump patterns rather than a single
    // hopeful `pumpAndSettle()` that could time out on the frost's looping
    // shader warm-up frame.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  group('Home (composed)', () {
    Widget buildHome(Brightness brightness) {
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
              builder: (_, __) =>
                  const Scaffold(body: Text('posture-stub'))),
        ],
      );
      return ProviderScope(
        overrides: [
          safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening:
                  screen({for (final q in ParQQuestion.values) q: false}))),
          // Without this, `forYouExercisesProvider` stays in AsyncLoading
          // (nothing here resolves it) and the Suggestions section renders
          // `_SuggestionsPlaceholder`'s indeterminate `CircularProgressIndicator`
          // forever -- an infinitely-animating widget by design, which is
          // exactly what made `pumpAndSettle` below hang until this override
          // was added. A resolved, deterministic list both fixes that and
          // makes the golden show the section's real composed content.
          forYouExercisesProvider.overrideWith((_) async => [
                ExerciseItem(
                  id: 'golden_ex_1',
                  title: 'Back squat',
                  equipmentId: null,
                  muscles: const ['quads'],
                  primaryMuscles: const ['quads'],
                  difficulty: ExerciseDifficulty.intermediate,
                  durationMinutes: 25,
                  summary: '',
                  steps: const [],
                ),
              ]),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              AuroraBackground(child: child ?? const SizedBox.shrink()),
        ),
      );
    }

    testWidgets('light', (tester) async {
      pinGoldenSurface(tester, size: const Size(400, 860));
      await tester.pumpWidget(buildHome(Brightness.light));
      await settle(tester);
      await expectLater(
        find.byType(HomePage),
        matchesGoldenFile('goldens/composed_home_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      pinGoldenSurface(tester, size: const Size(400, 860));
      await tester.pumpWidget(buildHome(Brightness.dark));
      await settle(tester);
      await expectLater(
        find.byType(HomePage),
        matchesGoldenFile('goldens/composed_home_dark.png'),
      );
    });
  });

  group('Workouts (composed, Programs tab)', () {
    Widget buildWorkouts(Brightness brightness) {
      final repo = _seededRepo();
      final router = GoRouter(
        initialLocation: '/workouts',
        routes: [
          GoRoute(
              path: '/workouts', builder: (_, __) => const WorkoutsPage()),
          GoRoute(
            path: '/workout/:id',
            builder: (_, state) => Scaffold(
                body: Center(
                    child: Text('player_${state.pathParameters['id']}'))),
          ),
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
          safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening:
                  screen({for (final q in ParQQuestion.values) q: false}))),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
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

    testWidgets('light', (tester) async {
      pinGoldenSurface(tester, size: const Size(400, 860));
      await tester.pumpWidget(buildWorkouts(Brightness.light));
      await settle(tester);
      await expectLater(
        find.byType(WorkoutsPage),
        matchesGoldenFile('goldens/composed_workouts_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      pinGoldenSurface(tester, size: const Size(400, 860));
      await tester.pumpWidget(buildWorkouts(Brightness.dark));
      await settle(tester);
      await expectLater(
        find.byType(WorkoutsPage),
        matchesGoldenFile('goldens/composed_workouts_dark.png'),
      );
    });
  });
}
