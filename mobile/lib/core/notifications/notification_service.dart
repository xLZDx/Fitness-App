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
  /// [title] and [body] are passed IN rather than built here. A notification is
  /// user-facing text, and this class has no `BuildContext` and no business
  /// knowing which language the user reads — building the strings here is why
  /// reminders shouted in English in a Russian app.
  Future<void> scheduleReminder(
    ScheduledSession session, {
    required String title,
    required String body,
    Duration leadTime = const Duration(minutes: 30),
  });

  /// Cancel a previously-scheduled reminder. Idempotent.
  Future<void> cancelReminder(String sessionId);

  /// Cancel every pending reminder (e.g. account sign-out).
  Future<void> cancelAll();
}
