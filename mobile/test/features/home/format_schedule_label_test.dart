import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/home/home_page.dart';

void main() {
  group('formatScheduleLabel', () {
    final now = DateTime(2026, 5, 8, 12); // 2026-05-08 is Friday

    test('today', () {
      expect(formatScheduleLabel(DateTime(2026, 5, 8, 7, 30), now: now),
          'Today 07:30');
    });

    test('tomorrow', () {
      expect(formatScheduleLabel(DateTime(2026, 5, 9, 18, 0), now: now),
          'Tomorrow 18:00');
    });

    test('within the next week shows weekday name', () {
      expect(formatScheduleLabel(DateTime(2026, 5, 13, 9, 0), now: now),
          'Wed 09:00');
    });

    test('beyond the next week shows month/day', () {
      expect(formatScheduleLabel(DateTime(2026, 5, 28, 14, 5), now: now),
          'May 28 · 14:05');
    });

    test('zero-pads single-digit hours and minutes', () {
      expect(formatScheduleLabel(DateTime(2026, 5, 8, 9, 5), now: now),
          'Today 09:05');
    });
  });
}
