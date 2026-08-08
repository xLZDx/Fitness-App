import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_schedule.dart';

ExerciseItem _ex(String id, {List<String> muscles = const []}) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 20,
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

    test('generated ids are unique across the whole schedule', () {
      final programme = _programme(weeks: 4, daysPerWeek: 5, muscles: const []);
      final catalogue = [_ex('a'), _ex('b'), _ex('c')];
      final rows = buildProgrammeSchedule(programme: programme, catalogue: catalogue);
      expect(rows.map((r) => r.id).toSet(), hasLength(rows.length));
    });
  });
}
