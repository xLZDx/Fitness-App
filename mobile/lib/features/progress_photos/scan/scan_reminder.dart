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
import 'scan_models.dart';
import 'scan_repository.dart';

/// The one notification id of the scan reminder. Shared on purpose: each
/// schedule replaces the pending one, so the reminder always follows the
/// newest scan. (The notification service maps the id with FNV-1a.)
const String kScanReminderId = 'body_scan_next';

/// Scans are reminded every two weeks, counted from the newest scan.
const Duration kScanReminderGap = Duration(days: 14);

/// Per-account preference key. Erased by the account-deletion wipe.
String scanReminderPrefKey(String uid) => 'progress_photos.scan_reminder.v1.$uid';

/// Raw due time: 14 days after the newest scan, or null with no history.
DateTime? scanReminderDueAt(List<ScanRecord> history) {
  if (history.isEmpty) return null;
  var newest = history.first.createdAt;
  for (final r in history) {
    if (r.createdAt.isAfter(newest)) newest = r.createdAt;
  }
  return newest.add(kScanReminderGap);
}

/// When the next scan is due: 14 days after the newest scan, never earlier
/// than [now] (an overdue scan is due now). Null when there is no scan yet.
DateTime? scanReminderNextDue(List<ScanRecord> history, DateTime now) {
  final due = scanReminderDueAt(history);
  if (due == null) return null;
  return due.isBefore(now) ? now : due;
}

/// The stored explicit choice for the signed-in account, or null if the user
/// never touched the toggle.
final _scanReminderPrefProvider = FutureProvider<bool?>((ref) async {
  final uid = (await ref.watch(authUserProvider.future))?.uid;
  if (uid == null || uid.isEmpty) return null;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(scanReminderPrefKey(uid));
});

/// Whether the 2-weekly scan reminder is on. With no stored choice it is off
/// until the first scan exists, and on from then on.
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
  /// choice, else "on once a scan exists". A provider that is still loading
  /// (an account switch) holds the previous account's value, so it is ignored.
  bool _compute() {
    final explicit = _explicit ?? _settled<bool?>(_scanReminderPrefProvider);
    if (explicit != null) return explicit;
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
    final outcome = await sync();
    if (enabled &&
        (outcome == ReminderOutcome.denied ||
            outcome == ReminderOutcome.failed)) {
      await prefs.setBool(scanReminderPrefKey(uid), false);
      _explicit = false;
      state = false;
    }
    return outcome;
  }

  /// Brings the pending notification in line with the toggle and the history.
  /// Call after a scan is saved or deleted (after invalidating
  /// [scanHistoryProvider]). Best-effort: never throws. Null means nothing to
  /// schedule; [ReminderOutcome.failed] means the attempt threw.
  Future<ReminderOutcome?> sync() async {
    final service = ref.read(notificationServiceProvider);
    try {
      final history = await ref.read(scanHistoryProvider.future);
      final now = DateTime.now();
      final due = scanReminderNextDue(history, now);
      final notificationsOn =
          ref.read(settingsControllerProvider).notificationsEnabled;
      if (!state || due == null || !notificationsOn) {
        await service.cancelReminder(kScanReminderId);
        return null;
      }
      final l = await AppLocalizations.delegate
          .load(Locale(ref.read(effectiveLanguageCodeProvider)));
      // An overdue scan is due now; the service refuses a time that is not in
      // the future, so "now" is pushed a minute ahead.
      return await service.scheduleAt(
        kScanReminderId,
        fireAt: due.isAfter(now) ? due : now.add(const Duration(minutes: 1)),
        title: l.photosReminderTitle,
        body: l.photosReminderBody,
      );
    } catch (e) {
      debugPrint('scan reminder not synced: $e');
      return ReminderOutcome.failed;
    }
  }
}
