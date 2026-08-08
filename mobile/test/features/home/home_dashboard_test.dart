import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/data/home_dashboard.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

/// R11a rebuilt Home against the real design source. Everything the new screen
/// shows that the old one did not — greeting, plan bar, recovery strip, week
/// strip, week totals — is arithmetic, and this is where that arithmetic is
/// pinned. The widget test that follows it only checks the wiring.

ExerciseItem _ex(String id, List<String> primary, {List<String>? muscles}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: muscles ?? primary,
      primaryMuscles: primary,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
    );

WorkoutLogEntry _log(
  String exerciseId,
  DateTime at, {
  double? weightKg,
  int? reps,
  String? id,
}) =>
    WorkoutLogEntry(
      id: id ?? '$exerciseId-${at.toIso8601String()}',
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      completedAt: at,
      durationMinutes: 30,
      weightKg: weightKg,
      repsCompleted: reps,
    );

ScheduledSession _sched(
  String exerciseId,
  DateTime at, {
  ScheduledSessionStatus status = ScheduledSessionStatus.pending,
}) =>
    ScheduledSession(
      id: '$exerciseId-${at.toIso8601String()}',
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      scheduledFor: at,
      durationMinutes: 30,
      status: status,
    );

void main() {
  group('greetingFor', () {
    test('splits the day at noon and at 18:00', () {
      expect(greetingFor(DateTime(2026, 8, 5, 0)), DayGreeting.morning);
      expect(greetingFor(DateTime(2026, 8, 5, 11, 59)), DayGreeting.morning);
      expect(greetingFor(DateTime(2026, 8, 5, 12)), DayGreeting.afternoon);
      expect(greetingFor(DateTime(2026, 8, 5, 17, 59)), DayGreeting.afternoon);
      expect(greetingFor(DateTime(2026, 8, 5, 18)), DayGreeting.evening);
      expect(greetingFor(DateTime(2026, 8, 5, 23, 59)), DayGreeting.evening);
    });
  });

  group('derivePlanProgress', () {
    final now = DateTime(2026, 8, 5, 12); // mid-week

    test('an empty schedule reports isEmpty, not 0%', () {
      final p = derivePlanProgress(const [], now: now);
      expect(p.isEmpty, isTrue,
          reason: 'a 0% bar over nothing scheduled reads as failure');
      expect(p.fraction, 0, reason: 'must not divide by zero');
    });

    test('counts this week only', () {
      final p = derivePlanProgress([
        _sched('a', now, status: ScheduledSessionStatus.completed),
        _sched('b', now.add(const Duration(days: 1))),
        // Last week and next week are outside the window.
        _sched('c', now.subtract(const Duration(days: 8))),
        _sched('d', now.add(const Duration(days: 9))),
      ], now: now);

      expect(p.total, 2);
      expect(p.done, 1);
      expect(p.percent, 50);
    });

    test('a cancelled session leaves the bar, it does not become a miss', () {
      final p = derivePlanProgress([
        _sched('a', now, status: ScheduledSessionStatus.completed),
        _sched('b', now, status: ScheduledSessionStatus.cancelled),
      ], now: now);

      expect(p.total, 1, reason: 'cancelled is removal, not outstanding work');
      expect(p.percent, 100);
    });
  });

  group('deriveRecovery', () {
    final now = DateTime(2026, 8, 5, 12);
    final catalog = {
      'bench': _ex('bench', ['chest']),
      'row': _ex('row', ['back']),
      'squat': _ex('squat', ['quads']),
      // Names no primary muscle -- the first of `muscles` stands in, the same
      // fallback `digestForDay` makes.
      'curl': _ex('curl', const [], muscles: ['biceps', 'forearms']),
    };

    test('maps hours-since onto the three statuses', () {
      final rows = deriveRecovery([
        _log('bench', now.subtract(const Duration(hours: 3))),
        _log('row', now.subtract(const Duration(hours: 30))),
        _log('squat', now.subtract(const Duration(hours: 100))),
      ], catalog, now: now);

      final byMuscle = {for (final r in rows) r.muscle: r.status};
      expect(byMuscle['chest'], RecoveryStatus.recovering);
      expect(byMuscle['back'], RecoveryStatus.medium);
      expect(byMuscle['quads'], RecoveryStatus.ready);
    });

    test('most-recently-trained first', () {
      final rows = deriveRecovery([
        _log('squat', now.subtract(const Duration(hours: 100))),
        _log('bench', now.subtract(const Duration(hours: 3))),
        _log('row', now.subtract(const Duration(hours: 30))),
      ], catalog, now: now);

      expect(rows.map((r) => r.muscle).toList(), ['chest', 'back', 'quads']);
    });

    test('falls back to the first listed muscle when none is primary', () {
      final rows = deriveRecovery(
        [_log('curl', now.subtract(const Duration(hours: 1)))],
        catalog,
        now: now,
      );
      expect(rows.single.muscle, 'biceps',
          reason: 'take(1), not all of them -- same rule as digestForDay');
    });

    test('an exercise missing from the catalogue is skipped, not guessed', () {
      final rows = deriveRecovery(
        [_log('not_in_catalog', now.subtract(const Duration(hours: 1)))],
        catalog,
        now: now,
      );
      expect(rows, isEmpty);
    });

    test('a muscle never trained does not appear as "ready"', () {
      final rows = deriveRecovery(
        [_log('bench', now.subtract(const Duration(hours: 1)))],
        catalog,
        now: now,
      );
      expect(rows.map((r) => r.muscle), ['chest']);
      expect(rows.any((r) => r.muscle == 'quads'), isFalse,
          reason: 'you cannot be recovered from work you never did');
    });

    test('a future-dated log clamps to zero rather than going negative', () {
      final rows = deriveRecovery(
        [_log('bench', now.add(const Duration(hours: 5)))],
        catalog,
        now: now,
      );
      expect(rows.single.hoursSince, 0);
      expect(rows.single.status, RecoveryStatus.recovering);
    });
  });

  group('deriveWeekStrip', () {
    final now = DateTime(2026, 8, 5, 12);

    test('is seven cells, Monday first, with today marked once', () {
      final week = deriveWeekStrip(const [], const [], now: now);

      expect(week.length, 7);
      expect(week.first.day.weekday, DateTime.monday);
      expect(week.last.day.weekday, DateTime.sunday);
      expect(week.where((c) => c.isToday).length, 1);
    });

    test('separates trained, planned and rest days', () {
      final monday = deriveWeekStrip(const [], const [], now: now).first.day;
      final tuesday = monday.add(const Duration(days: 1));
      final wednesday = monday.add(const Duration(days: 2));

      final week = deriveWeekStrip(
        [_log('bench', monday.add(const Duration(hours: 9)))],
        [_sched('row', tuesday.add(const Duration(hours: 18)))],
        now: now,
      );

      expect(week[0].done, isTrue);
      expect(week[0].isRest, isFalse);
      expect(week[1].done, isFalse);
      expect(week[1].scheduled, isTrue);
      expect(week[1].isRest, isFalse,
          reason: 'planned-but-unfinished is not a rest day');
      expect(week[2].isRest, isTrue, reason: 'nothing logged, nothing planned');
      expect(wednesday, week[2].day);
    });

    test('a cancelled session does not mark its day as planned', () {
      final monday = deriveWeekStrip(const [], const [], now: now).first.day;
      final week = deriveWeekStrip(
        const [],
        [
          _sched('row', monday.add(const Duration(hours: 18)),
              status: ScheduledSessionStatus.cancelled)
        ],
        now: now,
      );
      expect(week[0].scheduled, isFalse);
      expect(week[0].isRest, isTrue);
    });
  });

  group('deriveWeekTotals', () {
    final now = DateTime(2026, 8, 5, 12);

    test('an empty history is all zeros', () {
      expect(deriveWeekTotals(const [], now: now).workouts, 0);
      expect(deriveWeekTotals(const [], now: now).volumeKg, 0);
    });

    test('volume is weight x reps, and load-free work contributes nothing', () {
      final t = deriveWeekTotals([
        _log('bench', now, weightKg: 80, reps: 5), // 400
        _log('row', now, weightKg: 60, reps: 10), // 600
        _log('plank', now), // no load at all
        _log('curl', now, weightKg: 20), // weight but no rep count
      ], now: now);

      expect(t.workouts, 4, reason: 'all four are workouts');
      expect(t.volumeKg, 1000,
          reason: 'only the two rows carrying both a weight and reps count');
    });

    test('last week is excluded from the counts', () {
      final t = deriveWeekTotals([
        _log('bench', now, weightKg: 80, reps: 5),
        _log('bench', now.subtract(const Duration(days: 8)),
            weightKg: 100, reps: 5),
      ], now: now);

      expect(t.workouts, 1);
      expect(t.volumeKg, 400);
    });

    test('a record needs to beat every earlier load for the same exercise', () {
      final t = deriveWeekTotals([
        // Earlier, outside the week: the bar to clear.
        _log('bench', now.subtract(const Duration(days: 9)), weightKg: 80),
        _log('bench', now.subtract(const Duration(days: 2)), weightKg: 85),
        // Equalling the best is holding a record, not setting one.
        _log('bench', now.subtract(const Duration(days: 1)), weightKg: 85),
        _log('bench', now, weightKg: 90),
      ], now: now);

      expect(t.personalRecords, 2,
          reason: '85 beat 80 and 90 beat 85; the repeated 85 did not');
    });

    test('the very first time an exercise is logged is not counted as a PR',
        () {
      final t = deriveWeekTotals(
        [_log('deadlift', now, weightKg: 140)],
        now: now,
      );
      expect(t.personalRecords, 0,
          reason: 'nothing was beaten -- there was no earlier load');
    });

    test('records are per exercise, not across the whole log', () {
      final t = deriveWeekTotals([
        _log('bench', now.subtract(const Duration(days: 2)), weightKg: 100),
        // Lighter than the bench, but it is a different lift.
        _log('curl', now.subtract(const Duration(days: 1)), weightKg: 20),
        _log('curl', now, weightKg: 22),
      ], now: now);

      expect(t.personalRecords, 1);
    });

    // R11e: WorkoutSession.asLogEntries() emits one row per exercise for a
    // multi-exercise session, all sharing one WorkoutLogEntry.sessionId. A
    // gym visit covering three machines is one workout, not three.
    test('rows sharing a sessionId count as one workout, but their volume '
        'and records still each count', () {
      final t = deriveWeekTotals([
        WorkoutLogEntry(
          id: 'sess_1_0',
          sessionId: 'sess_1',
          exerciseId: 'bench',
          exerciseTitle: 'Bench',
          completedAt: now,
          durationMinutes: 45,
          weightKg: 80,
          repsCompleted: 5,
        ),
        WorkoutLogEntry(
          id: 'sess_1_1',
          sessionId: 'sess_1',
          exerciseId: 'row',
          exerciseTitle: 'Row',
          completedAt: now,
          durationMinutes: 45,
          weightKg: 60,
          repsCompleted: 10,
        ),
        WorkoutLogEntry(
          id: 'sess_1_2',
          sessionId: 'sess_1',
          exerciseId: 'ohp',
          exerciseTitle: 'Overhead Press',
          completedAt: now,
          durationMinutes: 45,
          weightKg: 30,
          repsCompleted: 8,
        ),
      ], now: now);

      expect(t.workouts, 1, reason: '3 exercises, 1 gym visit');
      expect(t.volumeKg, 400 + 600 + 240,
          reason: 'volume sums every exercise in the session, not just one');
    });

    test('two separate sessions the same week both count as separate '
        'workouts', () {
      final t = deriveWeekTotals([
        _log('bench', now, id: 'sessA_0', weightKg: 80, reps: 5)
            .copyWith(sessionId: 'sessA'),
        _log('squat', now, id: 'sessB_0', weightKg: 100, reps: 5)
            .copyWith(sessionId: 'sessB'),
      ], now: now);

      expect(t.workouts, 2);
    });
  });
}
