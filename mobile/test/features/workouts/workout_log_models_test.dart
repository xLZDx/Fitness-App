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

    // R11e: sessionId defaults to id, so every row that predates the field
    // -- every legacy `workout_logs` document, every existing test fixture --
    // reads back exactly as before.
    test('sessionId defaults to id and is omitted from JSON when equal', () {
      expect(entry.sessionId, 'log_1');
      expect(entry.toJson().containsKey('sessionId'), isFalse);
    });

    test('an explicit sessionId round-trips and is written to JSON', () {
      final row = WorkoutLogEntry(
        id: 'sess_1_0',
        sessionId: 'sess_1',
        exerciseId: 'bench',
        exerciseTitle: 'Bench',
        completedAt: DateTime.utc(2026, 8, 6, 9),
        durationMinutes: 45,
      );
      final json = row.toJson();
      expect(json['sessionId'], 'sess_1');
      final restored = WorkoutLogEntry.fromJson(json);
      expect(restored.sessionId, 'sess_1');
      expect(restored, row);
    });

    test('copyWith() with no args keeps the existing sessionId rather than '
        're-deriving it from a new id', () {
      final row = WorkoutLogEntry(
        id: 'sess_1_0',
        sessionId: 'sess_1',
        exerciseId: 'bench',
        exerciseTitle: 'Bench',
        completedAt: DateTime.utc(2026, 8, 6, 9),
        durationMinutes: 45,
      );
      final renamed = row.copyWith(id: 'sess_1_0_renamed');
      expect(renamed.sessionId, 'sess_1',
          reason: 'renaming the row must not silently sever it from its session');
    });

    test('fromJson without a sessionId key defaults it to id, for legacy '
        'workout_logs documents', () {
      final out = WorkoutLogEntry.fromJson({
        'id': 'legacy_1',
        'exerciseId': 'squat',
        'exerciseTitle': 'Squat',
        'completedAt': '2026-01-01T00:00:00.000Z',
        'durationMinutes': 30,
      });
      expect(out.sessionId, 'legacy_1');
    });
  });
}
