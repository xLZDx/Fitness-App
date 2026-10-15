import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/scan_plan_context_provider.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_reminder.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';

ScanRecord _r(DateTime at) => ScanRecord(
    id: 's${at.microsecondsSinceEpoch}', createdAt: at, shots: const {});

class _MemRepo implements ScanRepository {
  final List<ScanRecord> items = [];
  @override
  Future<List<ScanRecord>> list() async =>
      [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

class _FullSurfaceSource extends ScanPlanContextSource {
  const _FullSurfaceSource();
  @override
  ScanPlanContext current() =>
      const ScanPlanContext(surfaceMode: ScanSurfaceMode.full);
}

class _ThrowingScheduler extends MockNotificationService {
  @override
  Future<ReminderOutcome> scheduleAt(String id,
          {required DateTime fireAt,
          required String title,
          required String body}) async =>
      throw StateError('plugin');
}

Future<void> pumpAuth() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scanReminderNextDue', () {
    final now = DateTime(2026, 10, 13, 12);
    test('no history: null',
        () => expect(scanReminderNextDue(const [], now), isNull));
    test('first Sunday 08:00 after newest scan + 5 days, order independent', () {
      final hist = [
        _r(DateTime(2026, 10, 1, 9)),
        _r(DateTime(2026, 10, 10, 9)),
        _r(DateTime(2026, 9, 1)),
      ];
      // Newest Sat 10 Oct + 5 days = Thu 15 Oct; next Sunday is 18 Oct.
      expect(scanReminderNextDue(hist, now), DateTime(2026, 10, 18, 8));
    });
    test('a Friday scan does not fire on the Sunday two days later', () {
      final fri = DateTime(2026, 10, 9, 10);
      expect(scanReminderNextDue([_r(fri)], DateTime(2026, 10, 9, 11)),
          DateTime(2026, 10, 18, 8));
    });
    test('overdue scan: next weekday slot strictly after now', () {
      expect(scanReminderNextDue([_r(DateTime(2026, 8, 1))], now),
          DateTime(2026, 10, 18, 8));
    });
    test('strictly after: same weekday and time as now moves a week', () {
      final sun = DateTime(2026, 10, 18, 8);
      expect(scanReminderNextDue([_r(DateTime(2026, 8, 1))], sun),
          DateTime(2026, 10, 25, 8));
    });
    test('custom weekday and time', () {
      expect(
          scanReminderNextDue([_r(DateTime(2026, 8, 1))], now,
              weekday: 3, minutes: 18 * 60 + 30),
          DateTime(2026, 10, 14, 18, 30));
    });
  });

  group('toggle and scheduling', () {
    late MockNotificationService notes;
    late _MemRepo repo;

    ProviderContainer make({bool notificationsEnabled = true}) {
      SharedPreferences.setMockInitialValues({});
      notes = MockNotificationService();
      repo = _MemRepo();
      final c = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(notes),
        scanPlanContextProvider.overrideWithValue(const _FullSurfaceSource()),
        scanRepositoryProvider.overrideWithValue(repo),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
        initialSettingsProvider.overrideWithValue(
            AppSettings(notificationsEnabled: notificationsEnabled)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle(ProviderContainer c) async {
      await c.read(authUserProvider.future);
      await c.read(scanHistoryProvider.future);
    }

    test('default off with no scans', () async {
      final c = make();
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isFalse);
    });

    test('default on once a scan exists and the user never chose', () async {
      final c = make();
      repo.items.add(_r(DateTime.now()));
      final sub = c.listen(scanReminderEnabledProvider, (_, __) {});
      addTearDown(sub.close);
      await settle(c);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(scanReminderEnabledProvider), isTrue);
    });

    test('enabling after a scan schedules the next Sunday 08:00, one id',
        () async {
      final c = make();
      final at = DateTime.now().subtract(const Duration(days: 2));
      repo.items.add(_r(at));
      await settle(c);
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(c.read(scanReminderEnabledProvider), isTrue);
      expect(notes.scheduled, hasLength(1));
      final s = notes.scheduled.single;
      expect(s.sessionId, kScanReminderId);
      expect(s.fireAt.weekday, DateTime.sunday);
      expect((s.fireAt.hour, s.fireAt.minute), (8, 0));
      expect(s.fireAt.isAfter(at.add(const Duration(days: 5))), isTrue);
      expect(s.title, isNotEmpty);
      await c.read(scanReminderEnabledProvider.notifier).sync();
      expect(notes.scheduled, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(scanReminderPrefKey('u1')), isTrue);
    });

    test('disabling cancels the pending reminder and persists off', () async {
      final c = make();
      repo.items.add(_r(DateTime.now()));
      await settle(c);
      final n = c.read(scanReminderEnabledProvider.notifier);
      await n.setEnabled(true);
      expect(notes.scheduled, hasLength(1));
      await n.setEnabled(false);
      expect(notes.scheduled, isEmpty);
      expect(c.read(scanReminderEnabledProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(scanReminderPrefKey('u1')), isFalse);
    });

    test('enabled before any scan: nothing yet, follows the first scan',
        () async {
      final c = make();
      await settle(c);
      final n = c.read(scanReminderEnabledProvider.notifier);
      await n.setEnabled(true);
      expect(notes.scheduled, isEmpty);
      repo.items.add(_r(DateTime.now()));
      c.invalidate(scanHistoryProvider);
      await n.sync();
      expect(notes.scheduled, hasLength(1));
    });

    test('notifications switched off in Settings: nothing scheduled', () async {
      final c = make(notificationsEnabled: false);
      repo.items.add(_r(DateTime.now()));
      await settle(c);
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(notes.scheduled, isEmpty);
    });

    test('an overdue scan is scheduled at the next weekly slot', () async {
      final c = make();
      repo.items.add(_r(DateTime.now().subtract(const Duration(days: 40))));
      await settle(c);
      final before = DateTime.now();
      final outcome =
          await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(outcome, ReminderOutcome.scheduled);
      expect(notes.scheduled, hasLength(1));
      final fireAt = notes.scheduled.single.fireAt;
      expect(fireAt.isAfter(before), isTrue);
      expect(fireAt.difference(before), lessThan(const Duration(days: 7)));
      expect(fireAt.weekday, DateTime.sunday);
      expect(c.read(scanReminderEnabledProvider), isTrue);
    });

    test('nothing to schedule stays null, distinct from failed', () async {
      final c = make();
      await settle(c);
      final n = c.read(scanReminderEnabledProvider.notifier);
      expect(await n.setEnabled(true), isNull);
    });

    test('a throwing platform call reports failed and the toggle reverts',
        () async {
      SharedPreferences.setMockInitialValues({});
      repo = _MemRepo()..items.add(_r(DateTime.now()));
      final c = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(_ThrowingScheduler()),
        scanRepositoryProvider.overrideWithValue(repo),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
        initialSettingsProvider
            .overrideWithValue(AppSettings(notificationsEnabled: true)),
      ]);
      addTearDown(c.dispose);
      await settle(c);
      final n = c.read(scanReminderEnabledProvider.notifier);
      expect(await n.setEnabled(true), ReminderOutcome.failed);
      expect(c.read(scanReminderEnabledProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(scanReminderPrefKey('u1')), isFalse);
    });
  });

  group('account isolation', () {
    late StreamController<AuthUser?> auth;
    late MockNotificationService notes;
    late _MemRepo repo;
    late ProviderContainer c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        scanReminderPrefKey('A'): true,
      });
      notes = MockNotificationService();
      repo = _MemRepo()..items.add(_r(DateTime.now()));
      auth = StreamController<AuthUser?>();
      c = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(notes),
        scanPlanContextProvider.overrideWithValue(const _FullSurfaceSource()),
        scanRepositoryProvider.overrideWithValue(repo),
        authUserProvider.overrideWith((_) => auth.stream),
        // The real store is per account; a fresh one per auth emission mirrors that.
        bodyScanSettingsStoreProvider.overrideWith((ref) {
          ref.watch(authUserProvider);
          return InMemoryBodyScanSettingsStore();
        }),
        initialSettingsProvider
            .overrideWithValue(AppSettings(notificationsEnabled: true)),
      ]);
      addTearDown(() async {
        c.dispose();
        await auth.close();
      });
      c.listen(scanReminderEnabledProvider, (_, __) {});
      auth.add(const AuthUser(uid: 'A', displayName: 'a'));
      await c.read(authUserProvider.future);
      await c.read(scanHistoryProvider.future);
      await pumpAuth();
      // A turns the reminder on explicitly and has one pending.
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(notes.scheduled, hasLength(1));
    });

    test('B does not inherit the toggle or the pending notification of A',
        () async {
      // B has no scans and no stored choice.
      repo.items.clear();
      c.invalidate(scanHistoryProvider);
      auth.add(const AuthUser(uid: 'B', displayName: 'b'));
      await pumpAuth();
      expect(c.read(scanReminderEnabledProvider), isFalse);
      expect(notes.scheduled, isEmpty);
      // B's own explicit choice does not touch A's stored one.
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(scanReminderPrefKey('B')), isTrue);
      expect(prefs.getBool(scanReminderPrefKey('A')), isTrue);
    });

    test('sign-out cancels the pending notification', () async {
      auth.add(null);
      await pumpAuth();
      expect(notes.scheduled, isEmpty);
    });
  });
}
