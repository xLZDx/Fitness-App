import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';

ScheduledSession _s({
  String id = 's_1',
  required DateTime when,
  String title = 'Push-ups',
}) =>
    ScheduledSession(
      id: id,
      exerciseId: 'pushup',
      exerciseTitle: title,
      scheduledFor: when,
      durationMinutes: 12,
    );

void main() {
  group('MockNotificationService', () {
    late MockNotificationService svc;

    setUp(() {
      svc = MockNotificationService();
      svc.now = () => DateTime.utc(2026, 5, 8, 12);
    });

    test('init reports the configured permission result', () async {
      expect(svc.initialized, isFalse);
      expect(await svc.init(), isTrue);
      expect(svc.initialized, isTrue);

      svc.initResult = false;
      expect(await svc.init(), isFalse);
    });

    test('scheduleReminder adds an entry fired ahead of the session', () async {
      final session = _s(when: DateTime.utc(2026, 5, 9, 9));
      await svc.scheduleReminder(session, title: 'T', body: 'B');

      expect(svc.scheduled, hasLength(1));
      final r = svc.scheduled.first;
      expect(r.sessionId, 's_1');
      expect(r.fireAt, DateTime.utc(2026, 5, 9, 8, 30));
      // The text is the caller's now: the service must store it verbatim and
      // not compose its own English.
      expect(r.title, 'T');
      expect(r.body, 'B');
    });

    test('scheduleReminder honours a custom lead time', () async {
      final session = _s(when: DateTime.utc(2026, 5, 9, 9));
      await svc.scheduleReminder(session,
          leadTime: const Duration(hours: 2),
          title: 'Workout in 120 minutes',
          body: 'B');

      expect(svc.scheduled.first.fireAt, DateTime.utc(2026, 5, 9, 7));
      expect(svc.scheduled.first.title, 'Workout in 120 minutes');
    });

    test('scheduleReminder is idempotent on session id', () async {
      final session = _s(when: DateTime.utc(2026, 5, 9, 9));
      await svc.scheduleReminder(session, title: 'T', body: 'B');
      await svc.scheduleReminder(
          session.copyWith(scheduledFor: DateTime.utc(2026, 5, 9, 10)),
          title: 'T',
          body: 'B');
      expect(svc.scheduled, hasLength(1));
      expect(svc.scheduled.first.fireAt, DateTime.utc(2026, 5, 9, 9, 30));
    });

    test('scheduleReminder drops reminders whose window already passed',
        () async {
      // Session is in the future but fire-at (after subtracting 30 min lead)
      // is already behind us.
      final session = _s(
          id: 'past',
          when: DateTime.utc(2026, 5, 8, 12, 15));
      await svc.scheduleReminder(session, title: 'T', body: 'B');
      expect(svc.scheduled, isEmpty);
    });

    test('scheduleReminder removes a stale entry when the new fire-at is past',
        () async {
      final original = _s(when: DateTime.utc(2026, 5, 9, 9));
      await svc.scheduleReminder(original, title: 'T', body: 'B');
      expect(svc.scheduled, hasLength(1));

      final pushedBack = original.copyWith(
          scheduledFor: DateTime.utc(2026, 5, 8, 12, 5));
      await svc.scheduleReminder(pushedBack, title: 'T', body: 'B');
      expect(svc.scheduled, isEmpty);
    });

    test('cancelReminder removes the entry, idempotent on unknown id',
        () async {
      await svc.scheduleReminder(_s(when: DateTime.utc(2026, 5, 9, 9)),
          title: 'T', body: 'B');
      await svc.cancelReminder('s_1');
      expect(svc.scheduled, isEmpty);

      // Cancelling a non-existent id is a no-op.
      await svc.cancelReminder('does-not-exist');
      expect(svc.scheduled, isEmpty);
    });

    test('cancelAll wipes every reminder', () async {
      await svc.scheduleReminder(_s(id: 'a', when: DateTime.utc(2026, 5, 9, 9)),
          title: 'T', body: 'B');
      await svc.scheduleReminder(_s(id: 'b', when: DateTime.utc(2026, 5, 10, 9)),
          title: 'T', body: 'B');
      await svc.cancelAll();
      expect(svc.scheduled, isEmpty);
    });

    test('scheduled list is sorted ascending by fire-at', () async {
      await svc.scheduleReminder(_s(id: 'late', when: DateTime.utc(2026, 5, 11, 9)),
          title: 'T', body: 'B');
      await svc.scheduleReminder(_s(id: 'early', when: DateTime.utc(2026, 5, 9, 9)),
          title: 'T', body: 'B');
      expect(svc.scheduled.map((r) => r.sessionId), ['early', 'late']);
    });
  });
}
