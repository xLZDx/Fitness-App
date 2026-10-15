// C14: retention, paused and cloud-consent parts of body_scan_settings (the
// reminder part lives in body_scan_settings_test.dart). Tolerant reads decide
// whether a photo may ever leave the device, so they are tested to the edge.
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';

void main() {
  test('constants', () {
    expect(kRetentionChoices, [0, 30, 90, 365]);
    expect(kBodyScanCloudConsentVersion, 1);
  });

  group('fromJson is tolerant', () {
    test('non-map and empty documents are the defaults (no consent)', () {
      for (final raw in <Object?>[null, 'x', 5, <Object?>[], <String, Object?>{}]) {
        final s = BodyScanSettings.fromJson(raw);
        expect(s.retentionDays, 0, reason: '$raw');
        expect(s.cloudConsentVersion, isNull);
        expect(s.hasCurrentConsent, isFalse);
        expect(s.paused, isFalse);
        expect(s.reminder, isNull);
      }
    });

    test('only the allowed retention values are accepted', () {
      for (final d in kRetentionChoices) {
        expect(BodyScanSettings.fromJson({'retentionDays': d}).retentionDays, d);
      }
      for (final bad in <Object?>[1, 31, -30, 366, '30', 30.5, null]) {
        expect(BodyScanSettings.fromJson({'retentionDays': bad}).retentionDays, 0,
            reason: '$bad');
      }
    });

    test('consent needs a map with an int version >= 1', () {
      expect(
          BodyScanSettings.fromJson({
            'cloudConsent': {'version': 1}
          }).cloudConsentVersion,
          1);
      for (final bad in <Object?>[
        {'version': 0},
        {'version': -1},
        {'version': '1'},
        {'version': 1.0},
        {'version': null},
        <String, Object?>{},
        'yes',
        true,
      ]) {
        final s = BodyScanSettings.fromJson({'cloudConsent': bad});
        expect(s.cloudConsentVersion, isNull, reason: '$bad');
        expect(s.hasCurrentConsent, isFalse, reason: '$bad');
      }
    });

    test('paused is true only for the boolean true', () {
      expect(BodyScanSettings.fromJson({'paused': true}).paused, isTrue);
      for (final bad in <Object?>['true', 1, null, false]) {
        expect(BodyScanSettings.fromJson({'paused': bad}).paused, isFalse);
      }
    });
  });

  group('hasCurrentConsent', () {
    test('null, and older versions, are not consent; the current and newer are',
        () {
      expect(const BodyScanSettings().hasCurrentConsent, isFalse);
      expect(const BodyScanSettings(cloudConsentVersion: 0).hasCurrentConsent,
          isFalse);
      expect(
          BodyScanSettings(cloudConsentVersion: kBodyScanCloudConsentVersion)
              .hasCurrentConsent,
          isTrue);
      expect(
          BodyScanSettings(cloudConsentVersion: kBodyScanCloudConsentVersion + 1)
              .hasCurrentConsent,
          isTrue);
    });
  });

  group('copyWith and equality', () {
    test('copyWith keeps untouched fields and clearConsent removes consent', () {
      const base = BodyScanSettings(
          retentionDays: 30, cloudConsentVersion: 1, paused: true);
      expect(base.copyWith(retentionDays: 90).cloudConsentVersion, 1);
      expect(base.copyWith(paused: false).retentionDays, 30);
      final cleared = base.copyWith(clearConsent: true);
      expect(cleared.cloudConsentVersion, isNull);
      expect(cleared.retentionDays, 30);
      expect(cleared.paused, isTrue);
      expect(base.copyWith(), base);
    });

    test('equality and hashCode cover every field', () {
      const a = BodyScanSettings(retentionDays: 30, cloudConsentVersion: 1);
      expect(a, const BodyScanSettings(retentionDays: 30, cloudConsentVersion: 1));
      expect(a.hashCode,
          const BodyScanSettings(retentionDays: 30, cloudConsentVersion: 1).hashCode);
      expect(a == const BodyScanSettings(retentionDays: 90, cloudConsentVersion: 1), isFalse);
      expect(a == const BodyScanSettings(retentionDays: 30), isFalse);
      expect(a == a.copyWith(paused: true), isFalse);
      expect(a == a.copyWith(reminder: const ScanReminderPrefs(enabled: true)), isFalse);
    });
  });

  group('InMemoryBodyScanSettingsStore', () {
    test('starts from the initial value and replays it', () async {
      final s = InMemoryBodyScanSettingsStore(const BodyScanSettings(retentionDays: 365));
      expect((await s.watch().first).retentionDays, 365);
    });

    test('an invalid retention is refused and changes nothing', () async {
      final s = InMemoryBodyScanSettingsStore();
      await expectLater(s.setRetentionDays(7), throwsArgumentError);
      expect((await s.watch().first).retentionDays, 0);
      await s.setRetentionDays(30);
      expect((await s.watch().first).retentionDays, 30);
    });

    test('accept then withdraw consent', () async {
      final s = InMemoryBodyScanSettingsStore();
      expect((await s.watch().first).hasCurrentConsent, isFalse);
      await s.acceptCloudConsent(1);
      expect((await s.watch().first).hasCurrentConsent, isTrue);
      await s.withdrawCloudConsent();
      final after = await s.watch().first;
      expect(after.cloudConsentVersion, isNull);
      expect(after.hasCurrentConsent, isFalse);
    });

    test('watchers are notified of every change in order', () async {
      final s = InMemoryBodyScanSettingsStore();
      final seen = <BodyScanSettings>[];
      final sub = s.watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await s.setPaused(true);
      await s.setRetentionDays(90);
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((e) => [e.paused, e.retentionDays]),
          [[false, 0], [true, 0], [true, 90]]);
      await sub.cancel();
    });
  });
}
