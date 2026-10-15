// C17 weekly scan reminder: the cases `scan_reminder_test.dart` does not cover
// (SCAN-27, I18N-06). The pure rule at its boundaries and across DST, the
// settings -> v1 SharedPreferences -> default resolution order, the
// measurement-only default (D-74), paused tracking (D-77), the synced
// `reminder` map and the localised notification text.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
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

class _Source extends ScanPlanContextSource {
  const _Source(this.mode);
  final ScanSurfaceMode mode;
  @override
  ScanPlanContext current() => ScanPlanContext(surfaceMode: mode);
}

Future<void> _pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nextScanReminderFire: boundaries', () {
    test('no scan: null whatever the clock', () {
      expect(nextScanReminderFire(now: DateTime(2026, 10, 15), newestScan: null),
          isNull);
    });

    test('exactly newest + 5 days on the slot is NOT eligible (strictly after)',
        () {
      // Tue 13 Oct 08:00 + 5 days = Sun 18 Oct 08:00 exactly.
      final scan = DateTime(2026, 10, 13, 8);
      expect(nextScanReminderFire(now: DateTime(2026, 10, 13, 9), newestScan: scan),
          DateTime(2026, 10, 25, 8));
    });

    test('one minute before the 5-day mark the slot is still eligible', () {
      final scan = DateTime(2026, 10, 13, 7, 59);
      expect(nextScanReminderFire(now: DateTime(2026, 10, 13, 9), newestScan: scan),
          DateTime(2026, 10, 18, 8));
    });

    test('a scan on the slot itself waits for the following week', () {
      // Sun 11 Oct 08:00: +5 days is Fri 16 Oct, next Sunday is 18 Oct.
      expect(
          nextScanReminderFire(
              now: DateTime(2026, 10, 11, 8, 5),
              newestScan: DateTime(2026, 10, 11, 8)),
          DateTime(2026, 10, 18, 8));
    });

    test('now later than newest + 5 days drives the result, not the scan', () {
      final scan = DateTime(2026, 10, 1, 9);
      // Mon 19 Oct: the Sunday 18 Oct slot is already behind.
      expect(nextScanReminderFire(now: DateTime(2026, 10, 19, 7), newestScan: scan),
          DateTime(2026, 10, 25, 8));
    });

    test('now just before the slot (one minute): fires today', () {
      expect(
          nextScanReminderFire(
              now: DateTime(2026, 10, 18, 7, 59),
              newestScan: DateTime(2026, 8, 1)),
          DateTime(2026, 10, 18, 8));
    });

    test('a scan dated in the future (clock skew) still waits 5 days', () {
      // newest Fri 23 Oct + 5 = Wed 28 Oct; next Sunday 1 Nov.
      expect(
          nextScanReminderFire(
              now: DateTime(2026, 10, 15, 12), newestScan: DateTime(2026, 10, 23, 10)),
          DateTime(2026, 11, 1, 8));
    });

    test('year rollover', () {
      // Tue 29 Dec 2026 09:00 + 5 = Sun 3 Jan 2027 09:00 (after the slot).
      expect(
          nextScanReminderFire(
              now: DateTime(2026, 12, 29, 10), newestScan: DateTime(2026, 12, 29, 9)),
          DateTime(2027, 1, 10, 8));
    });

    test('leap day: Mon 24 Feb 2028 + slots crosses 29 Feb', () {
      final out = nextScanReminderFire(
          now: DateTime(2028, 2, 24, 10),
          newestScan: DateTime(2028, 2, 24, 9),
          weekday: 3,
          minutes: 600)!;
      // +5 = Sat 26 Feb 09:00; next Wednesday is 1 Mar 2028 (leap year).
      expect(out, DateTime(2028, 3, 1, 10));
    });

    test('every weekday and the minute extremes land on the requested slot', () {
      final scan = DateTime(2026, 8, 1);
      final now = DateTime(2026, 10, 15, 12); // Thursday
      for (var wd = 1; wd <= 7; wd++) {
        for (final m in [0, 1, 1439]) {
          final out = nextScanReminderFire(
              now: now, newestScan: scan, weekday: wd, minutes: m)!;
          expect(out.weekday, wd, reason: 'weekday $wd min $m');
          expect((out.hour, out.minute), (m ~/ 60, m % 60));
          expect(out.isAfter(now), isTrue);
          expect(out.difference(now), lessThanOrEqualTo(const Duration(days: 7)));
        }
      }
    });

    test('out-of-range weekday falls back to Sunday, minutes to 08:00', () {
      final scan = DateTime(2026, 8, 1);
      final now = DateTime(2026, 10, 15, 12);
      final want = DateTime(2026, 10, 18, 8);
      for (final wd in [0, 8, -3]) {
        expect(nextScanReminderFire(now: now, newestScan: scan, weekday: wd),
            want,
            reason: 'weekday $wd');
      }
      for (final m in [-1, 1440, 99999]) {
        expect(nextScanReminderFire(now: now, newestScan: scan, minutes: m),
            want,
            reason: 'minutes $m');
      }
    });

    test('the defaults are Sunday and 08:00', () {
      expect(ScanReminderPrefs.kDefaultReminderWeekday, DateTime.sunday);
      expect(ScanReminderPrefs.kDefaultReminderMinutes, 8 * 60);
      expect(kScanReminderMinGap, const Duration(days: 5));
    });

    test('newestScanAt picks the newest regardless of order', () {
      expect(newestScanAt(const []), isNull);
      final a = _r(DateTime(2026, 1, 1));
      final b = _r(DateTime(2026, 3, 1));
      final c = _r(DateTime(2026, 2, 1));
      expect(newestScanAt([a, b, c]), DateTime(2026, 3, 1));
      expect(newestScanAt([b, c, a]), DateTime(2026, 3, 1));
    });
  });

  group('nextScanReminderFire: DST', () {
    // Calendar arithmetic keeps the wall-clock time across a DST change. The
    // check is meaningful when the machine zone observes DST (the dates cover
    // the EU and US spring/autumn changes); in a fixed-offset zone it is still
    // a valid property check.
    test('the slot keeps 08:00 local on every Sunday across a year', () {
      var cursor = DateTime(2026, 1, 1, 12);
      final scan = DateTime(2025, 12, 1);
      for (var i = 0; i < 366; i++) {
        final out = nextScanReminderFire(now: cursor, newestScan: scan)!;
        expect(out.weekday, DateTime.sunday, reason: '$cursor');
        expect((out.hour, out.minute), (8, 0), reason: 'wall clock drifted at $cursor');
        expect(out.isAfter(cursor), isTrue);
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1, 12);
      }
    });

    test('a fire after a DST change is a whole number of calendar days away', () {
      for (final start in [
        DateTime(2026, 3, 7, 12), // before the US change (8 Mar)
        DateTime(2026, 3, 28, 12), // before the EU change (29 Mar)
        DateTime(2026, 10, 24, 12), // before the EU change (25 Oct)
        DateTime(2026, 10, 31, 12), // before the US change (1 Nov)
      ]) {
        final scan = DateTime(start.year, start.month, start.day - 30);
        final a = nextScanReminderFire(now: start, newestScan: scan)!;
        final b = nextScanReminderFire(now: a, newestScan: scan)!;
        // b is the next slot strictly after a: the same wall clock one week on.
        expect(b, DateTime(a.year, a.month, a.day + 7, 8), reason: '$start');
        expect((b.hour, b.minute), (8, 0));
      }
    });
  });

  group('notifier: resolution order and defaults', () {
    late MockNotificationService notes;
    late _MemRepo repo;
    late InMemoryBodyScanSettingsStore store;

    ProviderContainer make({
      ScanSurfaceMode mode = ScanSurfaceMode.full,
      Map<String, Object> prefs = const {},
      BodyScanSettings settings = const BodyScanSettings(),
      bool withScan = true,
      AppSettings app = const AppSettings(),
    }) {
      SharedPreferences.setMockInitialValues(prefs);
      notes = MockNotificationService();
      repo = _MemRepo();
      if (withScan) repo.items.add(_r(DateTime.now().subtract(const Duration(days: 1))));
      store = InMemoryBodyScanSettingsStore(settings);
      final c = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(notes),
        scanPlanContextProvider.overrideWithValue(_Source(mode)),
        scanRepositoryProvider.overrideWithValue(repo),
        bodyScanSettingsStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
        initialSettingsProvider.overrideWithValue(app),
      ]);
      addTearDown(c.dispose);
      c.listen(scanReminderEnabledProvider, (_, __) {});
      return c;
    }

    Future<void> settle(ProviderContainer c) async {
      await c.read(authUserProvider.future);
      await c.read(scanHistoryProvider.future);
      await c.read(bodyScanSettingsProvider.future);
      await _pump();
    }

    test('schedule provider defaults to Sunday 08:00 with no stored choice',
        () async {
      final c = make();
      await settle(c);
      final s = c.read(scanReminderScheduleProvider);
      expect((s.weekday, s.minutes), (7, 480));
    });

    test('schedule provider follows the stored weekday and minutes', () async {
      final c = make(
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: true, weekday: 3, minutes: 1110)));
      await settle(c);
      final s = c.read(scanReminderScheduleProvider);
      expect((s.weekday, s.minutes), (3, 1110));
    });

    test('v1 true is honoured as enabled even with no scan (explicit choice)',
        () async {
      final c = make(
          prefs: {scanReminderPrefKey('u1'): true}, withScan: false);
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isTrue);
    });

    test('v1 false beats the "on once a scan exists" default', () async {
      final c = make(prefs: {scanReminderPrefKey('u1'): false});
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isFalse);
    });

    test('synced reminder.enabled beats the v1 bool (both directions)', () async {
      final off = make(
          prefs: {scanReminderPrefKey('u1'): true},
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)));
      await settle(off);
      expect(off.read(scanReminderEnabledProvider), isFalse);

      final on = make(
          prefs: {scanReminderPrefKey('u1'): false},
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: true)),
          withScan: false);
      await settle(on);
      expect(on.read(scanReminderEnabledProvider), isTrue);
    });

    test('measurementOnly: default stays OFF even with scans (D-74)', () async {
      final c = make(mode: ScanSurfaceMode.measurementOnly);
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isFalse);
      await c.read(scanReminderEnabledProvider.notifier).sync();
      expect(notes.scheduled, isEmpty);
    });

    test('full surface: the same account IS on by default (control case)',
        () async {
      final c = make(mode: ScanSurfaceMode.full);
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isTrue);
    });

    test('measurementOnly: an explicit opt-in is honoured and schedules',
        () async {
      final c = make(mode: ScanSurfaceMode.measurementOnly);
      await settle(c);
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(c.read(scanReminderEnabledProvider), isTrue);
      expect(notes.scheduled, hasLength(1));
    });

    test('with no scan and no choice the default is off', () async {
      final c = make(withScan: false);
      await settle(c);
      expect(c.read(scanReminderEnabledProvider), isFalse);
    });
  });

  group('notifier: schedule, pause and synced map', () {
    late MockNotificationService notes;
    late _MemRepo repo;
    late InMemoryBodyScanSettingsStore store;

    Future<ProviderContainer> make(
        {BodyScanSettings settings = const BodyScanSettings(),
        AppSettings app = const AppSettings()}) async {
      SharedPreferences.setMockInitialValues({});
      notes = MockNotificationService();
      repo = _MemRepo()
        ..items.add(_r(DateTime.now().subtract(const Duration(days: 1))));
      store = InMemoryBodyScanSettingsStore(settings);
      final c = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(notes),
        scanPlanContextProvider
            .overrideWithValue(const _Source(ScanSurfaceMode.full)),
        scanRepositoryProvider.overrideWithValue(repo),
        bodyScanSettingsStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
        initialSettingsProvider.overrideWithValue(app),
      ]);
      addTearDown(c.dispose);
      c.listen(scanReminderEnabledProvider, (_, __) {});
      await c.read(authUserProvider.future);
      await c.read(scanHistoryProvider.future);
      await c.read(bodyScanSettingsProvider.future);
      await _pump();
      return c;
    }

    test('the stored weekday and time drive the scheduled slot', () async {
      final c = await make(
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: true, weekday: 3, minutes: 1110)));
      await c.read(scanReminderEnabledProvider.notifier).sync();
      final s = notes.scheduled.single;
      expect(s.fireAt.weekday, DateTime.wednesday);
      expect((s.fireAt.hour, s.fireAt.minute), (18, 30));
    });

    test('the fire is the EARLIEST slot after newest + 5 days (no skipped week)',
        () async {
      final c = await make();
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      final fire = notes.scheduled.single.fireAt;
      final earliest = repo.items.single.createdAt.add(const Duration(days: 5));
      expect(fire.isAfter(earliest), isTrue);
      // One week earlier would already have been eligible if it were allowed.
      final weekBefore = DateTime(fire.year, fire.month, fire.day - 7, 8);
      expect(weekBefore.isAfter(earliest) && weekBefore.isAfter(DateTime.now()),
          isFalse);
    });

    test('setEnabled stores the synced reminder map with the current schedule',
        () async {
      final c = await make(
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false, weekday: 2, minutes: 90)));
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      await _pump();
      final stored = (await store.watch().first).reminder;
      expect(stored, const ScanReminderPrefs(enabled: true, weekday: 2, minutes: 90));
    });

    test('setSchedule persists the choice and moves the pending reminder',
        () async {
      final c = await make();
      final n = c.read(scanReminderEnabledProvider.notifier);
      await n.setEnabled(true);
      expect(notes.scheduled.single.fireAt.weekday, DateTime.sunday);
      final outcome = await n.setSchedule(weekday: 1, minutes: 0);
      await _pump();
      expect(outcome, isNotNull);
      expect(notes.scheduled, hasLength(1));
      final fire = notes.scheduled.single.fireAt;
      expect(fire.weekday, DateTime.monday);
      expect((fire.hour, fire.minute), (0, 0));
      final stored = (await store.watch().first).reminder;
      expect(stored, const ScanReminderPrefs(enabled: true, weekday: 1, minutes: 0));
    });

    test('setSchedule with only a weekday keeps the stored time', () async {
      final c = await make(
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: true, weekday: 7, minutes: 1110)));
      final n = c.read(scanReminderEnabledProvider.notifier);
      await n.setSchedule(weekday: 5);
      await _pump();
      final fire = notes.scheduled.single.fireAt;
      expect(fire.weekday, DateTime.friday);
      expect((fire.hour, fire.minute), (18, 30));
    });

    test('paused cancels the pending reminder and un-pausing restores it',
        () async {
      final c = await make();
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(notes.scheduled, hasLength(1));

      await store.setPaused(true);
      await _pump();
      expect(notes.scheduled, isEmpty, reason: 'paused tracking must cancel');
      // The user's toggle itself is untouched by pausing.
      expect(c.read(scanReminderEnabledProvider), isTrue);

      // While paused, a sync (e.g. after a scan) must not re-arm it.
      await c.read(scanReminderEnabledProvider.notifier).sync();
      expect(notes.scheduled, isEmpty);

      await store.setPaused(false);
      await _pump();
      expect(notes.scheduled, hasLength(1));
      expect(notes.scheduled.single.sessionId, kScanReminderId);
    });

    test('paused from the start: enabling schedules nothing', () async {
      final c = await make(settings: const BodyScanSettings(paused: true));
      await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
      expect(notes.scheduled, isEmpty);
    });

    test('the scheduled text is the localised string of the active language',
        () async {
      for (final lang in [AppLanguage.ru, AppLanguage.en]) {
        final c = await make(app: AppSettings(language: lang));
        await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
        final l = await AppLocalizations.delegate.load(Locale(lang.name));
        final s = notes.scheduled.single;
        expect(s.title, l.scanReminderTitle, reason: lang.name);
        expect(s.body, l.scanReminderBody, reason: lang.name);
        expect(s.title, isNotEmpty);
        expect(s.body, isNotEmpty);
      }
    });

    test('EN and RU notification texts differ and promise no body-fat number',
        () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      expect(ru.scanReminderTitle, isNot(en.scanReminderTitle));
      expect(ru.scanReminderBody, isNot(en.scanReminderBody));
      for (final t in [en.scanReminderTitle, en.scanReminderBody]) {
        expect(t.toLowerCase(), isNot(contains('body fat')));
        expect(t.toLowerCase(), isNot(contains('%')));
      }
    });
  });
}
