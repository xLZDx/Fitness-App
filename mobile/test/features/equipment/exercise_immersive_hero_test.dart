import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_reference.dart';
import '../../helpers/test_app.dart';

/// R11d replaced the 56px card hero with the design's 260px immersive header
/// and added the three-up stats row (`App.tsx:2818-2885`).
///
/// The poster-bearing path is deliberately NOT driven here: `Image.asset` on a
/// path that is not in the test bundle raises inside the image stream, and
/// mocking an asset bundle to prove `BoxFit.cover` was passed would test
/// Flutter rather than this widget. What is covered is everything the widget
/// itself decides — the no-media state, the title, the chip, and every branch
/// of the stats row.

ExerciseItem _ex({
  String title = 'Barbell Bench Press',
  List<String> muscles = const ['chest', 'triceps'],
  ExerciseDifficulty difficulty = ExerciseDifficulty.intermediate,
  String? equipmentLabel,
  String? equipmentId,
  bool isStretch = false,
}) =>
    ExerciseItem(
      id: 'bench',
      title: title,
      equipmentId: equipmentId,
      equipmentLabel: equipmentLabel,
      muscles: muscles,
      primaryMuscles: muscles.take(1).toList(),
      difficulty: difficulty,
      durationMinutes: 12,
      summary: '',
      steps: const [],
      isStretch: isStretch,
    );

void main() {
  group('ExerciseImmersiveHero', () {
    testWidgets('shows the name over the artwork', (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseImmersiveHero(exercise: _ex(), onBack: () {}),
      ));
      await tester.pump();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
    });

    testWidgets('an exercise with no clip says so instead of showing a blank',
        (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseImmersiveHero(exercise: _ex(), onBack: () {}),
      ));
      await tester.pump();

      expect(find.text('Animation unavailable'), findsOneWidget,
          reason: '168 catalogue rows have no clip and so no still');
    });

    testWidgets('carries the muscle chip', (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseImmersiveHero(exercise: _ex(), onBack: () {}),
      ));
      await tester.pump();

      expect(find.text('Chest · Triceps'), findsOneWidget);
    });

    testWidgets('an exercise with no muscles listed shows no chip',
        (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseImmersiveHero(
            exercise: _ex(muscles: const []), onBack: () {}),
      ));
      await tester.pump();

      // Only the title text remains; an empty chip would be a floating pill
      // with nothing in it.
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('the back control is reachable and labelled', (tester) async {
      var popped = false;
      await tester.pumpWidget(testHarness(
        child: ExerciseImmersiveHero(
          exercise: _ex(),
          onBack: () => popped = true,
        ),
      ));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump();
      expect(popped, isTrue);
    });
  });

  group('ExerciseQuickStats', () {
    testWidgets('renders level, equipment and type', (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseQuickStats(
            exercise: _ex(equipmentLabel: 'Barbell')),
      ));
      await tester.pump();

      expect(find.text('Intermediate'), findsOneWidget);
      expect(find.text('Barbell'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('LEVEL'), findsOneWidget);
      expect(find.text('EQUIPMENT'), findsOneWidget);
      expect(find.text('TYPE'), findsOneWidget);
    });

    testWidgets('an exercise with no equipment label reads Bodyweight',
        (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseQuickStats(exercise: _ex()),
      ));
      await tester.pump();

      expect(find.text('Bodyweight'), findsOneWidget,
          reason: 'better than an empty tile or the vendor\'s null');
    });

    /// C3 follow-up. `equipmentLabel` is the vendor's own English free text,
    /// so this tile was the one untranslated string on a Russian card —
    /// "Cable Pulley Machine" under "ОБОРУДОВАНИЕ". The registry already
    /// carries the translation; this surface had simply never asked it.
    ///
    /// Resolved through `equipmentByIdProvider`, the same lookup the machine
    /// pages use, so there is no second mapping to keep in step.
    testWidgets('the registry name wins over the vendor label', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentByIdProvider('cable_machine').overrideWith(
            (ref) async => const EquipmentItem(
              id: 'cable_machine',
              name: 'Блочный тренажёр',
              manufacturer: '',
              category: 'strength',
              description: '',
            ),
          ),
        ],
        child: testHarness(
          child: ExerciseQuickStats(
            exercise: _ex(
                equipmentId: 'cable_machine',
                equipmentLabel: 'Cable Pulley Machine'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Блочный тренажёр'), findsOneWidget);
      expect(find.text('Cable Pulley Machine'), findsNothing);
    });

    testWidgets('an unresolvable id falls back to the vendor label',
        (tester) async {
      // Stale English beats an empty tile, and beats claiming bodyweight for
      // an exercise that names a machine.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          equipmentByIdProvider('ghost').overrideWith((ref) async => null),
        ],
        child: testHarness(
          child: ExerciseQuickStats(
            exercise: _ex(equipmentId: 'ghost', equipmentLabel: 'Some Machine'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Some Machine'), findsOneWidget);
    });

    testWidgets('a row with no equipmentId keeps the vendor words',
        (tester) async {
      // NO_EQUIPMENT is not a machine we failed to name: "Yoga Mat" and "Wall"
      // are the honest answer and must not be replaced by a registry lookup.
      await tester.pumpWidget(testHarness(
        child: ExerciseQuickStats(exercise: _ex(equipmentLabel: 'Yoga Mat')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Yoga Mat'), findsOneWidget);
    });

    testWidgets('a stretch reads Mobility, not Strength', (tester) async {
      await tester.pumpWidget(testHarness(
        child: ExerciseQuickStats(exercise: _ex(isStretch: true)),
      ));
      await tester.pump();

      expect(find.text('Mobility'), findsOneWidget);
      expect(find.text('Strength'), findsNothing);
    });
  });
}
