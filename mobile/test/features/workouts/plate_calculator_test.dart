import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/widgets/plate_calculator.dart';

void main() {
  group('solvePlateLoad', () {
    test('100kg with 20kg bar → 25+15 per side (greedy, fewest plates)',
        () {
      // (100 - 20) / 2 = 40 per side. Greedy descent picks 25 first, then 15.
      final r = solvePlateLoad(targetKg: 100);
      expect(r.platesPerSide, [25, 15]);
      expect(r.totalLoaded, 100);
      expect(r.isExact, isTrue);
    });

    test('60kg with 20kg bar → 20 per side, exact', () {
      final r = solvePlateLoad(targetKg: 60);
      expect(r.platesPerSide, [20]);
      expect(r.totalLoaded, 60);
      expect(r.isExact, isTrue);
    });

    test('22.5kg with 20kg bar → 1.25 per side', () {
      final r = solvePlateLoad(targetKg: 22.5);
      expect(r.platesPerSide, [1.25]);
      expect(r.totalLoaded, closeTo(22.5, 0.01));
      expect(r.isExact, isTrue);
    });

    test('weight at or under bar weight → no plates', () {
      final r = solvePlateLoad(targetKg: 20);
      expect(r.platesPerSide, isEmpty);
      expect(r.totalLoaded, 20);
    });

    test('odd target rounds down with residual', () {
      final r = solvePlateLoad(targetKg: 23);
      // (23-20)/2 = 1.5 per side. Closest plate set: 1.25.
      expect(r.platesPerSide, [1.25]);
      expect(r.residualKg, closeTo(0.5, 0.01));
      expect(r.isExact, isFalse);
    });

    test('greedy descent for 200kg', () {
      final r = solvePlateLoad(targetKg: 200);
      // (200-20)/2 = 90 per side: 25+25+25+15
      expect(r.platesPerSide, [25, 25, 25, 15]);
      expect(r.totalLoaded, 200);
    });
  });
}
