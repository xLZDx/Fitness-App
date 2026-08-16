import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  /// H4 — what a screen reader is actually handed.
  ///
  /// The finding was recorded as "`ExerciseThumb` carries no `Semantics`", with
  /// the evidence "no `Semantics` anywhere in `exercise_thumb.dart`". Both are
  /// true, and the conclusion drawn from them was wrong: the tile is DECORATIVE
  /// at five of its six call sites, where it sits in a `Row` directly beside a
  /// `Text` carrying the exercise title. A label on the picture there makes the
  /// name be read out twice.
  ///
  /// The sixth is the programme card's tile strip, which has no text per tile,
  /// and it already supplies its own `Semantics(label: title)` wrapper
  /// (`workouts_page.dart:1169`). So the change that was actually missing is the
  /// opposite of the one recorded: the image must be EXCLUDED, so it stops
  /// contributing an unnamed graphic node between the title and the next
  /// control on every list in the app.
  group('semantics', () {
    testWidgets('the poster contributes no node of its own', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
          t,
          ExerciseThumb(
            exercise: _ex(
                poster: const {'men': 'assets/posters/men/barbell_squat.jpg'}),
          ));
      expect(
        _announcesAnImage(t, find.byType(Image)),
        isFalse,
        reason: 'a decorative tile must not announce anything on its own',
      );
      handle.dispose();
    });

    testWidgets('beside a title, the name is announced exactly once', (t) async {
      // The shape of five of the six call sites.
      final handle = t.ensureSemantics();
      await _pump(
        t,
        Row(children: [
          ExerciseThumb(
              exercise: _ex(
                  poster: const {'men': 'assets/posters/men/barbell_squat.jpg'})),
          const Text('Barbell Squat'),
        ]),
      );
      expect(find.bySemanticsLabel('Barbell Squat'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('wrapped in a label, the name still gets through', (t) async {
      // The shape of the sixth. Excluding the image must not swallow a label
      // the call site deliberately added.
      final handle = t.ensureSemantics();
      await _pump(
        t,
        Semantics(
          label: 'Barbell Squat',
          image: true,
          excludeSemantics: true,
          child: ExerciseThumb(
              exercise: _ex(
                  poster: const {'men': 'assets/posters/men/barbell_squat.jpg'})),
        ),
      );
      expect(find.bySemanticsLabel('Barbell Squat'), findsOneWidget);
      handle.dispose();
    });
  });
}

Size tester_size(WidgetTester t) =>
    t.getSize(find.byType(ExerciseThumb));

/// Whether anything inside [finder] announces itself as an image.
///
/// Asked of the subtree rather than by label, because the node this is about
/// has NO label — which is exactly what makes it a problem: a screen reader
/// reaches an unnamed graphic and says so. A label-based finder cannot see it.
///
/// `SemanticsController.find` walks UP to the nearest node, which is why the
/// finder must be the `Image` itself rather than the tile around it: excluded,
/// the image has no node and this resolves to a plain ancestor; included, it
/// resolves to the image's own node and the flag is there. Pointed at the tile
/// instead, it walked past the very node under test and could not fail at all —
/// caught by mutation, not by reading it.
bool _announcesAnImage(WidgetTester t, Finder finder) =>
    t.semantics.find(finder).getSemanticsData().hasFlag(SemanticsFlag.isImage);
