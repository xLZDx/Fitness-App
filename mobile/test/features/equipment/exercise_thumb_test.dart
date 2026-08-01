import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_thumb.dart';

/// One tile, five call sites.
///
/// Every list rendered an exercise as a gradient square with a play triangle,
/// coloured by `id.hashCode % 5` — so five in a row looked interchangeable and
/// none of them told you what the movement was. The posters bundled for the
/// video player answer that for free.
ExerciseItem _ex({Map<String, String> poster = const {}}) => ExerciseItem(
      id: 'x',
      title: 'X',
      equipmentId: null,
      muscles: const ['core'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      poster: poster,
    );

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: w))),
    );

void main() {
  testWidgets('an exercise with a poster shows it', (t) async {
    await _pump(
        t,
        ExerciseThumb(
          exercise: _ex(poster: const {'men': 'assets/posters/men/barbell_squat.jpg'}),
        ));
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/posters/men/barbell_squat.jpg');
  });

  testWidgets('an exercise without one falls back rather than breaking',
      (t) async {
    await _pump(t, ExerciseThumb(exercise: _ex()));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
  });

  testWidgets('a null exercise still renders a tile', (t) async {
    // The home page has only a suggestion id in scope. It should still get the
    // same shape as everywhere else rather than inventing its own.
    await _pump(t, const ExerciseThumb(exercise: null, size: 44));
    expect(tester_size(t), const Size(44, 44));
  });

  testWidgets('the body preference picks the matching poster', (t) async {
    final ex = _ex(poster: const {
      'girl': 'assets/posters/girl/barbell_squat.jpg',
      'men': 'assets/posters/men/barbell_squat.jpg',
    });
    await _pump(t, ExerciseThumb(exercise: ex, body: 'girl'));
    expect((t.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
        contains('/girl/'));
  });

  testWidgets('radius scales with the tile, so sizes stay one shape',
      (t) async {
    // The five call sites had drifted to 44/48/56 px with radius 14/15/18 —
    // three different roundings for what is meant to be one component.
    for (final size in [44.0, 52.0, 56.0]) {
      await _pump(t, ExerciseThumb(exercise: _ex(), size: size));
      final box = t.widget<Container>(find.byType(Container).first);
      final radius = ((box.decoration! as BoxDecoration).borderRadius!
              as BorderRadius)
          .topLeft
          .x;
      expect(radius / size, closeTo(0.31, 1e-9), reason: 'at $size');
    }
  });
}

Size tester_size(WidgetTester t) =>
    t.getSize(find.byType(ExerciseThumb));
