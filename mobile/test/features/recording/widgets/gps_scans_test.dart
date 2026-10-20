// EP-G source scans over the real lib files (DT-25-1, DT-25-2, DT-25-14) plus
// the gps_format helpers the screens depend on. Scans read the repository;
// they would fail if a file were added, copied or changed in the scanned way.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/widgets/gps_format.dart';

/// DT-25-1: every screen or surface file under the recording UI folders maps
/// to surfaces of the S04-D contract (S4-1 .. S4-7, S4-11). A new file must be
/// added here on purpose.
const Map<String, List<String>> kSurfaceRegistry = <String, List<String>>{
  'lib/features/recording/pages/gps_recording_page.dart': <String>[
    'S4-1', 'S4-2', 'S4-3', 'S4-4', 'S4-5', 'S4-6'
  ],
  'lib/features/recording/pages/gps_outcome_views.dart': <String>[
    'S4-3', 'S4-4', 'S4-5', 'S4-6'
  ],
  'lib/features/recording/widgets/gps_start_panels.dart': <String>['S4-1'],
  'lib/features/recording/widgets/gps_start_flow.dart': <String>['S4-1'],
  'lib/features/recording/widgets/gps_live_widgets.dart': <String>['S4-2'],
  'lib/features/recording/widgets/gps_common_widgets.dart': <String>[
    'S4-1', 'S4-2', 'S4-3', 'S4-4', 'S4-5', 'S4-6'
  ],
  'lib/features/recording/widgets/gps_consent_row.dart': <String>['S4-11'],
  'lib/features/recording/widgets/gps_format.dart': <String>[
    'S4-2', 'S4-4'
  ],
};

List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) throw StateError('$dir must exist');
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

String _norm(String p) => p.replaceAll('\\', '/');

/// Source text with line and block comments removed (so words in docs do not
/// count as code).
String _code(File f) {
  var s = f.readAsStringSync();
  s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return s
      .split(RegExp(r'\r?\n'))
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  group('DT-25-1 file-to-surface registry', () {
    final files = <File>[
      ..._dartFiles('lib/features/recording/pages'),
      ..._dartFiles('lib/features/recording/widgets'),
    ].map((f) => _norm(f.path)).toList();

    test('every screen or widget file is registered', () {
      final unmapped =
          files.where((p) => !kSurfaceRegistry.containsKey(p)).toList();
      expect(unmapped, isEmpty,
          reason: 'unmapped screen files: $unmapped');
    });
    test('every registered file exists', () {
      for (final p in kSurfaceRegistry.keys) {
        expect(File(p).existsSync(), isTrue, reason: p);
      }
    });
    test('only known surfaces are named and S4-1..S4-6 and S4-11 are covered',
        () {
      const known = <String>{
        'S4-1', 'S4-2', 'S4-3', 'S4-4', 'S4-5', 'S4-6', 'S4-7', 'S4-11'
      };
      final seen = <String>{};
      for (final s in kSurfaceRegistry.values) {
        for (final id in s) {
          expect(known, contains(id));
          seen.add(id);
        }
      }
      expect(seen,
          containsAll(<String>['S4-1', 'S4-2', 'S4-3', 'S4-4', 'S4-5', 'S4-6', 'S4-11']));
    });
    test('the pages folder holds one pushed page file for S4-1..S4-6', () {
      final page = File('lib/features/recording/pages/gps_recording_page.dart')
          .readAsStringSync();
      expect(page, contains('class GpsRecordingPage'));
      // One route for all six surfaces: the doc line names /record/gps.
      expect(page, contains('/record/gps'));
    });
  });

  group('DT-25-2 no duplicated shell tab list, back rule or sheet flag', () {
    final recordingFiles = <File>[
      ..._dartFiles('lib/features/recording'),
    ];
    test('no recording file lists the tab paths itself', () {
      for (final f in recordingFiles) {
        final code = _code(f);
        final hits = <String>['/workouts', '/progress', '/profile', '/scan']
            .where(code.contains)
            .toList();
        expect(hits.length < 2, isTrue,
            reason: '${f.path} repeats the tab paths: $hits');
      }
    });
    test('no recording file keeps its own record-sheet open flag', () {
      for (final f in recordingFiles) {
        final code = _code(f);
        expect(code.contains('_recordOpen'), isFalse, reason: f.path);
        expect(code.contains('recordSheetOpen'), isFalse, reason: f.path);
      }
    });
    test('the shell destination list exists exactly once', () {
      final decl = <String>[];
      for (final f in _dartFiles('lib')) {
        if (_code(f).contains('const List<ShellDestination> kShellDestinations') ||
            RegExp(r'(final|const)\s+List<ShellDestination>\s+kShellDestinations')
                .hasMatch(_code(f))) {
          decl.add(_norm(f.path));
        }
      }
      expect(decl, <String>['lib/shared/widgets/shell_destinations.dart']);
    });
    test('the GPS route is registered in the one S04 route file', () {
      final routes = File('lib/core/router/s04_routes.dart').readAsStringSync();
      expect(routes, contains('/record/gps'));
    });
  });

  group('DT-25-14 no repeating controllers and no indeterminate indicators',
      () {
    final scanned = <File>[
      ..._dartFiles('lib/features/recording/pages'),
      ..._dartFiles('lib/features/recording/widgets'),
      File('lib/features/modes/widgets/record_sheet.dart'),
      File('lib/features/workouts/state/active_session_status.dart'),
    ];
    final banned = <String, RegExp>{
      'AnimationController': RegExp(r'AnimationController'),
      'repeat()': RegExp(r'\.repeat\('),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'LinearProgressIndicator': RegExp(r'LinearProgressIndicator'),
      'RefreshProgressIndicator': RegExp(r'RefreshProgressIndicator'),
      'CupertinoActivityIndicator': RegExp(r'CupertinoActivityIndicator'),
      'Ticker': RegExp(r'\bTickerProvider\b|\bSingleTickerProviderStateMixin\b'),
      'RotationTransition': RegExp(r'RotationTransition|FadeTransition|ScaleTransition'),
    };
    for (final e in banned.entries) {
      test('zero matches for ${e.key}', () {
        final hits = <String>[];
        for (final f in scanned) {
          expect(f.existsSync(), isTrue, reason: f.path);
          if (e.value.hasMatch(_code(f))) hits.add(_norm(f.path));
        }
        expect(hits, isEmpty, reason: '${e.key} found in $hits');
      });
    }
    test('the scan set is not empty (a vacuous scan would pass)', () {
      expect(scanned.length, greaterThan(8));
    });
    test('the scan really detects a banned token (positive control)', () {
      expect(banned['AnimationController']!.hasMatch('final c = AnimationController(vsync: v);'),
          isTrue);
      expect(banned['repeat()']!.hasMatch('c.repeat(reverse: true);'), isTrue);
    });
  });

  group('gps_format helpers', () {
    test('duration: m:ss under an hour, h:mm:ss after, never negative', () {
      expect(gpsFormatDuration(0), '0:00');
      expect(gpsFormatDuration(59999), '0:59');
      expect(gpsFormatDuration(60000), '1:00');
      expect(gpsFormatDuration(3599000), '59:59');
      expect(gpsFormatDuration(3600000), '1:00:00');
      expect(gpsFormatDuration(3661000), '1:01:01');
      expect(gpsFormatDuration(-5000), '0:00');
    });
    test('distance is a string with a unit', () {
      expect(gpsFormatDistance(0), isNotEmpty);
      expect(gpsFormatDistance(1234), contains('1'));
      expect(gpsFormatDistance(1234).length, greaterThan(2));
    });
    test('pace and speed are null when unknown, text when known', () {
      expect(gpsFormatPace(null), isNull);
      expect(gpsFormatSpeed(null), isNull);
      expect(gpsFormatPace(330), isNotNull);
      expect(gpsFormatPace(330), contains('5'));
      expect(gpsFormatSpeed(2.5), isNotNull);
    });
    test('clock is two digits per field', () {
      expect(gpsFormatClock(DateTime(2026, 10, 17, 7, 5)), contains('07'));
      expect(gpsFormatClock(DateTime(2026, 10, 17, 7, 5)), contains('05'));
    });
    test('running and cycling choose pace or speed by sport', () {
      expect(gpsUsesSpeed(SportType.running), isFalse);
      expect(gpsUsesSpeed(SportType.cycling), isTrue);
      expect(gpsUsesSpeed(null), isFalse);
    });
    test('stop reason line: user and none have no line; others are named',
        () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(gpsStopReasonLine(l10n, null), isNull);
      expect(gpsStopReasonLine(l10n, StopReason.user), isNull);
      for (final r in StopReason.values) {
        if (r == StopReason.user) continue;
        final line = gpsStopReasonLine(l10n, r);
        expect(line, isNotNull, reason: '$r');
        expect(line, isNotEmpty);
      }
      expect(gpsStopReasonLine(l10n, StopReason.consentWithdrawn),
          l10n.gpsReasonConsent);
      expect(gpsStopReasonLine(l10n, StopReason.account), l10n.gpsReasonAccount);
    });
    test('spoken duration and distance are words, not clock digits', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final d = gpsSpokenDuration(l10n, 3661000);
      expect(d, isNot(contains(':')));
      expect(d, isNotEmpty);
      expect(gpsSpokenDistance(l10n, 1500), isNotEmpty);
    });
  });
}
