import '../../features/workouts/data/scheduled_session.dart';
import 'notification_service.dart';

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.sessionId,
    required this.fireAt,
    required this.title,
    required this.body,
  });
  final String sessionId;
  final DateTime fireAt;
  final String title;
  final String body;
}

/// In-memory `NotificationService` used as the test default. Inspect
/// [scheduled] to verify reminder behaviour without a real plugin.
class MockNotificationService implements NotificationService {
  bool _initialized = false;
  final Map<String, _ScheduledReminder> _store = {};

  /// Override this to simulate a permission denial. Defaults to true
  /// (platform/user accepted the prompt).
  bool initResult = true;

  /// Override "now" so tests can reason about late reminders without
  /// touching real time.
  DateTime Function() now = DateTime.now;

  bool get initialized => _initialized;

  /// Snapshot of every currently-scheduled reminder, sorted by fireAt.
  List<({String sessionId, DateTime fireAt, String title, String body})>
      get scheduled {
    final list = _store.values.toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return list
        .map((r) => (
              sessionId: r.sessionId,
              fireAt: r.fireAt,
              title: r.title,
              body: r.body,
            ))
        .toList(growable: false);
  }

  @override
  Future<bool> init() async {
    _initialized = true;
    return initResult;
  }

  @override
  Future<void> scheduleReminder(
    ScheduledSession session, {
    Duration leadTime = const Duration(minutes: 30),
  }) async {
    final fireAt = session.scheduledFor.subtract(leadTime);
    if (!fireAt.isAfter(now())) {
      // The reminder window already passed — drop silently rather than
      // spam a notification on save. Caller doesn't need to care.
      _store.remove(session.id);
      return;
    }
    _store[session.id] = _ScheduledReminder(
      sessionId: session.id,
      fireAt: fireAt,
      title: 'Workout in ${leadTime.inMinutes} minutes',
      body: '${session.exerciseTitle} · ${session.durationMinutes} min',
    );
  }

  @override
  Future<void> cancelReminder(String sessionId) async {
    _store.remove(sessionId);
  }

  @override
  Future<void> cancelAll() async {
    _store.clear();
  }
}
