import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/features/equipment/widgets/muscle_map.dart';

/// Every muscle tag the catalog can emit, so a new one cannot be added without
/// a home on the chart.
const _catalogMuscles = {
  // front
  'shoulders', 'chest', 'biceps', 'forearms', 'core', 'quads', 'calves',
  // back
  'traps', 'lats', 'triceps', 'back', 'lower_back', 'glutes', 'hamstrings',
};

void main() {
  group('MuscleMap.loadFor', () {
    test('primary wins over secondary', () {
      expect(
        MuscleMap.loadFor('chest', primary: ['chest'], secondary: ['chest']),
        MuscleLoad.primary,
      );
    });

    test('secondary is reported when not primary', () {
      expect(
        MuscleMap.loadFor('chest', primary: ['lats'], secondary: ['chest']),
        MuscleLoad.secondary,
      );
    });

    test('an unlisted muscle is unloaded', () {
      expect(
        MuscleMap.loadFor('calves', primary: ['chest'], secondary: const []),
        MuscleLoad.none,
      );
    });
  });

  group('chart geometry', () {
    test('every catalog muscle has a shape on one of the two views', () {
      final drawn = {
        ...debugFrontMuscles().keys,
        ...debugBackMuscles().keys,
      };
      expect(drawn, containsAll(_catalogMuscles));
    });

    // Regression, 2026-07-30: the shapes were authored against a wider torso.
    // Narrowing it pushed the deltoids, lats and traps outside the outline, and
    // they rendered sheared off in mid-air. Shapes are now intersected with the
    // silhouette, so the assertion is that clipping left something behind —
    // a group that misses the body entirely would clip away to nothing.
    test('no muscle group clips away to nothing', () {
      for (final view in [debugFrontMuscles(), debugBackMuscles()]) {
        for (final entry in view.entries) {
          expect(entry.value, isNotEmpty, reason: '${entry.key} has no shapes');
          for (final shape in entry.value) {
            expect(shape.getBounds().isEmpty, isFalse,
                reason: '${entry.key} landed outside the body and was clipped '
                    'to nothing');
          }
        }
      }
    });

    test('every shape stays inside the body outline', () {
      final body = debugSilhouette().getBounds();
      for (final view in [debugFrontMuscles(), debugBackMuscles()]) {
        for (final entry in view.entries) {
          for (final shape in entry.value) {
            final b = shape.getBounds();
            // Clipping guarantees containment; this pins that the guard is
            // actually applied rather than accidentally bypassed.
            expect(body.contains(b.topLeft), isTrue,
                reason: '${entry.key} starts outside the body');
            expect(body.contains(b.bottomRight), isTrue,
                reason: '${entry.key} ends outside the body');
          }
        }
      }
    });

    test('bilateral groups are mirror-symmetric about the midline', () {
      // Chest, lats, quads and friends come in pairs built by mirroring, so
      // their combined bounds must be centred on x = 0.5.
      for (final key in ['chest', 'quads', 'calves', 'biceps']) {
        final shapes = debugFrontMuscles()[key]!;
        expect(shapes, hasLength(2), reason: '$key should be a pair');
        final left = shapes.first.getBounds();
        final right = shapes.last.getBounds();
        expect(left.left, closeTo(1 - right.right, 0.001), reason: key);
        expect(left.top, closeTo(right.top, 0.001), reason: key);
      }
    });
  });

  group('MuscleMap widget', () {
    testWidgets('renders both views without overflowing', (tester) async {
      await tester.pumpWidget(testHarness(
        child: const Center(
          child: SizedBox(
            width: 360,
            child: MuscleMap(
              primary: ['quads'],
              secondary: ['glutes', 'core'],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(MuscleMap), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives an empty muscle list', (tester) async {
      await tester.pumpWidget(testHarness(
        child: const Center(
          child: SizedBox(
            width: 300,
            child: MuscleMap(primary: []),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives an unknown muscle tag', (tester) async {
      await tester.pumpWidget(testHarness(
        child: const Center(
          child: SizedBox(
            width: 300,
            child: MuscleMap(primary: ['not_a_muscle']),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
