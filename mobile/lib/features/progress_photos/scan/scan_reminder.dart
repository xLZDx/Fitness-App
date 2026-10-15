import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/settings/state/settings_providers.dart';
import '../../auth/data/auth_user.dart';
import '../../auth/state/auth_providers.dart';
import '../../body_scan/data/scan_plan_context.dart';
import '../../body_scan/state/body_scan_providers.dart';
import '../../body_scan/state/body_scan_settings.dart';
import '../../body_scan/state/scan_plan_context_provider.dart';
import 'scan_models.dart';
import 'scan_repository.dart';

/// The one notification id of the scan reminder. Shared on purpose: each
/// schedule replaces the pending one, so the reminder always follows the
/// newest scan. (The notification service maps the id with FNV-1a.)
const String kScanReminderId = 'body_scan_next';

/// A reminder never fires sooner than this after the newest scan (design s19):
/// a Friday scan does not trigger a Sunday reminder two days later.
const Duration kScanReminderMinGap = Duration(days: 5);

/// Per-account preference key (the v1 bool, kept as a read fallback and still
/// written). Erased by the account-deletion wipe.
String scanReminderPrefKey(String uid) => 'progress_photos.scan_reminder.v1.$uid';

/// The newest scan time, or null with no history.
DateTime? newestScanAt(List<ScanRecord> history) {
  if (history.isEmpty) return null;
  var newest = history.first.createdAt;
  for (final r in history) {
    if (r.createdAt.isAfter(newest)) newest = r.createdAt;
  }
  return newest;
}

/// Pure weekly rule: the first [weekday] (ISO 1..7) at [minutes] after local
/// midnight that is STRICTLY after `max(now, newestScan + 5 days)`. Null when
/// there is no scan yet. Calendar arithmetic (not 24 h additions), so a DST
/// change keeps the wall-clock time.
DateTime? nextScanReminderFire({
  required DateTime now,
  required DateTime? newestScan,
  int weekday = ScanReminderPrefs.kDefaultReminderWeekday,
  int minutes = ScanReminderPrefs.kDefaultReminderMinutes,
}) {
  if (newestScan == null) return null;
  final wd = weekday < 1 || weekday > 7
      ? ScanReminderPrefs.kDefaultReminderWeekday
      : weekday;
  final mins = minutes < 0 || minutes > 1439
      ? ScanReminderPrefs.kDefaultReminderMinutes
      : minutes;
  final earliest = newestScan.add(kScanReminderMinGap);
  final after = earliest.isAfter(now) ? earliest : now;
  for (var i = 0; i <= 14; i++) {
    final c = DateTime(
        after.year, after.month, after.day + i, mins ~/ 60, mins % 60);
    if (c.weekday == wd && c.isAfter(after)) return c;
  }
  return null; // unreachable: some day in 0..14 matches
}

/// [nextScanReminderFire] from a scan history.
DateTime? scanReminderNextDue(
  List<ScanRecord> history,
  DateTime now, {
  int weekday = ScanReminderPrefs.kDefaultReminderWeekday,
  int minutes = ScanReminderPrefs.kDefaultReminderMinutes,
}) =>
    nextScanReminderFire(
      now: now,
      newestScan: newestScanAt(history),
      weekday: weekday,
      minutes: minutes,
    );

/// The weekday/time the reminder uses: the stored choice, else Sunday 08:00.
final scanReminderScheduleProvider =
    Provider<({int weekday, int minutes})>((ref) {
  final r = ref.watch(bodyScanSettingsProvider).valueOrNull?.reminder;
  return (
    weekday: r?.weekday ?? ScanReminderPrefs.kDefaultReminderWeekday,
    minutes: r?.minutes ?? ScanReminderPrefs.kDefaultReminderMinutes,
  );
});

/// The stored explicit v1 choice for the signed-in account, or null if the user
/// never touched the toggle.
final _scanReminderPrefProvider = FutureProvider<bool?>((ref) async {
  final uid = (await ref.watch(authUserProvider.future))?.uid;
  if (uid == null || uid.isEmpty) return null;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(scanReminderPrefKey(uid));
});

/// Whether the weekly scan reminder is on. With no stored choice it is off
/// until the first scan exists and on from then on, except in
/// `measurementOnly` mode where the default stays off (D-74).
final scanReminderEnabledProvider =
    NotifierProvider<ScanReminderNotifier, bool>(ScanReminderNotifier.new);

class ScanReminderNotifier extends Notifier<bool> {
  /// The user's explicit choice in this session, once made. Held here rather
  /// than re-read through an invalidated provider, so a toggle never marks
  /// this notifier outdated in the middle of [sync].
  bool? _explicit;

  /// The account this notifier's state belongs to.
  String? _uid;

  /// The toggle for the current account from what is stored: the explicit
  /// choice (synced settings, else the v1 bool), else "on once a scan exists"
  /// unless the surface is measurement only. A provider that is still loading
  /// (an account switch) holds the previous account's value, so it is ignored.
  bool _compute() {
    final explicit = _explicit ??
        _settled<BodyScanSettings>(bodyScanSettingsProvider)
            ?.reminder
            ?.enabled ??
        _settled<bool?>(_scanReminderPrefProvider);
    if (explicit != null) return explicit;
    if (ref.read(scanPlanContextValueProvider).surfaceMode !=
        ScanSurfaceMode.full) {
      return false;
    }
    final history = _settled<List<ScanRecord>>(scanHistoryProvider);
    return history != null && history.isNotEmpty;
  }

  T? _settled<T extends Object?>(ProviderListenable<AsyncValue<T>> p) {
    final v = ref.read(p);
    return v.isLoading ? null : v.valueOrNull;
  }

  @override
  bool build() {
    // Only `listen`/`read` here, never `watch`: a late-arriving preference or
    // history must update the value without marking this notifier outdated
    // while [sync] is reading through `ref`.
    _uid = ref.read(authUserProvider).valueOrNull?.uid;
    ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (_, next) {
      if (next.isLoading) return;
      final uid = next.valueOrNull?.uid;
      if (uid == _uid) return;
      // Account switch or sign-out: nothing of the previous account's toggle
      // or pending notification may carry over.
      _uid = uid;
      _explicit = null;
      state = _compute();
      _cancelPending();
    });
    ref.listen<AsyncValue<bool?>>(_scanReminderPrefProvider, (_, next) {
      if (next.isLoading || _explicit != null) return;
      state = _compute();
    });
    ref.listen<AsyncValue<BodyScanSettings>>(bodyScanSettingsProvider,
        (prev, next) {
      if (next.isLoading) return;
      // "Pause tracking" cancels / restores the pending reminder (D-77).
      final wasPaused = prev?.valueOrNull?.paused;
      if (wasPaused != null && wasPaused != next.valueOrNull?.paused) {
        sync();
      }
      if (_explicit != null) return;
      state = _compute();
    });
    ref.listen<ScanPlanContext>(scanPlanContextValueProvider, (_, __) {
      if (_explicit != null) return;
      state = _compute();
    });
    ref.listen<AsyncValue<List<ScanRecord>>>(scanHistoryProvider, (_, next) {
      if (next.isLoading || _explicit != null) return;
      state = _compute();
    });
    return _compute();
  }

  Future<void> _cancelPending() async {
    try {
      await ref.read(notificationServiceProvider).cancelReminder(kScanReminderId);
    } catch (e) {
      debugPrint('scan reminder not cancelled: $e');
    }
  }

  /// Persists the choice and (un)schedules. Returns the schedule outcome, or
  /// null when nothing was scheduled (turned off, or no scan yet). When the
  /// platform refuses permission, or the call fails, the toggle falls back to
  /// off.
  Future<ReminderOutcome?> setEnabled(bool enabled) async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(scanReminderPrefKey(uid), enabled);
    _explicit = enabled;
    state = enabled;
    await _storeSynced(enabled);
    final outcome = await sync();
    if (enabled &&
        (outcome == ReminderOutcome.denied ||
            outcome == ReminderOutcome.failed)) {
      await prefs.setBool(scanReminderPrefKey(uid), false);
      _explicit = false;
      state = false;
      await _storeSynced(false);
    }
    return outcome;
  }

  /// Writes the synced `reminder` map (enabled + current weekday/time).
  /// Best-effort: the local toggle and the notification do not depend on it.
  Future<void> _storeSynced(bool enabled) async {
    try {
      final s = ref.read(scanReminderScheduleProvider);
      await ref.read(bodyScanSettingsStoreProvider).setReminder(
          ScanReminderPrefs(
              enabled: enabled, weekday: s.weekday, minutes: s.minutes));
    } catch (e) {
      debugPrint('scan reminder settings not stored: $e');
    }
  }

  /// Changes the weekday / time of the weekly reminder and re-syncs.
  Future<ReminderOutcome?> setSchedule({int? weekday, int? minutes}) async {
    try {
      final s = ref.read(scanReminderScheduleProvider);
      await ref.read(bodyScanSettingsStoreProvider).setReminder(
          ScanReminderPrefs(
              enabled: state,
              weekday: weekday ?? s.weekday,
              minutes: minutes ?? s.minutes));
    } catch (e) {
      debugPrint('scan reminder schedule not stored: $e');
      return ReminderOutcome.failed;
    }
    // The settings stream delivers the new value asynchronously; the re-sync
    // takes the explicit values, not the (possibly stale) provider.
    return sync(weekday: weekday, minutes: minutes);
  }

  /// Brings the pending notification in line with the toggle and the history.
  /// Call after a scan is saved or deleted (after invalidating
  /// [scanHistoryProvider]). Best-effort: never throws. Null means nothing to
  /// schedule; [ReminderOutcome.failed] means the attempt threw. Paused
  /// tracking cancels the reminder (D-77).
  ///
  /// Notification tap: `LocalNotificationService` registers no tap handler, so
  /// tapping the reminder only opens the app (documented limit, design s19).
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async {
    final service = ref.read(notificationServiceProvider);
    try {
      final history = await ref.read(scanHistoryProvider.future);
      final now = DateTime.now();
      final s = ref.read(scanReminderScheduleProvider);
      final due = scanReminderNextDue(history, now,
          weekday: weekday ?? s.weekday, minutes: minutes ?? s.minutes);
      final notificationsOn =
          ref.read(settingsControllerProvider).notificationsEnabled;
      final paused =
          ref.read(bodyScanSettingsProvider).valueOrNull?.paused ?? false;
      if (!state || due == null || !notificationsOn || paused) {
        await service.cancelReminder(kScanReminderId);
        return null;
      }
      final l = await AppLocalizations.delegate
          .load(Locale(ref.read(effectiveLanguageCodeProvider)));
      // [due] is strictly after now by construction.
      return await service.scheduleAt(
        kScanReminderId,
        fireAt: due,
        title: l.scanReminderTitle,
        body: l.scanReminderBody,
      );
    } catch (e) {
      debugPrint('scan reminder not synced: $e');
      return ReminderOutcome.failed;
    }
  }
}
