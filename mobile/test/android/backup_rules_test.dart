import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Decision B: Android Auto Backup / device transfer must not carry the
// plaintext health profile, the legacy photo key or the secure-storage files,
// and must not carry the encrypted progress photos.
//
// This proves the CONFIGURATION FILES only. No device backup/restore was
// performed; the OS behaviour is not verified here.
//
// XML parsing: the `xml` package is not a dependency, so the files are read
// with a tolerant approach: strip XML comments with a regex, split into
// sections by tag name, and read `<exclude .../>` attributes with a regex.
//
// Paths are relative to the package root (`flutter test` cwd = mobile/).

const _expected = {
  'root|app_flutter/progress_photos',
  'sharedpref|FlutterSharedPreferences.xml',
  'sharedpref|FlutterSecureStorage.xml',
  'sharedpref|FlutterSecureKeyStorage.xml',
};

String _read(String path) => File(path).readAsStringSync();

String _stripComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Returns the exclusions (as `domain|path`) in the first `<tag>...</tag>`.
/// A duplicate entry is kept as a separate element so it is visible.
List<String> _excludes(String xml, String tag) {
  final clean = _stripComments(xml);
  final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(clean);
  expect(m, isNotNull, reason: 'missing <$tag> block');
  final out = <String>[];
  for (final e in RegExp(r'<exclude\b([^>]*?)/?>').allMatches(m!.group(1)!)) {
    final attrs = e.group(1)!;
    final domain = RegExp(r'domain="([^"]*)"').firstMatch(attrs)?.group(1);
    final path = RegExp(r'path="([^"]*)"').firstMatch(attrs)?.group(1);
    out.add('$domain|$path');
  }
  return out;
}

void _expectExactly(List<String> actual, String where) {
  expect(actual.length, _expected.length,
      reason: '$where has extra/duplicate/missing entries: $actual');
  expect(actual.toSet(), _expected, reason: where);
}

void main() {
  const res = 'android/app/src/main/res/xml';

  test('backup_rules.xml (API <= 30) excludes photos and sensitive prefs', () {
    final xml = _read('$res/backup_rules.xml');
    _expectExactly(_excludes(xml, 'full-backup-content'), 'full-backup-content');
  });

  test('data_extraction_rules.xml cloud-backup excludes the same four', () {
    final xml = _read('$res/data_extraction_rules.xml');
    _expectExactly(_excludes(xml, 'cloud-backup'), 'cloud-backup');
  });

  test('data_extraction_rules.xml device-transfer excludes the same four', () {
    final xml = _read('$res/data_extraction_rules.xml');
    _expectExactly(_excludes(xml, 'device-transfer'), 'device-transfer');
  });

  test('the parser helper sees a removed or mistyped exclusion', () {
    // Guards the instrument itself: a typo must not parse into the expected set.
    const typo = '<full-backup-content>'
        '<exclude domain="root" path="app_flutter/progress_photo" />'
        '</full-backup-content>';
    expect(_excludes(typo, 'full-backup-content').toSet(),
        isNot(_expected));
    const commented = '<full-backup-content><!-- <exclude domain="root" '
        'path="app_flutter/progress_photos" /> --></full-backup-content>';
    expect(_excludes(commented, 'full-backup-content'), isEmpty);
  });

  test('the excluded prefs file belongs to keys the app really stores there',
      () {
    // The sensitive profile keys live in SharedPreferences (plugin default
    // file on Android is FlutterSharedPreferences.xml, which the rules name).
    final store = _read('lib/features/profile/data/local_sensitive_store.dart');
    expect(store, contains("'profile.sensitive.\$uid'"));
    expect(store, contains("'profile.sensitive.corrupt.\$uid'"));
    expect(store, contains('SharedPreferences.getInstance()'));
    final wipe =
        _read('lib/features/account_deletion/data/local_data_wipe.dart');
    expect(wipe, contains("'profile.sensitive.\$uid'"));
  });

  test('pubspec.lock pins the plugins whose file names the rules rely on', () {
    // The names FlutterSharedPreferences.xml / FlutterSecureStorage.xml /
    // FlutterSecureKeyStorage.xml are plugin implementation details. When one
    // of these versions changes, this test fails on purpose so a human
    // re-checks the on-device file names against the exclusion lists.
    final lock = _read('pubspec.lock');
    String versionOf(String pkg) {
      final m = RegExp('^  $pkg:\\n(?:    .*\\n)*?    version: "([^"]+)"',
              multiLine: true)
          .firstMatch(lock);
      expect(m, isNotNull, reason: '$pkg missing from pubspec.lock');
      return m!.group(1)!;
    }

    expect(versionOf('shared_preferences'), '2.5.3');
    expect(versionOf('flutter_secure_storage'), '10.3.1');
  });

  test('AndroidManifest.xml wires both rule files', () {
    final m = _read('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(m,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('no manifest overrides the backup attributes or disables backup', () {
    // Found today: only the main manifest sets the two attributes; debug and
    // profile manifests only add INTERNET; nobody sets allowBackup.
    for (final flavor in ['main', 'debug', 'profile']) {
      final raw = _read('android/app/src/$flavor/AndroidManifest.xml');
      final m = _stripComments(raw);
      expect(m.contains('tools:replace'), isFalse, reason: flavor);
      expect(m.contains('allowBackup'), isFalse, reason: flavor);
      if (flavor != 'main') {
        expect(m.contains('fullBackupContent'), isFalse, reason: flavor);
        expect(m.contains('dataExtractionRules'), isFalse, reason: flavor);
      }
    }
  });

  test('the data inventory documents the exclusion', () {
    final inv = _read('../core/DATA_INVENTORY_2026-08-11.md');
    expect(inv, contains('FlutterSharedPreferences.xml'));
    expect(inv, contains('FlutterSecureStorage.xml'));
    expect(inv, contains('FlutterSecureKeyStorage.xml'));
    expect(inv, contains('backup_rules.xml'));
    expect(inv, contains('data_extraction_rules.xml'));
  });
}
