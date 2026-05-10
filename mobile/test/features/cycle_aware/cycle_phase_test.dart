import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';

void main() {
  group('phaseFor (28-day default)', () {
    test('day 1–5 = menstrual', () {
      for (var d = 1; d <= 5; d++) {
        expect(phaseFor(cycleDay: d), CyclePhase.menstrual,
            reason: 'day $d');
      }
    });
    test('day 6–12 = follicular', () {
      for (var d = 6; d <= 12; d++) {
        expect(phaseFor(cycleDay: d), CyclePhase.follicular,
            reason: 'day $d');
      }
    });
    test('day 13–15 = ovulatory', () {
      for (var d = 13; d <= 15; d++) {
        expect(phaseFor(cycleDay: d), CyclePhase.ovulatory,
            reason: 'day $d');
      }
    });
    test('day 16+ = luteal', () {
      for (var d = 16; d <= 28; d++) {
        expect(phaseFor(cycleDay: d), CyclePhase.luteal, reason: 'day $d');
      }
    });
  });

  group('hintFor', () {
    test('intensity factor never exceeds 1.15 or drops below 0.5', () {
      for (final p in CyclePhase.values) {
        final h = hintFor(p);
        expect(h.intensityFactor, greaterThanOrEqualTo(0.5));
        expect(h.intensityFactor, lessThanOrEqualTo(1.15));
      }
    });
    test('luteal phase prefers tempo / mobility', () {
      final h = hintFor(CyclePhase.luteal);
      expect(h.preferredTags, contains('tempo'));
    });
  });
}
