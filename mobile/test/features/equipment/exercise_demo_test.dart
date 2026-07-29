import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_demo.dart';
import 'package:fitness_app/features/equipment/widgets/muscle_map.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('ExerciseDemo', () {
    const frames = ['assets/exercises/x/0.jpg', 'assets/exercises/x/1.jpg'];

    testWidgets('advances through frames while playing', (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();

      Image shown() => tester.widgetList<Image>(find.byType(Image)).last;
      final first = (shown().image as AssetImage).assetName;

      // 1x tempo is 900ms; step past it and the other frame is on screen.
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump(const Duration(milliseconds: 300)); // finish fade
      final second = (shown().image as AssetImage).assetName;

      expect(second, isNot(first));
      expect(frames, containsAll(<String>[first, second]));
    });

    testWidgets('pause stops advancing', (tester) async {
      await tester.pumpWidget(_wrap(const ExerciseDemo(frames: frames)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('exercise-demo-play')));
      await tester.pump();
      final paused = (tester.widgetList<Image>(find.byType(Image)).last.image
              as AssetImage)
          .assetName;

      await tester.pump(const Duration(seconds: 3));
      final still = (tester.widgetList<Image>(find.byType(Image)).last.image
              as AssetImage)
          .assetName;
      expect(still, paused);
    });

    testWidgets('a single frame renders as a still with no crash',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const ExerciseDemo(frames: ['assets/exercises/x/0.jpg'])));
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
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
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
        'frames': ['assets/exercises/x/0.jpg', 'assets/exercises/x/1.jpg'],
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
