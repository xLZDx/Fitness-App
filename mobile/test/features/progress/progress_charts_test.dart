import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress/data/progress_charts.dart';
import 'package:fitness_app/features/workouts/data/set_capture.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

/// R6 — every number on the progress screen is a claim about the user's own
/// history. A chart that flatters is worse than no chart, so each rule that
/// could flatter is pinned here.

WorkoutSession _s(
  String id,
  DateTime when, {
  String exerciseId = 'row',
  String title = 'Seated row',
  List<SetCapture> sets = const [],
  WorkoutSessionStatus status = WorkoutSessionStatus.completed,
}) =>
    WorkoutSession(
      id: id,
      title: title,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: exerciseId,
          exerciseTitle: title,
          sets: sets,
        ),
      ],
      startedAt: when,
      completedAt: when,
      status: status,
    );

void main() {
  // A Wednesday, so week boundaries are not accidentally satisfied by landing
  // on a Monday.
  final now = DateTime(2026, 8, 5, 12);
  final thisMonday = DateTime(2026, 8, 3);

  group('weekly volume', () {
    test('weight times reps, summed', () {
      final v = volumeByWeek([
        _s('a', now, sets: const [(weightKg: 60, reps: 10)]),
        _s('b', now, sets: const [(weightKg: 20, reps: 12)]),
      ], now);

      expect(v.last.weekStart, thisMonday);
      expect(v.last.volumeKg, 60 * 10 + 20 * 12);
      expect(v.last.sessions, 2);
    });

    test('a week without training is a zero bar, not a missing one', () {
      // A chart that closes its own gaps shows a consistency nobody had.
      final v = volumeByWeek([
        _s('a', now, sets: const [(weightKg: 60, reps: 10)]),
      ], now);

      expect(v.length, 8);
      expect(v.first.volumeKg, 0);
      expect(v.map((w) => w.weekStart).toSet().length, 8,
          reason: 'eight distinct weeks, oldest first');
      expect(v.first.weekStart.isBefore(v.last.weekStart), isTrue);
    });

    test('a set with no weight adds nothing', () {
      final v = volumeByWeek([
        _s('a', now, sets: const [
          (weightKg: null, reps: 12),
          (weightKg: 40, reps: 10),
        ]),
      ], now);
      expect(v.last.volumeKg, 400);
    });

    test('an unfinished session is not volume', () {
      final v = volumeByWeek([
        _s('a', now,
            status: WorkoutSessionStatus.abandoned,
            sets: const [(weightKg: 100, reps: 10)]),
      ], now);
      expect(v.last.volumeKg, 0);
      expect(v.last.sessions, 0);
    });

    test('work older than the window is dropped, not folded into week one', () {
      // Folding it in would put a spike on the oldest bar and make every
      // trend read as a decline.
      final v = volumeByWeek([
        _s('old', now.subtract(const Duration(days: 200)),
            sets: const [(weightKg: 100, reps: 10)]),
      ], now);
      expect(v.every((w) => w.volumeKg == 0), isTrue);
    });
  });

  group('volume trend', () {
    test('four weeks against the four before them', () {
      final v = volumeTrend([
        // earlier half: 1000 kg
        _s('old', now.subtract(const Duration(days: 35)),
            sets: const [(weightKg: 100, reps: 10)]),
        // recent half: 1200 kg
        _s('new', now, sets: const [(weightKg: 120, reps: 10)]),
      ], now);

      expect(v, closeTo(0.2, 1e-9));
    });

    test('no earlier volume gives no percentage rather than infinity', () {
      // "+∞% за месяц" is not a compliment.
      final v = volumeTrend([
        _s('new', now, sets: const [(weightKg: 120, reps: 10)]),
      ], now);
      expect(v, isNull);
    });
  });

  group('month activity', () {
    test('one entry per calendar day, counting sessions', () {
      final a = monthActivity([
        _s('a', DateTime(2026, 8, 1, 9)),
        _s('b', DateTime(2026, 8, 1, 19)),
        _s('c', DateTime(2026, 8, 4, 9)),
      ], now);

      expect(a.length, 31, reason: 'August has 31 days');
      expect(a[0], 2);
      expect(a[3], 1);
      expect(a[1], 0);
    });

    test('another month is not counted', () {
      final a = monthActivity([_s('a', DateTime(2026, 7, 20))], now);
      expect(a.every((d) => d == 0), isTrue);
    });
  });

  group('personal records', () {
    test('the heaviest set actually recorded, not an estimated 1RM', () {
      final r = personalRecords([
        _s('a', now, sets: const [(weightKg: 80, reps: 5)]),
        _s('b', now, sets: const [(weightKg: 60, reps: 20)]),
      ]);

      // Epley would rank 60x20 (~120) above 80x5 (~93). A record is what was
      // lifted, not what a formula says could have been.
      expect(r['row']!.weightKg, 80);
      expect(r['row']!.reps, 5);
    });

    test('same weight, more reps wins', () {
      final r = personalRecords([
        _s('a', now, sets: const [(weightKg: 80, reps: 5)]),
        _s('b', now, sets: const [(weightKg: 80, reps: 8)]),
      ]);
      expect(r['row']!.reps, 8);
    });

    test('a set with no weight cannot hold a record', () {
      final r = personalRecords([
        _s('a', now, sets: const [(weightKg: null, reps: 50)]),
      ]);
      expect(r, isEmpty);
    });

    test('records are per exercise', () {
      final r = personalRecords([
        _s('a', now, exerciseId: 'row', sets: const [(weightKg: 80, reps: 5)]),
        _s('b', now,
            exerciseId: 'curl', sets: const [(weightKg: 20, reps: 10)]),
      ]);
      expect(r.keys.toSet(), {'row', 'curl'});
    });
  });

  group('recent records', () {
    test('counts exercises whose standing record is recent, not every gain',
        () {
      // Three sessions on one exercise, each beating the last. That is one
      // record standing, not three -- otherwise a beginner adding 2.5 kg a
      // week "sets a record" every week forever.
      final since = now.subtract(const Duration(days: 30));
      final recent = recentRecords([
        _s('a', now.subtract(const Duration(days: 20)),
            sets: const [(weightKg: 70, reps: 5)]),
        _s('b', now.subtract(const Duration(days: 10)),
            sets: const [(weightKg: 75, reps: 5)]),
        _s('c', now, sets: const [(weightKg: 80, reps: 5)]),
      ], since);

      expect(recent.length, 1);
      expect(recent.single.weightKg, 80);
    });

    test('a record set before the window does not count as recent', () {
      final since = now.subtract(const Duration(days: 30));
      final recent = recentRecords([
        _s('old', now.subtract(const Duration(days: 90)),
            sets: const [(weightKg: 100, reps: 5)]),
      ], since);
      expect(recent, isEmpty);
    });

    test('newest first', () {
      final since = now.subtract(const Duration(days: 30));
      final recent = recentRecords([
        _s('a', now.subtract(const Duration(days: 5)),
            exerciseId: 'row', sets: const [(weightKg: 80, reps: 5)]),
        _s('b', now.subtract(const Duration(days: 1)),
            exerciseId: 'curl', sets: const [(weightKg: 20, reps: 5)]),
      ], since);

      expect(recent.map((r) => r.exerciseId), ['curl', 'row']);
    });
  });
}
