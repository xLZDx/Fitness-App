import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/movement_role.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_schedule.dart';

ExerciseItem _ex(
  String id, {
  List<String> muscles = const [],
  // 20 by default only because these tests predate B5b and their expectations
  // are written against it. The day-filling tests pass 10 — the value every
  // one of the 1,887 shipped rows actually carries — so their arithmetic can
  // be read on the spot instead of against a fixture constant three screens up.
  int durationMinutes = 20,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: durationMinutes,
      summary: '',
      steps: const [],
    );

Programme _programme({
  int weeks = 2,
  int daysPerWeek = 3,
  List<String> muscles = const [],
  DateTime? startedAt,
}) =>
    Programme(
      id: 'p1',
      templateId: 't1',
      title: 'Test programme',
      goal: ProgrammeGoal.strength,
      level: ExerciseDifficulty.intermediate,
      weeks: weeks,
      daysPerWeek: daysPerWeek,
      muscles: muscles,
      startedAt: startedAt ?? DateTime(2026, 1, 1),
    );

void main() {
  /// G-E replaced `buildProgrammeSchedule` -- the alphabetical filler behind
  /// F021 and F022 -- with `buildProgramme`, and this group went with it: it
  /// described `_fillDay`'s pool-walking, day-length filling and rotation,
  /// none of which exists any more. `programme_builder_test.dart` covers what
  /// replaced it, including the two acceptance criteria (four primary roles a
  /// week; at most one shared exercise between consecutive sessions).
  ///
  /// What is here instead is coverage for `scheduleFromPlan`, the scheduler
  /// that SURVIVED -- and which had no test of its own at all while the
  /// deleted one had thirty. Deleting the old group without this would have
  /// left the only shipping schedule-writing path untested.
  group('scheduleFromPlan', () {
    PlannedSession session(int week, int dayIndex, List<String> ids) =>
        PlannedSession(
          week: week,
          dayIndex: dayIndex,
          specName: 'A',
          exercises: [
            for (final id in ids)
              PlannedExercise(
                  exercise: _ex(id), role: MovementRole.squat, sets: 3),
          ],
        );

    test('writes one row per planned session', () {
      final rows = scheduleFromPlan(
        programme: _programme(weeks: 2, daysPerWeek: 2),
        plan: [
          session(0, 0, ['a', 'b']),
          session(0, 1, ['c']),
          session(1, 0, ['d']),
          session(1, 1, ['e']),
        ],
        dayOffsets: const [0, 2],
      );
      expect(rows, hasLength(4));
    });

    test('the first exercise leads the row and the rest ride along', () {
      // The row's own `exerciseId` is what the player opens; the others are
      // `extraExercises`, which is what makes a day ONE workout.
      final rows = scheduleFromPlan(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        plan: [session(0, 0, ['a', 'b', 'c'])],
        dayOffsets: const [0],
      );
      expect(rows.single.exerciseId, 'a');
      expect(rows.single.extraExercises.map((e) => e.exerciseId),
          ['b', 'c']);
    });

    test('sessions land on the offsets they were given', () {
      // The weekday answer reaches the calendar through here. The old group
      // asserted this through `buildProgrammeSchedule`; this is the same
      // property on the path that still ships.
      final rows = scheduleFromPlan(
        programme: _programme(
            weeks: 1, daysPerWeek: 3, startedAt: DateTime(2026, 1, 5)),
        plan: [
          session(0, 0, ['a']),
          session(0, 1, ['b']),
          session(0, 2, ['c']),
        ],
        dayOffsets: const [0, 2, 4],
      );
      expect(rows.map((r) => r.scheduledFor.day), [5, 7, 9]);
    });

    test('week N is seven days after week N-1, same offsets', () {
      final rows = scheduleFromPlan(
        programme: _programme(
            weeks: 2, daysPerWeek: 1, startedAt: DateTime(2026, 1, 5)),
        plan: [
          session(0, 0, ['a']),
          session(1, 0, ['b']),
        ],
        dayOffsets: const [0],
      );
      expect(rows.map((r) => r.scheduledFor.day), [5, 12]);
    });

    test('ids are unique across the whole schedule', () {
      // Two rows sharing an id would have one overwrite the other in the
      // repository, silently shortening the programme.
      final rows = scheduleFromPlan(
        programme: _programme(weeks: 4, daysPerWeek: 3),
        plan: [
          for (var w = 0; w < 4; w++)
            for (var d = 0; d < 3; d++) session(w, d, ['a', 'b']),
        ],
        dayOffsets: const [0, 2, 4],
      );
      expect(rows.map((r) => r.id).toSet(), hasLength(rows.length));
    });

    test('a session with no exercises is skipped, not written empty', () {
      final rows = scheduleFromPlan(
        programme: _programme(weeks: 1, daysPerWeek: 2),
        plan: [
          session(0, 0, const []),
          session(0, 1, ['a']),
        ],
        dayOffsets: const [0, 2],
      );
      expect(rows, hasLength(1));
      expect(rows.single.exerciseId, 'a');
    });

    test('an empty plan or no offsets produces nothing, not a crash', () {
      expect(
        scheduleFromPlan(
            programme: _programme(),
            plan: const [],
            dayOffsets: const [0]),
        isEmpty,
      );
      expect(
        scheduleFromPlan(
            programme: _programme(),
            plan: [session(0, 0, ['a'])],
            dayOffsets: const []),
        isEmpty,
      );
    });
  });


  group('programmeDayOffsets', () {
    test('offsets are measured from the day the programme starts', () {
      // Thursday start, Friday wanted -> tomorrow, not "day 5 of the week".
      expect(
        programmeDayOffsets(
          startedOn: DateTime(2026, 1, 1),
          daysPerWeek: 1,
          preferredWeekdays: const [DateTime.friday],
        ),
        [1],
      );
    });

    test('the start weekday itself is offset zero, not seven', () {
      expect(
        programmeDayOffsets(
          startedOn: DateTime(2026, 1, 1),
          daysPerWeek: 1,
          preferredWeekdays: const [DateTime.thursday],
        ),
        [0],
      );
    });

    test('duplicates collapse instead of double-booking a day', () {
      expect(
        programmeDayOffsets(
          startedOn: DateTime(2026, 1, 1),
          daysPerWeek: 3,
          preferredWeekdays: const [
            DateTime.monday,
            DateTime.monday,
            DateTime.friday,
          ],
        ),
        hasLength(2),
      );
    });
  });

  group('programmeScheduledDays (B5d-2)', () {
    test('no named weekdays leaves the count answer alone', () {
      expect(
        programmeScheduledDays(daysPerWeek: 4, preferredWeekdays: const []),
        4,
      );
    });

    test('fewer named days than asked for wins', () {
      expect(
        programmeScheduledDays(
            daysPerWeek: 5, preferredWeekdays: const [2, 6]),
        2,
      );
    });

    test('more named days than asked for keeps the count answer', () {
      expect(
        programmeScheduledDays(
            daysPerWeek: 3, preferredWeekdays: const [1, 2, 3, 4, 5]),
        3,
      );
    });

    test('weekdays outside 1..7 do not inflate the count', () {
      // Same rule as `programmeDayOffsets`: `preferredWeekdays` is unvalidated
      // at the model, so a hand-written 9 must not become a day.
      expect(
        programmeScheduledDays(
            daysPerWeek: 4, preferredWeekdays: const [1, 9, 0, 1]),
        1,
      );
    });

    test('agrees with the generator on every start weekday', () {
      // This is the whole reason the function exists: the card states a
      // cadence BEFORE enrolment, when there is no start date yet. If the two
      // could ever disagree, the card would promise a number the schedule then
      // does not deliver.
      const cases = [
        (4, <int>[]),
        (4, [1, 3, 5]),
        (2, [1, 2, 3, 4, 5]),
        (3, [7]),
        (5, [1, 9, 3]),
        (1, <int>[]),
      ];
      for (final (days, weekdays) in cases) {
        for (var startDay = 1; startDay <= 7; startDay++) {
          // 2026-06-01 is a Monday, so this walks every weekday as a start.
          final startedOn = DateTime(2026, 6, startDay);
          expect(
            programmeScheduledDays(
                daysPerWeek: days, preferredWeekdays: weekdays),
            programmeDayOffsets(
              startedOn: startedOn,
              daysPerWeek: days,
              preferredWeekdays: weekdays,
            ).length,
            reason: 'days=$days weekdays=$weekdays start=$startedOn',
          );
        }
      }
    });
  });
}
