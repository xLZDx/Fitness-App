import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// Bug 6, the programme-card half. The nav-circle half shipped with Ф2.
///
/// The header used to be `AppPalette.tileGradients[index % 5]` — a saturated
/// two-hue aurora ramp at full opacity, chosen by the card's position in the
/// **filtered** list. That second part is the defect worth a test: filtering
/// renumbers the survivors, so the same programme changed colour depending on
/// which chip was active. A user cannot learn "the violet one is my strength
/// programme" if violet moves.
///
/// The colour is now a function of the programme's goal, so it is stable, and
/// the wash is the prototype's own 0.20 -> 0.08 alpha rather than full
/// strength.

AssetEquipmentRepository _seededRepo() {
  return AssetEquipmentRepository()
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
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [equipmentRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// The header wash of a given programme card, read back off the widget tree.
List<Color> _headerColors(WidgetTester tester, String templateId) {
  // Found by "the Container that carries a gradient", not by position: the
  // card is wrapped in several Containers by GlassCard and which one comes
  // first is an implementation detail that already broke this finder once.
  final header = find.descendant(
    of: find.byKey(Key('programme.template.$templateId')),
    matching: find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).gradient != null),
  );
  expect(header, findsOneWidget);
  final decoration =
      tester.widget<Container>(header).decoration! as BoxDecoration;
  return (decoration.gradient! as LinearGradient).colors;
}

/// The horizontal goal-filter strip, so a chip tap cannot be confused with the
/// identically-worded muscle label printed on a card.
final Finder _filterRow = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
);

void main() {
  group('programme card wash (bug 6)', () {
    testWidgets('is keyed to the goal, not to the position in the list',
        (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();
      // R11i/L1: WorkoutsPage now opens on the Library sub-tab by default,
      // so this file (which reads the Programs-tab template cards) must
      // switch to it first -- see workouts_page_test.dart's own note.
      await tester.tap(find.text('Программы'));
      await tester.pumpAndSettle();

      // "Гипертрофия" is 2nd of six unfiltered and 1st of two under the
      // Muscle filter -- the exact renumbering the old `index % 5` reacted to.
      final before = _headerColors(tester, 'hypertrophy');

      await tester.tap(find
          .descendant(of: _filterRow, matching: find.text('Мышцы'))
          .first);
      await tester.pumpAndSettle();

      expect(_headerColors(tester, 'hypertrophy'), before,
          reason: 'the card changed colour because the list was filtered');

      // Negative control, so this test cannot pass vacuously: under the scheme
      // it replaced the card WOULD have changed, because "Гипертрофия" moves
      // from position 1 to position 0 and those two ramps differ.
      expect(AppPalette.tileGradients[1], isNot(AppPalette.tileGradients[0]));
    });

    testWidgets('is the goal hue at the prototype\'s own alpha, not a '
        'full-strength aurora ramp', (tester) async {
      await tester.pumpWidget(_harness(_seededRepo()));
      await tester.pumpAndSettle();
      // R11i/L1: WorkoutsPage now opens on the Library sub-tab by default,
      // so this file (which reads the Programs-tab template cards) must
      // switch to it first -- see workouts_page_test.dart's own note.
      await tester.tap(find.text('Программы'));
      await tester.pumpAndSettle();

      final colors = _headerColors(tester, 'strength_base');
      expect(colors, hasLength(2));
      expect(colors.first.a, closeTo(0.20, 0.001));
      expect(colors.last.a, closeTo(0.08, 0.001));
      for (final c in colors) {
        expect(
          (c.r, c.g, c.b),
          (
            AppPalette.programmeStrength.r,
            AppPalette.programmeStrength.g,
            AppPalette.programmeStrength.b,
          ),
        );
      }

      // The negative control: whatever the header is now, it must not be one
      // of the old ramps. Without this the assertions above would still pass
      // if someone reinstated `tileGradients` at a low alpha.
      for (final ramp in AppPalette.tileGradients) {
        expect(colors.map((c) => (c.r, c.g, c.b)).toList(),
            isNot(ramp.map((c) => (c.r, c.g, c.b)).toList()));
      }
    });
  });
}
