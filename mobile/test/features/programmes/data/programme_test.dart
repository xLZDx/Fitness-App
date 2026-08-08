import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart'
    show ExerciseDifficulty;
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';

/// Gate P — the programme entity three earlier gates (R11a, R11d, R11i)
/// stopped short of building and worked around instead. This pins the
/// arithmetic: which week a programme is on, whether it has run past its own
/// length, and how much of it is actually done.

Programme _programme({
  int weeks = 8,
  int daysPerWeek = 4,
  DateTime? startedAt,
  ProgrammeStatus status = ProgrammeStatus.active,
}) =>
    Programme(
      id: 'p1',
      templateId: 'strength_base',
      title: 'Силовая база',
      goal: ProgrammeGoal.strength,
      level: ExerciseDifficulty.intermediate,
      weeks: weeks,
      daysPerWeek: daysPerWeek,
      startedAt: startedAt ?? DateTime(2026, 1, 1),
      status: status,
    );

ScheduledSession _row(
  String id, {
  required DateTime scheduledFor,
  String? programmeId,
  ScheduledSessionStatus status = ScheduledSessionStatus.pending,
}) =>
    ScheduledSession(
      id: id,
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: scheduledFor,
      durationMinutes: 30,
      programmeId: programmeId,
      status: status,
    );

void main() {
  group('programmeWeek', () {
    test('is week 1 on the start day itself', () {
      final p = _programme(startedAt: DateTime(2026, 1, 1));
      expect(programmeWeek(p, now: DateTime(2026, 1, 1)), 1);
    });

    test('counts in 7-day blocks from the start date, not calendar Monday',
        () {
      // Started Thursday 2026-01-01. Day 7 (2026-01-08, still a Thursday) is
      // the first day of week 2 -- NOT the following calendar Monday.
      final p = _programme(startedAt: DateTime(2026, 1, 1));
      expect(programmeWeek(p, now: DateTime(2026, 1, 7)), 1);
      expect(programmeWeek(p, now: DateTime(2026, 1, 8)), 2);
    });

    test('clamps to 1 for a date before the start', () {
      final p = _programme(startedAt: DateTime(2026, 1, 10));
      expect(programmeWeek(p, now: DateTime(2026, 1, 1)), 1);
    });

    test('clamps to the last week once the programme has run past its length',
        () {
      final p = _programme(weeks: 8, startedAt: DateTime(2026, 1, 1));
      // Week 20 worth of days later -- still reads as week 8, not 20.
      expect(programmeWeek(p, now: DateTime(2026, 1, 1).add(const Duration(days: 140))), 8);
    });
  });

  group('programmeIsOverdue', () {
    test('is false during the programme', () {
      final p = _programme(weeks: 8, startedAt: DateTime(2026, 1, 1));
      expect(programmeIsOverdue(p, now: DateTime(2026, 2, 1)), isFalse);
    });

    test('is true once more than `weeks` weeks have passed', () {
      final p = _programme(weeks: 8, startedAt: DateTime(2026, 1, 1));
      final overdueDate = DateTime(2026, 1, 1).add(const Duration(days: 8 * 7));
      expect(programmeIsOverdue(p, now: overdueDate), isTrue);
    });
  });

  group('deriveProgrammeProgress', () {
    test('counts only rows tagged with this programme\'s id', () {
      final p = _programme(weeks: 8, daysPerWeek: 4);
      final scheduled = [
        _row('a', scheduledFor: DateTime(2026, 1, 2), programmeId: 'p1',
            status: ScheduledSessionStatus.completed),
        // A session the user scheduled themselves, unrelated to the
        // programme -- must not push the bar forward.
        _row('b', scheduledFor: DateTime(2026, 1, 3),
            status: ScheduledSessionStatus.completed),
        _row('c', scheduledFor: DateTime(2026, 1, 4), programmeId: 'other-prog',
            status: ScheduledSessionStatus.completed),
      ];
      final progress = deriveProgrammeProgress(p, scheduled, now: DateTime(2026, 1, 5));
      expect(progress.done, 1);
      // 8 weeks * 4 days/week = 32 planned sessions, not "how many rows exist
      // right now".
      expect(progress.total, 32);
    });

    test('fraction is measured against the commitment, not against rows '
        'scheduled so far', () {
      final p = _programme(weeks: 2, daysPerWeek: 2);
      // Only week 1's two sessions exist yet, both completed -- 100% of what
      // is scheduled, but the programme asked for 4.
      final scheduled = [
        _row('a', scheduledFor: DateTime(2026, 1, 1), programmeId: 'p1',
            status: ScheduledSessionStatus.completed),
        _row('b', scheduledFor: DateTime(2026, 1, 3), programmeId: 'p1',
            status: ScheduledSessionStatus.completed),
      ];
      final progress = deriveProgrammeProgress(p, scheduled, now: DateTime(2026, 1, 4));
      expect(progress.total, 4);
      expect(progress.fraction, 0.5);
      expect(progress.percent, 50);
    });

    test('fraction never exceeds 1 even with extra self-added sessions', () {
      final p = _programme(weeks: 1, daysPerWeek: 1);
      final scheduled = List.generate(
        5,
        (i) => _row('extra_$i',
            scheduledFor: DateTime(2026, 1, 1 + i),
            programmeId: 'p1',
            status: ScheduledSessionStatus.completed),
      );
      final progress = deriveProgrammeProgress(p, scheduled, now: DateTime(2026, 1, 10));
      expect(progress.fraction, 1.0);
    });

    test('carries the current week alongside the count', () {
      final p = _programme(weeks: 8, daysPerWeek: 4, startedAt: DateTime(2026, 1, 1));
      final progress = deriveProgrammeProgress(p, const [], now: DateTime(2026, 1, 15));
      expect(progress.week, 3);
      expect(progress.weeks, 8);
    });
  });
}
