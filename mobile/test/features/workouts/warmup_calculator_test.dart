import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/widgets/warmup_calculator.dart';

void main() {
  group('rampForWorkingWeight', () {
    test('80kg working weight → 4-set ramp at 40/60/75/90%', () {
      final ramp = rampForWorkingWeight(80);
      expect(ramp, hasLength(4));
      expect(ramp[0].percent, 40);
      expect(ramp[0].kg, 32.5);  // 32.0 rounded to 2.5
      expect(ramp[0].reps, 8);
      expect(ramp[3].percent, 90);
      expect(ramp[3].kg, 72.5);  // 72.0 rounded to 2.5
      expect(ramp[3].reps, 1);
    });

    test('30kg working weight (under 40) → 3-set ramp', () {
      final ramp = rampForWorkingWeight(30);
      expect(ramp, hasLength(3));
      expect(ramp[0].percent, 50);
      expect(ramp[0].reps, 8);
      expect(ramp[2].percent, 90);
    });

    test('all weights round to nearest 2.5kg', () {
      final ramp = rampForWorkingWeight(100);
      for (final s in ramp) {
        expect(s.kg * 10 % 25, equals(0),
            reason: '${s.kg} should be a 2.5kg multiple');
      }
    });

    test('reps descend 8 → 5 → 3 → 1', () {
      final ramp = rampForWorkingWeight(120);
      expect(ramp.map((s) => s.reps).toList(), [8, 5, 3, 1]);
    });
  });
}
