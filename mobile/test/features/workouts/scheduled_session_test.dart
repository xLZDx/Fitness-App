import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

void main() {
  group('ScheduledSession', () {
    final session = ScheduledSession(
      id: 'sess_1',
      exerciseId: 'pushup',
      exerciseTitle: 'Push-ups',
      scheduledFor: DateTime.utc(2026, 5, 10, 7, 30),
      durationMinutes: 12,
      status: ScheduledSessionStatus.pending,
      notes: 'before breakfast',
    );

    test('toJson/fromJson round-trips losslessly', () {
      final json = session.toJson();
      expect(json['scheduledFor'], '2026-05-10T07:30:00.000Z');
      expect(json['status'], 'pending');
      final restored = ScheduledSession.fromJson(json);
      expect(restored, session);
    });

    test('toJson omits notes when null', () {
      final fresh = ScheduledSession(
        id: session.id,
        exerciseId: session.exerciseId,
        exerciseTitle: session.exerciseTitle,
        scheduledFor: session.scheduledFor,
        durationMinutes: session.durationMinutes,
      );
      expect(fresh.toJson().containsKey('notes'), isFalse);
    });

    test('fromJson tolerates DateTime values for scheduledFor', () {
      final s = ScheduledSession.fromJson({
        'id': 'x',
        'exerciseId': 'y',
        'exerciseTitle': 'Y',
        'scheduledFor': DateTime.utc(2026, 1, 1),
        'durationMinutes': 5,
      });
      expect(s.scheduledFor, DateTime.utc(2026, 1, 1));
      expect(s.status, ScheduledSessionStatus.pending);
    });

    test('fromJson defaults unknown status to pending', () {
      final s = ScheduledSession.fromJson({
        'id': 'x',
        'exerciseId': 'y',
        'exerciseTitle': 'Y',
        'scheduledFor': '2026-05-01T00:00:00.000Z',
        'durationMinutes': 5,
        'status': 'mystery',
      });
      expect(s.status, ScheduledSessionStatus.pending);
    });

    test('equality and hashCode cover all fields', () {
      final a = session.copyWith();
      expect(a, equals(session));
      expect(a.hashCode, equals(session.hashCode));

      final b = session.copyWith(status: ScheduledSessionStatus.completed);
      expect(a, isNot(equals(b)));
    });

    // Gate P: programmeId is additive. A row written before the programme
    // entity existed must read back with it null, and toJson must not emit
    // the key at all for such a row -- the same "omit when null" contract
    // notes already has, so a Firestore doc predating this change round-trips
    // unchanged.
    test('programmeId defaults to null and round-trips when set', () {
      expect(session.programmeId, isNull);
      expect(session.toJson().containsKey('programmeId'), isFalse);

      final linked = session.copyWith(programmeId: 'prog_1');
      final json = linked.toJson();
      expect(json['programmeId'], 'prog_1');
      expect(ScheduledSession.fromJson(json).programmeId, 'prog_1');
      expect(linked, isNot(equals(session)));
    });

    group('several exercises in one day (B5b)', () {
      const squat =
          WorkoutSessionExercise(exerciseId: 'squat', exerciseTitle: 'Squats');
      const row = WorkoutSessionExercise(exerciseId: 'row', exerciseTitle: 'Rows');

      test('a day holds one exercise by default', () {
        expect(session.extraExercises, isEmpty);
        expect(session.exerciseCount, 1);
        expect(session.exercises.map((e) => e.exerciseId), ['pushup']);
      });

      test('exercises starts with the first one, then the extras in order', () {
        final day = session.copyWith(extraExercises: [squat, row]);
        expect(day.exerciseCount, 3);
        expect(day.exercises.map((e) => e.exerciseId),
            ['pushup', 'squat', 'row']);
      });

      test('a document written before B5b reads back as a one-exercise day',
          () {
        // Absence of the key IS the discriminator — no migration script, no
        // version field. This is the exact JSON an older build wrote.
        final legacy = {
          'id': 'sess_1',
          'exerciseId': 'pushup',
          'exerciseTitle': 'Push-ups',
          'scheduledFor': '2026-05-10T07:30:00.000Z',
          'durationMinutes': 12,
          'status': 'pending',
        };
        final restored = ScheduledSession.fromJson(legacy);
        expect(restored.extraExercises, isEmpty);
        expect(restored.exerciseCount, 1);
        expect(restored.exercises.single.exerciseId, 'pushup');
      });

      test('a one-exercise day writes the same document it always did', () {
        // So that a build of the app predating B5b sees no new key at all.
        expect(session.toJson().containsKey('extraExercises'), isFalse);
      });

      test('a multi-exercise day still writes the singular fields, so an older '
          'build reads the first exercise instead of failing', () {
        final json = session.copyWith(extraExercises: [squat]).toJson();
        expect(json['exerciseId'], 'pushup');
        expect(json['exerciseTitle'], 'Push-ups');
        expect(json['extraExercises'], hasLength(1));
      });

      test('round-trips through JSON with the extras intact', () {
        final day = session.copyWith(extraExercises: [squat, row]);
        final restored = ScheduledSession.fromJson(day.toJson());
        expect(restored, day);
        expect(restored.exercises.map((e) => e.exerciseTitle),
            ['Push-ups', 'Squats', 'Rows']);
      });

      test('order is part of identity — it is the order the player follows',
          () {
        final a = session.copyWith(extraExercises: [squat, row]);
        final b = session.copyWith(extraExercises: [row, squat]);
        expect(a, isNot(equals(b)));
      });

      test('a day with extras differs from the same day without them', () {
        expect(session.copyWith(extraExercises: [squat]),
            isNot(equals(session)));
      });

      test('copyWith keeps the extras when it is not asked to change them', () {
        final day = session.copyWith(extraExercises: [squat]);
        expect(day.copyWith(notes: 'later').extraExercises, [squat]);
      });
    });
  });
}
