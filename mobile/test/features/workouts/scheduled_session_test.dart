import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/scheduled_session.dart';

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
  });
}
