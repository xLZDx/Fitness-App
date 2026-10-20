// EP-J S04-38 release gate checks (DT-38-1, 38-2, 38-3, 38-4, 38-5, 38-6).
// Reads the real S04_RELEASE_CHECKLIST.md. Documents only: a READY status
// needs evidence, and today no row has any (so the release must read BLOCKED).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> kAllowed = <String>{'DRAFT', 'READY', 'NOT_RUN'};

String _doc() {
  final f = File('../docs/phase2/s04/S04_RELEASE_CHECKLIST.md');
  expect(f.existsSync(), isTrue, reason: 'the checklist must exist');
  return f.readAsStringSync();
}

/// Table rows of one section (text between `## <prefix>` and the next `## `):
/// each as the list of trimmed cells.
List<List<String>> _rows(String doc, String sectionPrefix) {
  final lines = doc.split(RegExp(r'\r?\n'));
  final out = <List<String>>[];
  var inSection = false;
  for (final l in lines) {
    if (l.startsWith('## ')) inSection = l.startsWith('## $sectionPrefix');
    if (!inSection || !l.startsWith('|')) continue;
    final parts = l.split('|');
    final cells =
        parts.sublist(1, parts.length - 1).map((c) => c.trim()).toList();
    if (cells.isEmpty || cells.first == '#' || cells.first.startsWith('---')) {
      continue;
    }
    out.add(cells);
  }
  return out;
}

String _statusWord(String cell) =>
    kAllowed.firstWhere((s) => cell.startsWith(s), orElse: () => '');

/// The status cell: column 6 in the 8-column table, second-to-last otherwise.
String _status(List<String> r) => r.length == 8 ? r[6] : r[r.length - 2];

void main() {
  late String doc;
  setUpAll(() => doc = _doc());

  group('DT-38-1 required rows have an owner and an allowed status', () {
    final required = <String, RegExp>{
      'privacy-policy': RegExp('privacy policy', caseSensitive: false),
      'data-safety-form': RegExp('data-safety form', caseSensitive: false),
      'foreground-service-declaration':
          RegExp('foreground-service declaration', caseSensitive: false),
      'in-app-disclosure-text':
          RegExp('in-app disclosure text', caseSensitive: false),
    };
    for (final e in required.entries) {
      test('/${e.key}', () {
        final hit = _rows(doc, '1.').where((r) => e.value.hasMatch(r[1])).toList();
        expect(hit, hasLength(1), reason: 'exactly one row for ${e.key}');
        final r = hit.single;
        expect(r, hasLength(8));
        expect(r[3], isNotEmpty, reason: 'drafted-by owner');
        expect(r[4], isNotEmpty, reason: 'checked-by owner');
        expect(r[5], isNotEmpty, reason: 'console owner');
        expect(_statusWord(r[6]), isNotEmpty,
            reason: 'status must be DRAFT, READY or NOT_RUN: ${r[6]}');
      });
    }
    test('every row of every table uses an allowed status word', () {
      for (final section in <String>['1.', '2.']) {
        final rows = _rows(doc, section);
        expect(rows, isNotEmpty);
        for (final r in rows) {
          expect(_statusWord(_status(r)), isNotEmpty,
              reason: 'row ${r.first}: "${_status(r)}" is not a known status');
        }
      }
    });
    test('the status vocabulary is stated in the document', () {
      expect(doc, contains('Allowed statuses: DRAFT, READY, NOT_RUN'));
    });
    test('a READY row must carry evidence (none is READY without it)', () {
      for (final section in <String>['1.', '2.']) {
        for (final r in _rows(doc, section)) {
          if (_statusWord(_status(r)) == 'READY') {
            expect(r.last.toLowerCase(), isNot(startsWith('none')),
                reason: 'row ${r.first} is READY with no evidence');
          }
        }
      }
    });
  });

  test('DT-38-2 the minors statement says private only, no sharing, no upload',
      () {
    final minors = _rows(doc, '2.')
        .where((r) => r[1].toLowerCase().startsWith('minors statement'))
        .toList();
    expect(minors, hasLength(1));
    final text = minors.single[2].toLowerCase();
    expect(text, contains('private'));
    expect(text, contains('no sharing'));
    expect(text, contains('no upload'));
  });

  test('DT-38-3 the server-enforcement row exists with a status field', () {
    final rows = _rows(doc, '2.')
        .where((r) =>
            r[1].contains('GPS-PRIV-050') && r[1].contains('GPS-PRIV-098'))
        .toList();
    expect(rows, hasLength(1));
    final st = _status(rows.single);
    expect(_statusWord(st), isNotEmpty);
    // Today it is UNKNOWN, so it must NOT read READY.
    expect(st, isNot(startsWith('READY')));
    expect(st, contains('UNKNOWN'));
  });

  test('DT-38-4 data-safety answers match: no upload, no sharing, no heart rate',
      () {
    final forms = _rows(doc, '1.')
        .where((r) => r[1].toLowerCase().contains('data-safety'))
        .toList();
    expect(forms, isNotEmpty);
    for (final r in forms) {
      final t = r[2].toLowerCase();
      expect(t, contains('no upload'));
      expect(t, contains('no sharing'));
      expect(t, contains('no heart rate'));
    }
    final cmp = _rows(doc, '2.')
        .where((r) => r[1].toLowerCase().contains('data-safety answers'))
        .toList();
    expect(cmp, hasLength(1));
    final t = cmp.single[2].toLowerCase();
    expect(t, contains('no upload'));
    expect(t, contains('no sharing'));
    expect(t, contains('no heart rate'));
  });

  group('DT-38-5 a not-ready row blocks the release, never marks it ready', () {
    test('some row is not READY', () {
      var notReady = 0;
      for (final section in <String>['1.', '2.']) {
        for (final r in _rows(doc, section)) {
          if (_statusWord(_status(r)) != 'READY') notReady++;
        }
      }
      expect(notReady, greaterThan(0));
    });
    test('the release state reads BLOCKED while any row is not READY', () {
      final i = doc.indexOf('## 4. Release state');
      expect(i, greaterThanOrEqualTo(0));
      final section = doc.substring(i, doc.indexOf('## 5.'));
      expect(section, contains('Current state: BLOCKED'));
      expect(section, isNot(contains('Current state: READY')));
    });
    test('the rule is written down', () {
      expect(doc, contains('the release is then recorded as BLOCKED'));
      expect(doc, contains('never as ready'));
    });
    test('the file makes no claim of a submission', () {
      expect(doc, contains('No statement in this file claims a submission'));
    });
  });

  test('DT-38-6 the five accepted risks are written down', () {
    final i = doc.indexOf('## 3. Accepted risks');
    expect(i, greaterThanOrEqualTo(0));
    final section = doc.substring(i, doc.indexOf('## 4.')).toLowerCase();
    for (final needle in <String>[
      'rooted or debuggable',
      'second app holding location permission',
      'notification-listener apps',
      'file sizes and modification times',
      'no aad binding',
    ]) {
      expect(section, contains(needle), reason: needle);
    }
  });
}
