import '../../features/workouts/data/scheduled_session.dart';

/// Cross-platform reminder service. Production uses
/// `LocalNotificationService` (`flutter_local_notifications`); tests + the
/// default Riverpod provider use `MockNotificationService` so unit tests
/// don't drag in a platform plugin.
abstract class NotificationService {
  /// Plugin warm-up ONLY: timezone database, channel registration, tap
  /// handler. Never prompts. Safe to call multiple times, and safe to call
  /// from `main()` before the first frame.
  ///
  /// The permission request used to live here, which meant the Android
  /// "Allow notifications?" dialog was the first thing a new user saw --
  /// before the app had shown a single screen, let alone a reason to want
  /// reminders. A prompt with no context is a prompt that gets denied, and on
  /// Android a denial is close to permanent: the system stops re-asking, and
  /// the only way back is Settings.
  Future<bool> init();

  /// Ask for notification permission, at a moment the user can connect to a
  /// reminder they just asked for. Returns true when reminders can be
  /// delivered.
  ///
  /// Separate from [init] so the prompt is tied to intent rather than to
  /// process start. Call it where the user has just done something that
  /// implies they want to be reminded -- [scheduleReminder] does exactly
  /// that, so most callers never need this directly.
  Future<bool> ensurePermission();

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

  /// Schedule a one-shot reminder at an absolute time, keyed by [id].
  ///
  /// The general form. [scheduleReminder] is this plus the lead-time
  /// arithmetic — a workout reminder is a `scheduleAt` whose time happens to
  /// be derived from a session.
  ///
  /// Exists because not every reminder is about a [ScheduledSession]. The
  /// first one that was not is the progress-photo nudge: it has no session, no
  /// exercise and no duration, and forcing it through the session-shaped call
  /// would have meant inventing a fake session to carry a date.
  ///
  /// Same contract as [scheduleReminder]: replaces any prior reminder with the
  /// same [id], and when [fireAt] is already past it cancels rather than fires.
  /// Cancel with [cancelReminder], which keys on the same string.
  Future<void> scheduleAt(
    String id, {
    required DateTime fireAt,
    required String title,
    required String body,
  });

  /// Cancel a previously-scheduled reminder. Idempotent.
  ///
  /// The parameter is named for its first caller; any [scheduleAt] id works.
  Future<void> cancelReminder(String sessionId);

  /// Cancel every pending reminder (e.g. account sign-out).
  Future<void> cancelAll();
}
