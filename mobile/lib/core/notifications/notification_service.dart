import '../../features/workouts/data/scheduled_session.dart';

/// Cross-platform reminder service. Production uses
/// `LocalNotificationService` (`flutter_local_notifications`); tests + the
/// default Riverpod provider use `MockNotificationService` so unit tests
/// don't drag in a platform plugin.
abstract class NotificationService {
  /// Best-effort permission request + plugin warm-up. Safe to call multiple
  /// times. Returns true when the platform reports notifications can be
  /// delivered (the user accepted, or the platform doesn't gate).
  Future<bool> init();

  /// Schedule a one-shot reminder for [session]. Replaces any prior
  /// reminder with the same session id.
  ///
  /// [leadTime] is how far in advance of `session.scheduledFor` the
  /// notification fires (default 30 minutes). When `scheduledFor - leadTime`
  /// is in the past, no reminder is registered.
  Future<void> scheduleReminder(
    ScheduledSession session, {
    Duration leadTime = const Duration(minutes: 30),
  });

  /// Cancel a previously-scheduled reminder. Idempotent.
  Future<void> cancelReminder(String sessionId);

  /// Cancel every pending reminder (e.g. account sign-out).
  Future<void> cancelAll();
}
