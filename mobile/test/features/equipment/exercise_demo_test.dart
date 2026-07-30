import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_demo.dart';
import 'package:fitness_app/features/equipment/widgets/muscle_map.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('ExerciseDemo', () {
    const frames = ['assets/exercises/x_0.jpg', 'assets/exercises/x_1.jpg'];

    /// Opacity of the frame at [asset], or null when it is not mounted.
    ///
    /// Both frames stay in the tree and cross-fade, so which one the user sees
    /// is a question about opacity, not about which Image exists. The old tests
    /// read `.last` and compared asset names, which cannot distinguish "holding
    /// the start position" from "half way through the transition" — the very
    /// thing the cadence is about.
    double? opacityOf(WidgetTester tester, String asset) {
      final finder = find.ancestor(
        of: find.image(AssetImage(asset)),
        matching: find.byType(Opacity),
      );
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Opacity>(finder.first).opacity;
    }

    testWidgets('holds the start position before moving', (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();

      // The first fifth of the cycle is a deliberate hold: a rep pauses at the
      // end of the range, and without that the loop reads as a dissolve.
      expect(opacityOf(tester, frames[0]), 1.0);
      await tester.pump(const Duration(milliseconds: 120)); // < 20% of 900ms
      expect(opacityOf(tester, frames[0]), 1.0);
      expect(opacityOf(tester, frames[1]), 0.0);
    });

    testWidgets('crosses over mid-transition, then holds the end position',
        (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 450)); // mid-travel
      final mid = opacityOf(tester, frames[1])!;
      expect(mid, greaterThan(0.1));
      expect(mid, lessThan(0.9));

      await tester.pump(const Duration(milliseconds: 300)); // into the end hold
      expect(opacityOf(tester, frames[1]), 1.0);
    });

    testWidgets('advances so the loop keeps running', (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();

      // A full cycle swaps which frame the transition starts from, so with two
      // frames the demo runs back the other way rather than snapping.
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump(const Duration(milliseconds: 120));
      expect(opacityOf(tester, frames[1]), 1.0);
      expect(opacityOf(tester, frames[0]), 0.0);
    });

    testWidgets('pause freezes the current position', (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      await tester.tap(find.byKey(const Key('exercise-demo-play')));
      await tester.pump();
      final paused = opacityOf(tester, frames[1]);

      await tester.pump(const Duration(seconds: 3));
      expect(opacityOf(tester, frames[1]), paused);
    });

    testWidgets('speed changes the cycle length', (tester) async {
      // The travel phase runs from 20% to 80% of the cycle, so 380ms lands in
      // the end hold at 2x (450ms cycle, hold from 360ms) but still mid-travel
      // at 1x (900ms cycle, hold from 720ms). Asserting both is what makes this
      // a test of the SPEED rather than of the curve.
      const probe = Duration(milliseconds: 380);

      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();
      await tester.pump(probe);
      expect(opacityOf(tester, frames[1]), lessThan(0.9), reason: 'at 1x');

      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();
      await tester.tap(find.text('2x'));
      await tester.pump();
      await tester.pump(probe);
      expect(opacityOf(tester, frames[1]), 1.0, reason: 'at 2x');
    });

    testWidgets('a single frame renders as a still with no crash',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const ExerciseDemo(frames: ['assets/exercises/x_0.jpg'])));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('MuscleMap', () {
    test('classifies regions by how hard they are worked', () {
      const primary = ['quads'];
      const secondary = ['glutes'];
      expect(MuscleMap.loadFor('quads', primary: primary, secondary: secondary),
          MuscleLoad.primary);
      expect(
          MuscleMap.loadFor('glutes', primary: primary, secondary: secondary),
          MuscleLoad.secondary);
      expect(MuscleMap.loadFor('lats', primary: primary, secondary: secondary),
          MuscleLoad.none);
    });

    testWidgets('renders both views without throwing', (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(
          width: 320,
          height: 220,
          child: MuscleMap(primary: ['chest'], secondary: ['triceps']),
        ),
      ));
      await tester.pump();
      // Smoke check only: mounting the chart must not throw, including before
      // its artwork has loaded.
      //
      // Deliberately NOT waiting for the SVG here. Doing that needs
      // `tester.runAsync`, which also lets google_fonts fire its real HTTP
      // fetch — this file pumps with `AppTheme.light()`, so the test would fail
      // on a font download rather than on anything about the chart. Rendering
      // from the real artwork is covered in muscle_map_test.dart, which wraps in
      // a plain theme.
      //
      // The previous assertion here was `find.byType(CustomPaint), findsWidgets`,
      // which any Material ancestor satisfies on its own — it asserted nothing.
      expect(tester.takeException(), isNull);
      expect(find.byType(MuscleMap), findsOneWidget);
    });
  });

  group('catalog schema', () {
    test('ExerciseItem parses frames and primaryMuscles', () {
      final item = ExerciseItem.fromJson(const {
        'id': 'x',
        'title': 'X',
        'equipmentId': 'treadmill',
        'muscles': ['quads', 'calves'],
        'primaryMuscles': ['quads'],
        'difficulty': 'beginner',
        'durationMinutes': 8,
        'summary': 's',
        'steps': ['a'],
        'frames': ['assets/exercises/x_0.jpg', 'assets/exercises/x_1.jpg'],
        'contraindications': ['knee'],
      });
      expect(item.frames, hasLength(2));
      expect(item.primaryMuscles, ['quads']);
    });

    test('older entries without frames still parse', () {
      final item = ExerciseItem.fromJson(const {
        'id': 'y',
        'title': 'Y',
        'equipmentId': null,
        'muscles': ['core'],
        'difficulty': 'beginner',
        'durationMinutes': 5,
        'summary': '',
        'steps': <String>[],
      });
      expect(item.frames, isEmpty);
      expect(item.primaryMuscles, isEmpty);
    });
  });
}
