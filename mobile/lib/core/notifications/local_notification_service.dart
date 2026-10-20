import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/workouts/data/scheduled_session.dart';
import 'notification_service.dart';

/// Production reminder service backed by `flutter_local_notifications`.
///
/// Each scheduled session maps to a notification keyed by a stable hash of
/// `session.id`, so re-saving the same session replaces the prior reminder
/// instead of duplicating it.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  /// null until the OS has actually been asked. Distinguishes "not asked yet"
  /// from "asked and refused" -- collapsing those two into a bool is how a
  /// denial turns into a prompt on every single schedule.
  bool? _permissionGranted;

  static const _channelId = 'workout_reminders';
  static const _channelName = 'Workout reminders';
  static const _channelDescription =
      'Lead-time reminders for scheduled workouts.';

  /// Stable 31-bit id (Android requires int). FNV-1a, not `String.hashCode`:
  /// the latter is not specified to be stable across Dart versions, so an app
  /// update could leave a pending reminder under an id nothing can cancel.
  int _idFor(String sessionId) => reminderIdFor(sessionId);

  /// The id earlier builds used. Cancelled alongside the current one so a
  /// reminder scheduled before the FNV-1a switch does not outlive its session.
  int _legacyIdFor(String sessionId) => sessionId.hashCode & 0x7FFFFFFF;

  Future<void> _cancelLegacy(String sessionId) async {
    final legacy = _legacyIdFor(sessionId);
    if (legacy != _idFor(sessionId)) await _plugin.cancel(legacy);
  }

  @override
  Future<bool> init() async {
    if (_initialized) return true;
    tz_data.initializeTimeZones();

    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // Already false on iOS: Darwin has always taken the permission
        // request as an explicit call. Android is what was prompting at
        // launch, and now neither does.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(init);
    _initialized = true;
    return true;
  }

  @override
  Future<bool> ensurePermission() async {
    if (!_initialized) await init();
    // Asked once per process. Re-prompting after a denial does nothing on
    // Android 13+ anyway -- the system returns the same answer without
    // showing anything -- and re-prompting after a grant is pure noise.
    if (_permissionGranted != null) return _permissionGranted!;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      // iOS or a platform with no gate. Treat as granted; a Darwin
      // implementation would request here.
      _permissionGranted = true;
      return true;
    }
    // 13+ requires runtime POST_NOTIFICATIONS approval; older OSes
    // return null/true.
    final granted = await android.requestNotificationsPermission();
    if (granted == false) {
      _permissionGranted = false;
      return false;
    }
    // No exact-alarm request: reminders use inexactAllowWhileIdle, which
    // needs neither SCHEDULE_EXACT_ALARM nor USE_EXACT_ALARM.
    _permissionGranted = true;
    return true;
  }

  @override
  Future<ReminderOutcome> scheduleReminder(
    ScheduledSession session, {
    required String title,
    required String body,
    Duration leadTime = const Duration(minutes: 30),
  }) =>
      // The lead-time arithmetic is the only thing this adds over the general
      // form. Expressed in terms of it rather than beside it, so the
      // "already past -> cancel" rule exists once instead of twice.
      scheduleAt(
        session.id,
        fireAt: session.scheduledFor.subtract(leadTime),
        title: title,
        body: body,
      );

  @override
  Future<ReminderOutcome> scheduleAt(
    String id, {
    required DateTime fireAt,
    required String title,
    required String body,
  }) async {
    // THE in-context moment: the user has just done the thing the reminder is
    // about, so a prompt explains itself. Returning early on a denial matters
    // -- scheduling into a channel the OS will not deliver leaves a reminder
    // that exists in our state and nowhere else.
    if (!await ensurePermission()) return ReminderOutcome.denied;
    if (!fireAt.isAfter(DateTime.now())) {
      // Reminder window already passed — clear any stale entry and bail.
      await cancelReminder(id);
      return ReminderOutcome.past;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const details = NotificationDetails(android: androidDetails);
    final tzWhen = tz.TZDateTime.from(fireAt, tz.local);

    // Drop a reminder an older build registered under the legacy id, or it
    // would fire next to the new one.
    await _cancelLegacy(id);
    await _plugin.zonedSchedule(
      _idFor(id),
      title,
      body,
      tzWhen,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: id,
    );
    return ReminderOutcome.scheduled;
  }

  @override
  Future<void> cancelReminder(String sessionId) async {
    await _plugin.cancel(_idFor(sessionId));
    await _cancelLegacy(sessionId);
  }

  @override
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

/// 32-bit FNV-1a over the UTF-16 code units of [sessionId], masked to 31 bits.
/// Deterministic on every platform and Dart version.
int reminderIdFor(String sessionId) {
  var h = 0x811C9DC5;
  for (final unit in sessionId.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}
