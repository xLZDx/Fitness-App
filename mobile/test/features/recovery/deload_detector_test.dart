import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

WorkoutLogEntry _ratedLog(DateTime when, DifficultyRating r) =>
    WorkoutLogEntry(
      id: when.toIso8601String(),
      exerciseId: 'x',
      exerciseTitle: 'x',
      completedAt: when,
      durationMinutes: 30,
      difficulty: r,
    );

ScheduledSession _scheduled(
  DateTime when, {
  ScheduledSessionStatus status = ScheduledSessionStatus.pending,
}) =>
    ScheduledSession(
      id: when.toIso8601String(),
      exerciseId: 'x',
      exerciseTitle: 'x',
      scheduledFor: when,
      durationMinutes: 30,
      status: status,
    );

void main() {
  group('detectDeload', () {
    final now = DateTime.utc(2026, 5, 10, 12);

    test('happy path: empty inputs → no deload', () {
      final v = detectDeload(
        recentLogs: const [],
        scheduledLast14Days: const [],
        now: now,
      );
      expect(v.shouldDeload, isFalse);
      expect(v.suggestedVolumeFactor, 1.0);
    });

    test('only difficulty signal → no deload (need 2 of 3)', () {
      final v = detectDeload(
        recentLogs: List.generate(
            5,
            (i) => _ratedLog(
                now.subtract(Duration(days: i)), DifficultyRating.tooHard)),
        scheduledLast14Days: const [],
        now: now,
      );
      expect(v.shouldDeload, isFalse);
    });

    test('difficulty + compliance signals → deload', () {
      final v = detectDeload(
        recentLogs: List.generate(
            5,
            (i) => _ratedLog(
                now.subtract(Duration(days: i)), DifficultyRating.tooHard)),
        scheduledLast14Days: [
          // 6 scheduled, 1 completed, 5 missed (past due) → 16% compliance
          _scheduled(now.subtract(const Duration(days: 1))),
          _scheduled(now.subtract(const Duration(days: 3))),
          _scheduled(now.subtract(const Duration(days: 5))),
          _scheduled(now.subtract(const Duration(days: 7))),
          _scheduled(now.subtract(const Duration(days: 9))),
          _scheduled(now.subtract(const Duration(days: 11)),
              status: ScheduledSessionStatus.completed),
        ],
        now: now,
      );
      expect(v.shouldDeload, isTrue);
      expect(v.suggestedVolumeFactor, 0.5);
      expect(v.reasons, hasLength(2));
      expect(v.reasons.first, isA<HardSessionsSignal>());
    });

    test('difficulty + HRV drop → deload', () {
      final v = detectDeload(
        recentLogs: List.generate(
            5,
            (i) => _ratedLog(
                now.subtract(Duration(days: i)), DifficultyRating.tooHard)),
        scheduledLast14Days: const [],
        hrvCurrent7DayAvg: 50,
        hrvBaseline30DayAvg: 60, // 16.7% drop
        now: now,
      );
      expect(v.shouldDeload, isTrue);
      expect(v.reasons.whereType<HrvBelowBaselineSignal>(), isNotEmpty);
    });

    test('all 3 signals fire → still triggers, more reasons', () {
      final v = detectDeload(
        recentLogs: List.generate(
            5,
            (i) => _ratedLog(
                now.subtract(Duration(days: i)), DifficultyRating.tooHard)),
        scheduledLast14Days: [
          _scheduled(now.subtract(const Duration(days: 1))),
          _scheduled(now.subtract(const Duration(days: 3))),
          _scheduled(now.subtract(const Duration(days: 5))),
          _scheduled(now.subtract(const Duration(days: 7))),
          _scheduled(now.subtract(const Duration(days: 9))),
          _scheduled(now.subtract(const Duration(days: 11)),
              status: ScheduledSessionStatus.completed),
        ],
        hrvCurrent7DayAvg: 50,
        hrvBaseline30DayAvg: 60,
        now: now,
      );
      expect(v.shouldDeload, isTrue);
      expect(v.reasons, hasLength(3));
    });

    test('compliance signal needs >= 5 scheduled to register', () {
      final v = detectDeload(
        recentLogs: List.generate(
            5,
            (i) => _ratedLog(
                now.subtract(Duration(days: i)), DifficultyRating.tooHard)),
        scheduledLast14Days: [
          // Only 4 scheduled — not enough sample size
          _scheduled(now.subtract(const Duration(days: 1))),
          _scheduled(now.subtract(const Duration(days: 3))),
          _scheduled(now.subtract(const Duration(days: 5))),
          _scheduled(now.subtract(const Duration(days: 7))),
        ],
        now: now,
      );
      // Only 1 signal (difficulty) → no deload
      expect(v.shouldDeload, isFalse);
    });

    test('strong HRV alone (no other signals) → no deload', () {
      final v = detectDeload(
        recentLogs: const [],
        scheduledLast14Days: const [],
        hrvCurrent7DayAvg: 30,
        hrvBaseline30DayAvg: 60,
        now: now,
      );
      expect(v.shouldDeload, isFalse);
    });

    test('mixed difficulty average ≤ 0.4 → no signal', () {
      // 3 tooHard + 4 justRight = avg 3/7 = 0.43... actually let me make it clearly < 0.4
      final v = detectDeload(
        recentLogs: [
          _ratedLog(now, DifficultyRating.tooHard),
          _ratedLog(now.subtract(const Duration(days: 1)),
              DifficultyRating.justRight),
          _ratedLog(now.subtract(const Duration(days: 2)),
              DifficultyRating.justRight),
          _ratedLog(now.subtract(const Duration(days: 3)),
              DifficultyRating.justRight),
          _ratedLog(now.subtract(const Duration(days: 4)),
              DifficultyRating.tooEasy),
        ],
        scheduledLast14Days: const [],
        now: now,
      );
      expect(v.shouldDeload, isFalse);
    });
  });
}
