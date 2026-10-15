// C17 part 1: the `reminder` field of `body_scan_settings/main` (design s5.2,
// s19): JSON round trip, tolerant reads, copyWith/equality and the in-memory
// store contract. The Firestore store needs a Firestore fake the project does
// not have; its wire shape is covered through `toJson` here and the rules tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';

void main() {
  group('ScanReminderPrefs JSON', () {
    test('toJson is exactly the rules shape {enabled, weekday, minutes}', () {
      expect(
          const ScanReminderPrefs(enabled: true, weekday: 3, minutes: 1110)
              .toJson(),
          {'enabled': true, 'weekday': 3, 'minutes': 1110});
      expect(const ScanReminderPrefs(enabled: false).toJson(),
          {'enabled': false, 'weekday': 7, 'minutes': 480});
    });

    test('round trip is lossless for the boundary values', () {
      for (final wd in [1, 7]) {
        for (final m in [0, 480, 1439]) {
          for (final e in [true, false]) {
            final p = ScanReminderPrefs(enabled: e, weekday: wd, minutes: m);
            expect(ScanReminderPrefs.tryFromJson(p.toJson()), p);
          }
        }
      }
    });

    test('out-of-range or mistyped weekday/minutes fall back to the defaults',
        () {
      for (final wd in [0, 8, -1, '3', 3.5, null]) {
        final p = ScanReminderPrefs.tryFromJson(
            {'enabled': true, 'weekday': wd, 'minutes': 60})!;
        expect(p.weekday, 7, reason: 'weekday $wd');
        expect(p.minutes, 60);
      }
      for (final m in [-1, 1440, '60', 60.5, null]) {
        final p = ScanReminderPrefs.tryFromJson(
            {'enabled': true, 'weekday': 2, 'minutes': m})!;
        expect(p.minutes, 480, reason: 'minutes $m');
        expect(p.weekday, 2);
      }
    });

    test('a missing or non-bool enabled, or a non-map, reads as "never chosen"',
        () {
      expect(ScanReminderPrefs.tryFromJson(null), isNull);
      expect(ScanReminderPrefs.tryFromJson('x'), isNull);
      expect(ScanReminderPrefs.tryFromJson({'weekday': 3}), isNull);
      expect(ScanReminderPrefs.tryFromJson({'enabled': 'true'}), isNull);
      expect(ScanReminderPrefs.tryFromJson({'enabled': 1}), isNull);
    });

    test('equality and hashCode cover all three fields', () {
      const a = ScanReminderPrefs(enabled: true, weekday: 3, minutes: 60);
      expect(a, const ScanReminderPrefs(enabled: true, weekday: 3, minutes: 60));
      expect(a.hashCode,
          const ScanReminderPrefs(enabled: true, weekday: 3, minutes: 60).hashCode);
      expect(a == a.copyWith(enabled: false), isFalse);
      expect(a == a.copyWith(weekday: 4), isFalse);
      expect(a == a.copyWith(minutes: 61), isFalse);
      expect(a.copyWith(), a);
    });
  });

  group('BodyScanSettings.reminder', () {
    test('default is null (never chosen)', () {
      expect(const BodyScanSettings().reminder, isNull);
      expect(BodyScanSettings.fromJson(null).reminder, isNull);
      expect(BodyScanSettings.fromJson(<String, Object?>{}).reminder, isNull);
    });

    test('fromJson reads the stored map alongside the other fields', () {
      final s = BodyScanSettings.fromJson({
        'retentionDays': 30,
        'paused': true,
        'cloudConsent': {'version': 1},
        'reminder': {'enabled': true, 'weekday': 5, 'minutes': 1200},
      });
      expect(s.retentionDays, 30);
      expect(s.paused, isTrue);
      expect(s.cloudConsentVersion, 1);
      expect(s.reminder,
          const ScanReminderPrefs(enabled: true, weekday: 5, minutes: 1200));
    });

    test('a malformed reminder does not disturb the rest of the document', () {
      final s = BodyScanSettings.fromJson(
          {'retentionDays': 90, 'reminder': 'garbage'});
      expect(s.retentionDays, 90);
      expect(s.reminder, isNull);
    });

    test('copyWith keeps the reminder when other fields change and vice versa',
        () {
      const base = BodyScanSettings(
          retentionDays: 30,
          reminder: ScanReminderPrefs(enabled: true, weekday: 2));
      expect(base.copyWith(paused: true).reminder, base.reminder);
      expect(base.copyWith(retentionDays: 90).reminder, base.reminder);
      final changed =
          base.copyWith(reminder: const ScanReminderPrefs(enabled: false));
      expect(changed.reminder, const ScanReminderPrefs(enabled: false));
      expect(changed.retentionDays, 30);
    });

    test('equality distinguishes the reminder', () {
      const a = BodyScanSettings(reminder: ScanReminderPrefs(enabled: true));
      expect(a, const BodyScanSettings(reminder: ScanReminderPrefs(enabled: true)));
      expect(a == const BodyScanSettings(), isFalse);
      expect(a == const BodyScanSettings(reminder: ScanReminderPrefs(enabled: false)),
          isFalse);
    });
  });

  group('InMemoryBodyScanSettingsStore.setReminder', () {
    test('replays the latest value then streams the change', () async {
      final store = InMemoryBodyScanSettingsStore();
      final seen = <BodyScanSettings>[];
      final sub = store.watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.reminder, isNull);

      await store.setReminder(
          const ScanReminderPrefs(enabled: true, weekday: 4, minutes: 30));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.reminder,
          const ScanReminderPrefs(enabled: true, weekday: 4, minutes: 30));

      // A late subscriber sees the stored value immediately.
      expect((await store.watch().first).reminder?.weekday, 4);
      await sub.cancel();
    });

    test('does not disturb retention, paused or consent', () async {
      final store = InMemoryBodyScanSettingsStore();
      await store.setRetentionDays(90);
      await store.setPaused(true);
      await store.acceptCloudConsent(kBodyScanCloudConsentVersion);
      await store.setReminder(const ScanReminderPrefs(enabled: true));
      final s = await store.watch().first;
      expect(s.retentionDays, 90);
      expect(s.paused, isTrue);
      expect(s.hasCurrentConsent, isTrue);
      expect(s.reminder?.enabled, isTrue);
    });

    test('later setters keep the stored reminder', () async {
      final store = InMemoryBodyScanSettingsStore();
      await store.setReminder(
          const ScanReminderPrefs(enabled: true, weekday: 6, minutes: 100));
      await store.setPaused(true);
      await store.withdrawCloudConsent();
      await store.setRetentionDays(30);
      expect((await store.watch().first).reminder,
          const ScanReminderPrefs(enabled: true, weekday: 6, minutes: 100));
    });

    test('the written shape survives a Firestore-style JSON round trip',
        () async {
      final store = InMemoryBodyScanSettingsStore();
      await store.setReminder(
          const ScanReminderPrefs(enabled: false, weekday: 1, minutes: 0));
      final stored = (await store.watch().first).reminder!;
      final doc = {'schema': 1, 'reminder': stored.toJson()};
      expect(BodyScanSettings.fromJson(doc).reminder, stored);
    });
  });
}
