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

  static const _channelId = 'workout_reminders';
  static const _channelName = 'Workout reminders';
  static const _channelDescription =
      'Lead-time reminders for scheduled workouts.';

  /// Stable 31-bit hash so different sessions never collide on the
  /// notification id (Android requires int).
  int _idFor(String sessionId) => sessionId.hashCode & 0x7FFFFFFF;

  @override
  Future<bool> init() async {
    if (_initialized) return true;
    tz_data.initializeTimeZones();

    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(init);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // 13+ requires runtime POST_NOTIFICATIONS approval; older OSes
      // return null/true.
      final granted = await android.requestNotificationsPermission();
      if (granted == false) {
        _initialized = true;
        return false;
      }
      // Best-effort exact-alarm grant on 12+. The user can still revoke it
      // manually; we degrade to inexact scheduling later if so.
      await android.requestExactAlarmsPermission();
    }
    _initialized = true;
    return true;
  }

  @override
  Future<void> scheduleReminder(
    ScheduledSession session, {
    required String title,
    required String body,
    Duration leadTime = const Duration(minutes: 30),
  }) async {
    if (!_initialized) await init();
    final fireAt = session.scheduledFor.subtract(leadTime);
    if (!fireAt.isAfter(DateTime.now())) {
      // Reminder window already passed — clear any stale entry and bail.
      await cancelReminder(session.id);
      return;
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

    await _plugin.zonedSchedule(
      _idFor(session.id),
      title,
      body,
      tzWhen,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: session.id,
    );
  }

  @override
  Future<void> cancelReminder(String sessionId) async {
    await _plugin.cancel(_idFor(sessionId));
  }

  @override
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
