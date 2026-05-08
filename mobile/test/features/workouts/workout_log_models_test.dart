import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/workout_log.dart';

void main() {
  group('WorkoutLogEntry', () {
    final entry = WorkoutLogEntry(
      id: 'log_1',
      exerciseId: 'pushup',
      exerciseTitle: 'Push-ups',
      completedAt: DateTime.utc(2026, 5, 1, 8, 30),
      durationMinutes: 12,
      notes: 'felt strong',
    );

    test('toJson/fromJson round-trips losslessly', () {
      final json = entry.toJson();
      expect(json['completedAt'], '2026-05-01T08:30:00.000Z');
      final restored = WorkoutLogEntry.fromJson(json);
      expect(restored, entry);
    });

    test('toJson omits notes when null', () {
      final noNotes = entry.copyWith(notes: null);
      // copyWith uses ?? so we have to drop notes by constructing fresh.
      final fresh = WorkoutLogEntry(
        id: noNotes.id,
        exerciseId: noNotes.exerciseId,
        exerciseTitle: noNotes.exerciseTitle,
        completedAt: noNotes.completedAt,
        durationMinutes: noNotes.durationMinutes,
      );
      expect(fresh.toJson().containsKey('notes'), isFalse);
    });

    test('fromJson tolerates DateTime values for completedAt', () {
      final out = WorkoutLogEntry.fromJson({
        'id': 'x',
        'exerciseId': 'y',
        'exerciseTitle': 'Y',
        'completedAt': DateTime.utc(2026, 1, 1),
        'durationMinutes': 5,
      });
      expect(out.completedAt, DateTime.utc(2026, 1, 1));
    });

    test('fromJson falls back to exerciseId when title missing', () {
      final out = WorkoutLogEntry.fromJson({
        'id': 'log_2',
        'exerciseId': 'rack_back_squat_5x5',
        'completedAt': '2026-04-01T00:00:00.000Z',
        'durationMinutes': 30,
      });
      expect(out.exerciseTitle, 'rack_back_squat_5x5');
    });

    test('equality matches on all fields', () {
      final a = entry;
      final b = entry.copyWith();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final c = entry.copyWith(durationMinutes: 99);
      expect(a, isNot(equals(c)));
    });
  });
}
