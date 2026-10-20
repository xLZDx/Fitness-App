// EP-F S04-23 battery protocol document (DT-23-1, DT-23-2). Reads the real
// document from the repository; the record validator below is the test's own
// reference implementation of the rule "a run record is accepted only when
// every required field is present and non-empty" (no production validator
// exists yet: the document is the only artifact, see the findings file).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The required field names of test plan section 5.3 (exact).
const List<String> kRequiredFields = <String>[
  'device_model',
  'android_version',
  'build_head',
  'run_type',
  'duration_min',
  'screen_off',
  'carry',
  'no_charger',
  'battery_start_percent',
  'battery_end_percent',
  'charge_counter_start',
  'charge_counter_end',
  'control_run',
  'temperature',
  'network_state',
  'recorder_settings',
  'counters',
  'percent_per_hour',
  'target',
  'status',
  'oem_kill_entry',
];

const Set<String> kStatuses = <String>{'PASS', 'FAIL', 'NOT_RUN'};

/// Accepts a record only when every required field is present and non-empty,
/// the status is one of the three allowed words, and PASS carries an artifact.
bool recordAccepted(Map<String, String> record) {
  for (final f in kRequiredFields) {
    final v = record[f];
    if (v == null || v.trim().isEmpty) return false;
  }
  if (!kStatuses.contains(record['status'])) return false;
  if (record['status'] == 'PASS' && (record['artifact'] ?? '').trim().isEmpty) {
    return false;
  }
  return true;
}

Map<String, String> fullRecord() => <String, String>{
      for (final f in kRequiredFields) f: 'x',
      'status': 'FAIL',
      'percent_per_hour': '9.5',
      'target': '8',
    };

File docFile(String name) {
  // `flutter test` runs with the package root (mobile/) as the cwd.
  final candidates = <String>[
    '../docs/phase2/s04/$name',
    'docs/phase2/s04/$name',
    '../../docs/phase2/s04/$name',
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f;
  }
  fail('document $name not found from ${Directory.current.path}');
}

void main() {
  late String doc;
  setUpAll(() => doc = docFile('S04_BATTERY_PROTOCOL.md').readAsStringSync());

  group('DT-23-1 the protocol contains each required field name', () {
    for (final f in kRequiredFields) {
      test('field `$f` is in the section 7 table', () {
        expect(doc.contains('| `$f` |'), isTrue,
            reason: 'section 7 of the protocol must define `$f`');
      });
    }

    test('the field table has exactly the required names, no extra field', () {
      final section = doc.substring(doc.indexOf('## 7. Required fields'));
      final end = section.indexOf('\n## 8.');
      final table = end < 0 ? section : section.substring(0, end);
      final names = RegExp(r'^\| `([a-z_]+)` \|', multiLine: true)
          .allMatches(table)
          .map((m) => m.group(1)!)
          .toList();
      expect(names, kRequiredFields);
    });

    test('every result field is an empty template: no PASS is claimed', () {
      expect(doc.contains('NOT_RUN'), isTrue);
      expect(RegExp(r'\|\s*`status`\s*\|[^|]*\|\s*NOT_RUN\s*\|').hasMatch(doc),
          isTrue,
          reason: 'status must read NOT_RUN while no run exists');
      expect(doc.contains('| `percent_per_hour` | computed result | empty |'),
          isTrue);
    });

    test('rules: no charger and no USB, control run, artifact for PASS', () {
      expect(doc, contains('No charger and no USB'));
      expect(doc, contains('Control run'));
      expect(doc, contains('PASS needs a linked artifact'));
      expect(doc, contains('8 percent'));
    });

    test('the reference phone and its caveats are recorded', () {
      expect(doc, contains('Samsung Galaxy S8'));
      expect(doc, contains('UNKNOWN'));
    });
  });

  group('DT-23-2 the record validator', () {
    test('/complete-record-accepted', () {
      expect(recordAccepted(fullRecord()), isTrue);
    });

    test('a PASS without an artifact is rejected, with one it is accepted', () {
      final r = fullRecord()..['status'] = 'PASS';
      expect(recordAccepted(r), isFalse);
      r['artifact'] = 'screenshot-2026-10-17.png';
      expect(recordAccepted(r), isTrue);
    });

    test('an unknown status word is rejected', () {
      expect(recordAccepted(fullRecord()..['status'] = 'OK'), isFalse);
    });

    for (final f in kRequiredFields) {
      test('/record-missing-a-field-rejected: `$f` removed', () {
        final r = fullRecord()..remove(f);
        expect(recordAccepted(r), isFalse);
      });
      test('/record-empty-field-rejected: `$f` blank', () {
        final r = fullRecord()..[f] = '   ';
        expect(recordAccepted(r), isFalse);
      });
    }
  });
}
