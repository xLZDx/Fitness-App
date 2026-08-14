import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
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
  group('buildProgrammeSchedule', () {
    test('produces exactly weeks * daysPerWeek rows when the catalogue has '
        'candidates for every slot', () {
      final catalogue = [_ex('a', muscles: ['chest']), _ex('b', muscles: ['chest'])];
      final programme = _programme(weeks: 3, daysPerWeek: 2, muscles: ['chest']);
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows, hasLength(6));
    });

    test('every row carries the programme id', () {
      final programme = _programme(weeks: 1, daysPerWeek: 2, muscles: ['chest']);
      final rows = buildProgrammeSchedule(
        programme: programme,
        catalogue: [_ex('a', muscles: ['chest'])],
      );
      expect(rows.every((r) => r.programmeId == 'p1'), isTrue);
    });

    test('a full-body template (empty muscles) draws from the whole catalogue',
        () {
      final programme = _programme(weeks: 1, daysPerWeek: 2, muscles: const []);
      final catalogue = [_ex('a', muscles: ['chest']), _ex('b', muscles: ['legs'])];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.exerciseId), containsAll(['a', 'b']));
    });

    test('a muscle with zero catalogue matches falls back to the whole '
        'catalogue rather than dropping the slot', () {
      final programme =
          _programme(weeks: 1, daysPerWeek: 1, muscles: ['nonexistent_muscle']);
      final catalogue = [_ex('a', muscles: ['chest'])];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows, hasLength(1));
      expect(rows.single.exerciseId, 'a');
    });

    test('an empty catalogue produces no rows, not fabricated ones', () {
      final programme = _programme(weeks: 2, daysPerWeek: 3);
      final rows = buildProgrammeSchedule(programme: programme, catalogue: const []);
      expect(rows, isEmpty);
    });

    test('day-slots are spread across the week, not bunched at the start',
        () {
      // 4 days/week over a 7-day span must not land on offsets 0/1/2/3.
      final programme = _programme(
        weeks: 1,
        daysPerWeek: 4,
        muscles: const [],
        startedAt: DateTime(2026, 1, 1),
      );
      final catalogue = [_ex('a')];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      final offsets = rows
          .map((r) => r.scheduledFor.difference(DateTime(2026, 1, 1)).inDays)
          .toList()
        ..sort();
      expect(offsets, [0, 1, 3, 5]);
    });

    test('rotates through candidates across weeks instead of repeating the '
        'same exercise every time', () {
      final programme = _programme(weeks: 3, daysPerWeek: 1, muscles: ['chest']);
      final catalogue = [_ex('a', muscles: ['chest']), _ex('b', muscles: ['chest'])];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      final ids = rows.map((r) => r.exerciseId).toList();
      // Not all three weeks picked the same exercise.
      expect(ids.toSet().length, greaterThan(1));
    });

    test('a template with more muscles than weekly slots still reaches every '
        'muscle, instead of dropping one forever', () {
      // `hypertrophy` names four muscles and offers four days. A user who told
      // the questionnaire they have three gets `daysPerWeek` clamped to three,
      // and under `slot % muscles.length` the fourth muscle — hamstrings —
      // would then never be scheduled in any week of the programme.
      final programme = _programme(
        weeks: 2,
        daysPerWeek: 3,
        muscles: ['chest', 'back', 'quads', 'hamstrings'],
      );
      final catalogue = [
        _ex('c', muscles: ['chest']),
        _ex('b', muscles: ['back']),
        _ex('q', muscles: ['quads']),
        _ex('h', muscles: ['hamstrings']),
      ];
      final rows =
          buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows.map((r) => r.exerciseId).toSet(), {'c', 'b', 'q', 'h'});
    });

    test('when muscles and weekly slots match, each slot keeps its own muscle '
        'every week', () {
      // The shipped templates are all in this shape, so the week-advancing
      // index must reduce to the old behaviour for them.
      final programme = _programme(
        weeks: 3,
        daysPerWeek: 2,
        muscles: ['chest', 'back'],
      );
      final catalogue = [
        _ex('c', muscles: ['chest']),
        _ex('b', muscles: ['back']),
      ];
      final rows =
          buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows.map((r) => r.exerciseId), ['c', 'b', 'c', 'b', 'c', 'b']);
    });

    test('a day is filled up to the session length the user asked for', () {
      // Every catalogue exercise is 10 minutes (measured: all 1,887 rows), so
      // a 40-minute answer is four of them.
      final catalogue = [
        for (var i = 0; i < 10; i++) _ex('e$i', durationMinutes: 10),
      ];
      final programme = _programme(weeks: 1, daysPerWeek: 1, muscles: const []);
      final rows = buildProgrammeSchedule(
        programme: programme,
        catalogue: catalogue,
        sessionMinutes: 40,
      );
      expect(rows.single.exerciseCount, 4);
      expect(rows.single.durationMinutes, 40);
    });

    test('a shorter answer produces a shorter day', () {
      final catalogue = [
        for (var i = 0; i < 10; i++) _ex('e$i', durationMinutes: 10),
      ];
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        catalogue: catalogue,
        sessionMinutes: 20,
      );
      expect(rows.single.exerciseCount, 2);
    });

    test('an unanswered session length falls back to the documented default',
        () {
      final catalogue = [
        for (var i = 0; i < 10; i++) _ex('e$i', durationMinutes: 10),
      ];
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        catalogue: catalogue,
      );
      expect(rows.single.durationMinutes,
          lessThanOrEqualTo(kDefaultSessionMinutes));
      expect(rows.single.exerciseCount, kDefaultSessionMinutes ~/ 10);
    });

    test('a day never repeats an exercise, even when the pool is smaller than '
        'the session length', () {
      // Two candidates, an hour asked for. Six slots' worth of time, two
      // exercises available — scheduling the same movement three times would
      // fill the minutes and would not be a workout.
      final catalogue = [_ex('a'), _ex('b')];
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        catalogue: catalogue,
        sessionMinutes: 60,
      );
      final ids = rows.single.exercises.map((e) => e.exerciseId).toList();
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
    });

    test('a day always has at least one exercise, even when one alone runs '
        'past the asked-for length', () {
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        catalogue: [_ex('a')],
        sessionMinutes: 5,
      );
      expect(rows.single.exerciseCount, 1);
    });

    test('the row duration is the whole day, not the first exercise', () {
      final catalogue = [
        for (var i = 0; i < 5; i++) _ex('e$i', durationMinutes: 10),
      ];
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 1),
        catalogue: catalogue,
        sessionMinutes: 30,
      );
      expect(rows.single.durationMinutes, 30);
      expect(rows.single.exerciseCount, 3);
    });

    test('the first exercise of the day stays the rotation entry, so weeks '
        'still differ from each other', () {
      final catalogue = [_ex('a'), _ex('b'), _ex('c')];
      final rows = buildProgrammeSchedule(
        programme: _programme(weeks: 3, daysPerWeek: 1),
        catalogue: catalogue,
        sessionMinutes: 10,
      );
      expect(rows.map((r) => r.exerciseId), ['a', 'b', 'c']);
    });

    test('generated ids are unique across the whole schedule', () {
      final programme = _programme(weeks: 4, daysPerWeek: 5, muscles: const []);
      final catalogue = [_ex('a'), _ex('b'), _ex('c')];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows.map((r) => r.id).toSet(), hasLength(rows.length));
    });

    // B5d. The questionnaire asks which weekdays the user trains and, until
    // this, nothing in the scheduling path read the answer.
    test('sessions land on the weekdays the user actually picked', () {
      // 2026-01-01 is a Thursday. Asking for Mon/Wed/Fri must produce those
      // weekdays, not three days measured from Thursday.
      final rows = buildProgrammeSchedule(
        programme: _programme(
            weeks: 2, daysPerWeek: 3, startedAt: DateTime(2026, 1, 1)),
        catalogue: [_ex('a'), _ex('b'), _ex('c')],
        preferredWeekdays: const [
          DateTime.monday,
          DateTime.wednesday,
          DateTime.friday,
        ],
      );

      expect(rows, hasLength(6));
      expect(
        rows.map((r) => r.scheduledFor.weekday).toSet(),
        {DateTime.monday, DateTime.wednesday, DateTime.friday},
      );
    });

    test('naming no weekdays keeps the old even spread', () {
      // Every enrolment made before this parameter existed was built this way,
      // and "not answered" must not silently become a different schedule.
      final withNone = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 3),
        catalogue: [_ex('a'), _ex('b'), _ex('c')],
      );
      final withEmpty = buildProgrammeSchedule(
        programme: _programme(weeks: 1, daysPerWeek: 3),
        catalogue: [_ex('a'), _ex('b'), _ex('c')],
        preferredWeekdays: const [],
      );

      expect(withEmpty.map((r) => r.scheduledFor),
          withNone.map((r) => r.scheduledFor));
    });

    test('fewer named days than the count answer shortens the week', () {
      // The named days win: putting someone on a weekday they were shown and
      // did not tick is the one outcome that reads as the app overriding them.
      final rows = buildProgrammeSchedule(
        programme: _programme(
            weeks: 2, daysPerWeek: 4, startedAt: DateTime(2026, 1, 1)),
        catalogue: [_ex('a'), _ex('b')],
        preferredWeekdays: const [DateTime.tuesday, DateTime.saturday],
      );

      expect(rows, hasLength(4), reason: 'two days a week for two weeks');
      expect(rows.map((r) => r.scheduledFor.weekday).toSet(),
          {DateTime.tuesday, DateTime.saturday});
    });

    test('more named days than the count answer keeps the count', () {
      final rows = buildProgrammeSchedule(
        programme: _programme(
            weeks: 1, daysPerWeek: 2, startedAt: DateTime(2026, 1, 1)),
        catalogue: [_ex('a'), _ex('b')],
        preferredWeekdays: const [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
        ],
      );

      expect(rows, hasLength(2));
    });

    test('every week keeps the same weekdays, across a clock change', () {
      // A year-long span so a DST transition falls inside it on any host that
      // has one (this project's own zone, Europe/Chisinau, does). The rows are
      // built from calendar parts precisely because
      // `startedAt.add(Duration(days: n))` moves the absolute instant by n*24h
      // and does not correct for DST, which drifts a near-midnight programme
      // onto the wrong weekday partway through.
      final rows = buildProgrammeSchedule(
        programme: _programme(
          weeks: 52,
          daysPerWeek: 2,
          // 23:30 local: the hour where a one-hour shift changes the date.
          startedAt: DateTime(2026, 1, 1, 23, 30),
        ),
        catalogue: [_ex('a'), _ex('b')],
        preferredWeekdays: const [DateTime.tuesday, DateTime.saturday],
      );

      expect(rows, hasLength(104));
      expect(
        rows.map((r) => r.scheduledFor.weekday).toSet(),
        {DateTime.tuesday, DateTime.saturday},
        reason: 'not one of 104 sessions may drift onto another weekday',
      );
    });

    test('a weekday outside 1..7 is dropped, not wrapped into a wrong day', () {
      // The model does not validate this field (`profile_models.dart`), so a
      // value written by hand into Firestore can reach here. Wrapping it with
      // a modulo would schedule a real day the user never asked for.
      final rows = buildProgrammeSchedule(
        programme: _programme(
            weeks: 1, daysPerWeek: 3, startedAt: DateTime(2026, 1, 1)),
        catalogue: [_ex('a')],
        preferredWeekdays: const [DateTime.monday, 0, 9],
      );

      expect(rows.map((r) => r.scheduledFor.weekday).toSet(),
          {DateTime.monday});
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
}
