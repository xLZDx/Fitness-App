// S02 test epic 10b: remediation D, the Dart mirror of the `primarySourceId`
// rule (test/support/firestore_rules_parser.dart `rulesViolations`) against the
// two deployed sides, on one value table. Oracle:
// docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md (rules mirror bullet).
//
// The TypeScript patterns below are copied LITERALLY from
// functions/src/activity_streams/schema.ts:
//   line 128: sourceId: { maxLength: 64, pattern: /^[A-Za-z0-9._:-]{1,64}$/ }
//   line 168: export const COORDINATE_LIKE = /\d\.\d{2,}|\d\s*,\s*-?\d/;
// A guard test re-reads that file, so a change on the TypeScript side fails here
// instead of silently drifting. The firestore.rules side is parsed from the
// real file (actLabelsOk, lines ~940 to 944).
import 'package:flutter_test/flutter_test.dart';

import '../../../support/firestore_rules_parser.dart';
import '../../../support/s02_paths.dart';

// functions/src/activity_streams/schema.ts:128 (pattern) and :168.
final _tsSourceId = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');
final _tsCoordinateLike = RegExp(r'\d\.\d{2,}|\d\s*,\s*-?\d');

bool _tsAccepts(String v) =>
    v.length <= 64 && _tsSourceId.hasMatch(v) && !_tsCoordinateLike.hasMatch(v);

/// firestore.rules `matches()` must match the whole string.
bool _rulesAccepts(List<String> patterns, List<String> denials, String v) {
  bool full(String p) => RegExp('^(?:$p)\$').hasMatch(v);
  return patterns.every(full) && !denials.any(full);
}

/// Pulls the two `primarySourceId.matches('...')` literals out of
/// `firestore.rules`: the first is the allow pattern, the second the denial.
({List<String> allow, List<String> deny}) _rulesPatterns() {
  final src = readRulesText();
  final at = src.indexOf('function actLabelsOk');
  expect(at, greaterThan(0), reason: 'actLabelsOk not found');
  final block = src.substring(at, at + 600);
  final found = [
    for (final m in RegExp(r"primarySourceId\.matches\('([^']+)'\)")
        .allMatches(block))
      m.group(1)!,
  ];
  expect(found, hasLength(2), reason: 'allow and deny literals expected');
  return (allow: [found[0]], deny: [found[1]]);
}

List<String> _mirrorViolations(Object? id) => [
      for (final v in rulesViolations(parseActivityRules(), {
        'primarySourceId': id,
        'sport': 'running',
      }))
        if (v.contains('primarySourceId')) v,
    ];

void main() {
  // (value, accepted, why). Strings only for the three-way table.
  final strings = <(String, bool, String)>[
    ('health.connect:abc-1_2', true, 'the notes\' accepted example'),
    ('app', true, 'plain id'),
    ('a', true, 'one character'),
    ('A' * 64, true, 'exactly 64 characters'),
    ('A' * 65, false, 'over 64 characters'),
    ('', false, 'empty'),
    ('a b', false, 'space'),
    ('a/b', false, 'slash'),
    ('a,b', false, 'comma is outside the class'),
    ('café', false, 'non-ASCII'),
    ('abc\n', false, 'trailing newline'),
    ('51.5007', false, 'coordinate-like: latitude'),
    ('x-0.1276', false, 'coordinate-like: longitude with prefix'),
    ('173.25', false, 'coordinate-like: two decimals'),
    ('v1.25', false, 'a digit, a dot and two digits inside an id'),
    ('1.5', true, 'one decimal is not coordinate-like'),
    ('abc.12', true, 'no digit before the dot'),
    ('1.a22', true, 'letter after the dot'),
  ];

  group('Dart mirror vs the TypeScript pattern vs firestore.rules', () {
    for (final (value, accepted, why) in strings) {
      final shown = value.length > 20 ? '${value.length} chars' : '"$value"';
      test('$shown ($why) -> ${accepted ? 'accepted' : 'rejected'}', () {
        final p = _rulesPatterns();
        expect(_mirrorViolations(value).isEmpty, accepted, reason: 'Dart mirror');
        expect(_tsAccepts(value), accepted, reason: 'schema.ts sourceId');
        expect(_rulesAccepts(p.allow, p.deny, value), accepted,
            reason: 'firestore.rules actLabelsOk');
      });
    }
  });

  group('non-string values are rejected by the Dart mirror', () {
    for (final v in <Object>[5, 51.5007, true, const ['a'], const {'a': 1}]) {
      test('${v.runtimeType} $v', () {
        expect(_mirrorViolations(v), ['primarySourceId bad']);
      });
    }

    test('absent or null primarySourceId is not a violation', () {
      expect(_mirrorViolations(null), isEmpty);
    });
  });

  group('guards against drift of the copied literals', () {
    test('functions/src/activity_streams/schema.ts still holds them', () {
      final ts = repoFile('functions/src/activity_streams/schema.ts')
          .readAsStringSync();
      expect(ts, contains(r'pattern: /^[A-Za-z0-9._:-]{1,64}$/'));
      expect(ts, contains(r'export const COORDINATE_LIKE = /\d\.\d{2,}|\d\s*,\s*-?\d/;'));
    });

    test('firestore.rules still holds the allow pattern and the denial', () {
      final p = _rulesPatterns();
      expect(p.allow, [r'^[A-Za-z0-9._:-]{1,64}$']);
      expect(p.deny, [r'.*[0-9][.][0-9][0-9]+.*']);
    });

    test('control: a mirror without the coordinate denial would accept '
        '51.5007 (the table can fail)', () {
      expect(_tsSourceId.hasMatch('51.5007'), isTrue);
      expect(_tsSourceId.hasMatch('x-0.1276'), isTrue);
    });
  });
}
