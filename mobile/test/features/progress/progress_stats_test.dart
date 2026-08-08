import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress/data/progress_stats.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

WorkoutLogEntry _l(String id, DateTime when) => WorkoutLogEntry(
      id: id,
      exerciseId: 'pushup',
      exerciseTitle: 'Push-ups',
      completedAt: when,
      durationMinutes: 10,
    );

void main() {
  group('deriveProgress', () {
    test('empty history returns ProgressStats.empty', () {
      final stats = deriveProgress(const [], now: DateTime(2026, 5, 8));
      expect(stats.total, 0);
      expect(stats.thisWeek, 0);
      expect(stats.currentStreakDays, 0);
      expect(stats.longestStreakDays, 0);
      expect(stats.last8Weeks, [0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('counts total and this-week correctly', () {
      // 2026-05-08 is a Friday, so the week starts Monday 2026-05-04.
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 5, 4)),
        _l('b', DateTime(2026, 5, 6)),
        _l('c', DateTime(2026, 5, 8)),
        _l('d', DateTime(2026, 4, 30)), // previous week
      ];
      final stats = deriveProgress(logs, now: now);
      expect(stats.total, 4);
      expect(stats.thisWeek, 3);
    });

    test('current streak counts consecutive days ending today', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 5, 6)),
        _l('b', DateTime(2026, 5, 7)),
        _l('c', DateTime(2026, 5, 8)),
      ];
      expect(deriveProgress(logs, now: now).currentStreakDays, 3);
    });

    test('current streak survives a missing today (uses yesterday)', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 5, 5)),
        _l('b', DateTime(2026, 5, 6)),
        _l('c', DateTime(2026, 5, 7)),
      ];
      expect(deriveProgress(logs, now: now).currentStreakDays, 3);
    });

    test('current streak is 0 when there is a gap of 2+ days', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 5, 1)),
        _l('b', DateTime(2026, 5, 2)),
      ];
      expect(deriveProgress(logs, now: now).currentStreakDays, 0);
    });

    test('longest streak picks the largest consecutive run', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 4, 1)),
        _l('b', DateTime(2026, 4, 2)),
        _l('c', DateTime(2026, 4, 3)),
        _l('d', DateTime(2026, 4, 4)),
        _l('e', DateTime(2026, 5, 7)),
        _l('f', DateTime(2026, 5, 8)),
      ];
      final stats = deriveProgress(logs, now: now);
      expect(stats.longestStreakDays, 4);
      expect(stats.currentStreakDays, 2);
    });

    test('treats multiple workouts on the same day as one streak day', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        _l('a', DateTime(2026, 5, 8, 9)),
        _l('b', DateTime(2026, 5, 8, 18)),
      ];
      expect(deriveProgress(logs, now: now).currentStreakDays, 1);
    });

    // R11e: a multi-exercise session contributes several WorkoutLogEntry
    // rows sharing one sessionId (WorkoutSession.asLogEntries). Every count
    // in this file must be counting distinct sessions, not rows -- a
    // 5-exercise gym visit is one workout.
    test('multiple rows sharing a sessionId count as one workout, not '
        'several', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        WorkoutLogEntry(
          id: 'sess_1_0',
          sessionId: 'sess_1',
          exerciseId: 'bench',
          exerciseTitle: 'Bench',
          completedAt: DateTime(2026, 5, 8, 9),
          durationMinutes: 45,
        ),
        WorkoutLogEntry(
          id: 'sess_1_1',
          sessionId: 'sess_1',
          exerciseId: 'row',
          exerciseTitle: 'Row',
          completedAt: DateTime(2026, 5, 8, 9),
          durationMinutes: 45,
        ),
        WorkoutLogEntry(
          id: 'sess_1_2',
          sessionId: 'sess_1',
          exerciseId: 'ohp',
          exerciseTitle: 'Overhead Press',
          completedAt: DateTime(2026, 5, 8, 9),
          durationMinutes: 45,
        ),
      ];
      final stats = deriveProgress(logs, now: now);
      expect(stats.total, 1, reason: '3 exercises, 1 gym visit');
      expect(stats.thisWeek, 1);
      expect(stats.last8Weeks[7], 1);
      expect(stats.last8Weeks.reduce((a, b) => a + b), 1);
    });

    test('two distinct sessions on the same day both count, and both count '
        'as one streak day', () {
      final now = DateTime(2026, 5, 8);
      final logs = [
        WorkoutLogEntry(
          id: 'morning_0',
          sessionId: 'morning',
          exerciseId: 'bench',
          exerciseTitle: 'Bench',
          completedAt: DateTime(2026, 5, 8, 7),
          durationMinutes: 30,
        ),
        WorkoutLogEntry(
          id: 'evening_0',
          sessionId: 'evening',
          exerciseId: 'squat',
          exerciseTitle: 'Squat',
          completedAt: DateTime(2026, 5, 8, 19),
          durationMinutes: 30,
        ),
      ];
      final stats = deriveProgress(logs, now: now);
      expect(stats.total, 2);
      expect(stats.currentStreakDays, 1);
    });

    test('buckets logs into the last 8 weeks (oldest → newest)', () {
      final now = DateTime(2026, 5, 8); // Friday
      final logs = [
        // This week (index 7)
        _l('a', DateTime(2026, 5, 4)),
        _l('b', DateTime(2026, 5, 5)),
        // 1 week ago (index 6)
        _l('c', DateTime(2026, 4, 30)),
        // 7 weeks ago (index 0)
        _l('d', DateTime(2026, 3, 16)),
        // 9 weeks ago — outside the window, dropped
        _l('e', DateTime(2026, 3, 1)),
      ];
      final stats = deriveProgress(logs, now: now);
      expect(stats.last8Weeks[7], 2);
      expect(stats.last8Weeks[6], 1);
      expect(stats.last8Weeks[0], 1);
      expect(stats.last8Weeks[1], 0);
      expect(stats.last8Weeks.reduce((a, b) => a + b), 4);
    });
  });
}
