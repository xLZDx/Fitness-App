// S04-27 / S04-28 (DT-27-3, DT-27-4, DT-27-5, DT-28-1, DT-28-2, DT-28-4,
// DT-28-5, DT-28-6, DT-28-7, DT-28-8, DT-21-6): recording defaults, the
// consent text version tie to the ARB files, and source scans of
// `lib/features/recording/**`. The scans fail when a new violating line is
// added; they were checked against the real corpus (non-empty file set).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart'
    show kGpsRecorderBuild;
import 'package:fitness_app/features/workouts/state/active_session_status.dart'
    show gpsRecorderEnabledProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

Directory get _recDir => Directory('lib/features/recording');

List<File> _recordingFiles() => _recDir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Source with `//` comments removed line by line (string literals containing
/// `//` are rare in this folder; a false removal can only hide, and the
/// corpus-size assertion keeps the scan honest).
String _code(File f) => f
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('scan corpus sanity', () {
    test('the recording folder is found and non-trivial', () {
      expect(_recDir.existsSync(), isTrue);
      expect(_recordingFiles().length, greaterThan(40));
    });
  });

  group('DT-27-3 no raw logging in recording/**', () {
    test('no print, debugPrint, developer.log or stdout/stderr writes', () {
      final hits = <String>[];
      final re = RegExp(
          r'(^|[^A-Za-z_.])(print|debugPrint|debugPrintStack)\s*\(|developer\.log\s*\(|\bstdout\.|\bstderr\.|\bdebugger\s*\(');
      for (final f in _recordingFiles()) {
        final code = _code(f);
        for (final m in re.allMatches(code)) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('logRecorderError / logRecorderEvent scopes are fixed literals '
        '(no interpolation) everywhere in lib', () {
      final hits = <String>[];
      final re = RegExp(r'logRecorder(Error|Event)\s*\(\s*([^,)]*)');
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.replaceAll('\\', '/').endsWith('l10n/recording_log.dart')) {
          continue;
        }
        for (final m in re.allMatches(_code(f))) {
          final arg = m.group(2)!.trim();
          final literal = RegExp(r"^'[A-Za-z0-9_.]+'$").hasMatch(arg);
          if (!literal) hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('logRecorderEvent event words are fixed literals', () {
      final hits = <String>[];
      final re = RegExp(r'logRecorderEvent\s*\(\s*[^,]*,\s*([^)]*)\)');
      for (final f in _recordingFiles()) {
        if (f.path.replaceAll(r'\', '/').endsWith('l10n/recording_log.dart')) {
          continue;
        }
        for (final m in re.allMatches(_code(f))) {
          if (!RegExp(r"^'[A-Za-z0-9_.]+'$").hasMatch(m.group(1)!.trim())) {
            hits.add('${f.path}: ${m.group(0)}');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no catch block interpolates the caught error or its message into a '
        'string', () {
      final hits = <String>[];
      // `catch (e)` followed within the same block by "$e" / "${e" / e.message.
      final re = RegExp(
          r'''catch\s*\(\s*(\w+)[^)]*\)\s*\{([^}]*)\}''',
          multiLine: true);
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          final v = m.group(1)!;
          final body = m.group(2)!;
          if (RegExp('\\\$$v\\b|\\\$\\{\\s*$v\\b|\\b$v\\.(message|toString)')
              .hasMatch(body)) {
            hits.add('${f.path}: ${m.group(0)!.split('\n').first}');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no string interpolation of latitude / longitude / position fields '
        'outside the pure formatters', () {
      final hits = <String>[];
      final re = RegExp(
          r'''['"][^'"\n]*\$\{?(\w+\.)*(lat|lon|lng|latitude|longitude)\b[^'"\n]*['"]''');
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('DT-27-4 no crash reporter in recording/**', () {
    test('no Crashlytics / Sentry / recordError reference', () {
      final hits = <String>[];
      final re = RegExp(
          r'Crashlytics|Sentry|recordFlutterError|recordError\s*\(|FirebasePerformance|FirebaseAnalytics|\.logEvent\s*\(',
          caseSensitive: false);
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('DT-28-1 defaults are off', () {
    test('/recorder-flag-default-off', () {
      expect(kGpsRecorderBuild, isFalse,
          reason: 'GPS_RECORDER is a --dart-define, absent in the test run');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(gpsRecorderEnabledProvider), isFalse);
    });

    test('/cloud-streams-default-false: upload constant and heart rate off',
        () {
      expect(kGpsUploadEnabled, isFalse);
      expect(kRecorderRecordsHeartRate, isFalse);
    });
  });

  group('DT-28-2 / DT-28-4 import graph and forbidden symbols', () {
    test('recording/** imports no uploader, sync repository or tombstone '
        'pusher', () {
      final hits = <String>[];
      final re = RegExp(
          r'''import\s+['"][^'"]*(uploader|sync_repository|sync_resolution|tombstone|cloud_functions|dio|http|firebase_storage|cloud_firestore)[^'"]*['"]''',
          caseSensitive: false);
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('recording/** opens no network client', () {
      final hits = <String>[];
      final re =
          RegExp(r'HttpClient\s*\(|http\.(get|post|put)\s*\(|Socket\.connect|WebSocket\.connect');
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no heart-rate or BLE symbol in recording/**', () {
      final hits = <String>[];
      final re = RegExp(
          r'heart[_ ]?rate|\bhr[A-Z_]\w*|\bbpm\b|bluetooth|flutter_blue|\bBLE\b|\bble[A-Z_]\w*|gatt',
          caseSensitive: false);
      for (final f in _recordingFiles()) {
        for (final m in re.allMatches(_code(f))) {
          final s = m.group(0)!;
          // `kRecorderRecordsHeartRate` lives in core/config, not here.
          hits.add('${f.path}: $s');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('DT-28-6 constants', () {
    test('/privacy-zone-200m-and-key', () {
      expect(kDefaultPrivacyZoneRadiusM, 200);
      expect(kPrivacyZoneSettingKey, 'settings.privacyZone');
    });

    test('/expiry-24-months-from-activity-date-and-key', () {
      expect(kDefaultGpsExpiryMonths, 24);
      expect(kGpsConsentSettingKey, 'settings.gpsConsent');
    });
  });

  group('DT-28-7 no application of the privacy-zone / expiry defaults', () {
    test('/no-application: nothing outside recording_defaults.dart reads them',
        () {
      final names = [
        'kDefaultPrivacyZoneRadiusM',
        'kDefaultGpsExpiryMonths',
      ];
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.replaceAll('\\', '/').endsWith('config/recording_defaults.dart')) {
          continue;
        }
        final code = _code(f);
        for (final n in names) {
          if (code.contains(n)) hits.add('${f.path}: $n');
        }
      }
      expect(hits, isEmpty,
          reason: 'S04 applies neither the privacy zone nor expiry:\n'
              '${hits.join('\n')}');
    });

    test('/no-scheduler: no expiry or retention rule in recording/**', () {
      final hits = <String>[];
      final re = RegExp(
          r'expir|retention|ttl\b|Timer\.periodic\([^)]*(days|hours)|purgeOlder|deleteOlder',
          caseSensitive: false);
      for (final f in _recordingFiles()) {
        // kRecordingExpiryMs is the 30-day sweep of quarantined local
        // recordings, not an upload expiry (S04-R-049).
        final code = _code(f).replaceAll('kRecordingExpiryMs', '');
        for (final m in re.allMatches(code)) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('DT-28-8 no unproved iOS claim', () {
    test('the release checklist and findings docs state no iOS pass', () {
      final hits = <String>[];
      final re = RegExp(r'ios[^\n|]{0,60}\b(pass|passed|verified|tested)\b',
          caseSensitive: false);
      for (final p in [
        '../docs/phase2/s04/S04_RELEASE_CHECKLIST.md',
        '../docs/phase2/s04/S04_DEVICE_LAB_RECORD.md',
      ]) {
        final f = File(p);
        if (!f.existsSync()) continue;
        for (final line in f.readAsLinesSync()) {
          // A line saying "no iOS ... pass" / "NOT_RUN" is the honest form.
          if (re.hasMatch(line) &&
              !RegExp(r'\bno\b|not|NOT_RUN', caseSensitive: false)
                  .hasMatch(line)) {
            hits.add('$p: $line');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('DT-21-6 consent text version equals the ARB version', () {
    for (final name in ['app_en.arb', 'app_ru.arb']) {
      test('gpsConsentTextVersion in $name equals the constant', () {
        expect(_arb(name)['gpsConsentTextVersion'], kLocationConsentTextVersion);
      });
    }

    test('/draft-marker: the wording keys are flagged DRAFT in the en ARB', () {
      final en = _arb('app_en.arb');
      for (final k in ['gpsPrivacyLine', 'gpsPrePromptReason']) {
        final meta = en['@$k'] as Map<String, dynamic>;
        expect(meta['description'], contains('DRAFT'), reason: k);
        expect(en[k], isA<String>());
        expect((en[k] as String).trim(), isNotEmpty);
      }
    });

    test('the DRAFT wording exists in ru as well', () {
      final ru = _arb('app_ru.arb');
      for (final k in ['gpsPrivacyLine', 'gpsPrePromptReason', 'gpsPrePromptPrecise']) {
        expect((ru[k] as String?)?.trim(), isNotEmpty, reason: k);
      }
    });

    test('the privacy line says where it is stored and who sees it '
        '(DT-17-2 content half)', () {
      final en = (_arb('app_en.arb')['gpsPrivacyLine'] as String).toLowerCase();
      expect(en, contains('phone'));
      expect(en, contains('only you'));
    });
  });

  group('DT-28-5 saved-on-device notice', () {
    test('the ARB key named by the constant exists in en and ru', () {
      expect(kSavedOnDeviceStringKey, 'gpsSavedOnDevice');
      for (final name in ['app_en.arb', 'app_ru.arb']) {
        final v = _arb(name)[kSavedOnDeviceStringKey];
        expect(v, isA<String>(), reason: name);
        expect((v as String).trim(), isNotEmpty);
      }
    });

    test('the en notice states it is not shared', () {
      expect((_arb('app_en.arb')[kSavedOnDeviceStringKey] as String).toLowerCase(),
          contains('not shared'));
    });
  });

  group('DT-27-5 user-facing gps strings cannot carry a coordinate', () {
    test('no gps* placeholder is named like a coordinate, and no gps string '
        'is a coordinate-typed placeholder', () {
      final hits = <String>[];
      final coordLike = RegExp(r'lat|lon|lng|coord|position|location\b|geohash',
          caseSensitive: false);
      for (final name in ['app_en.arb', 'app_ru.arb']) {
        final arb = _arb(name);
        for (final e in arb.entries) {
          if (!e.key.startsWith('@gps')) continue;
          final meta = e.value;
          if (meta is! Map) continue;
          final ph = meta['placeholders'];
          if (ph is! Map) continue;
          for (final p in ph.keys) {
            if (coordLike.hasMatch(p as String)) hits.add('$name ${e.key}.$p');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('literal text of gps strings contains no coordinate-shaped number',
        () {
      final hits = <String>[];
      final coord = RegExp(r'-?\d{1,3}[.,]\d{4,}');
      for (final name in ['app_en.arb', 'app_ru.arb']) {
        for (final e in _arb(name).entries) {
          if (e.key.startsWith('gps') && e.value is String) {
            if (coord.hasMatch(e.value as String)) hits.add('$name ${e.key}');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('every gps* key of en exists in ru (no silent fallback of consent '
        'wording)', () {
      final en = _arb('app_en.arb');
      final ru = _arb('app_ru.arb');
      final missing = [
        for (final k in en.keys)
          if (k.startsWith('gps') && !k.startsWith('@') && !ru.containsKey(k)) k
      ];
      expect(missing, isEmpty, reason: missing.join(', '));
    });
  });
}
