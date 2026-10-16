// S02 test epic 3, U14: the A-1 quarantine stage rejects hostile raw input with
// a reason code and accepts valid input.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_quarantine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/synthetic_activity_corpus.dart';

void _rejected(String raw, QuarantineReason why, {String? label}) {
  final r = quarantineCheck(raw);
  expect(r.accepted, isFalse, reason: label ?? why.name);
  expect(r.reason, why, reason: label);
  expect(r.value, isNull, reason: 'a rejected input must not carry a value');
}

String _streamWith(int n, {String list = 'offsetsMs'}) {
  final b = StringBuffer('{"streams":[{"kind":"gps","$list":[');
  for (var i = 0; i < n; i++) {
    if (i > 0) b.write(',');
    b.write(i);
  }
  b.write(']}]}');
  return b.toString();
}

void main() {
  group('U14 hostile input is rejected with a reason code', () {
    test('200 001 samples', () {
      _rejected(_streamWith(200001), QuarantineReason.tooManySamples);
    });

    test('the same list of exactly 200 000 samples is accepted (boundary)', () {
      expect(quarantineCheck(_streamWith(200000)).accepted, isTrue);
    });

    test('too many samples in any of the parallel lists', () {
      for (final k in ['values', 'lats', 'lons', 'accuracies']) {
        _rejected(_streamWith(200001, list: k), QuarantineReason.tooManySamples,
            label: k);
      }
    });

    test('depth 100 nesting', () {
      _rejected('${'[' * 100}${']' * 100}', QuarantineReason.tooDeep);
      _rejected('{"a":' * 100 + '1' + '}' * 100, QuarantineReason.tooDeep);
    });

    test('depth boundary: 32 accepted as nesting, 33 rejected', () {
      final ok = '{"a":${'[' * 31}${']' * 31}}'; // 1 object + 31 arrays = 32
      expect(quarantineCheck(ok).accepted, isTrue);
      final bad = '{"a":${'[' * 32}${']' * 32}}'; // 33
      _rejected(bad, QuarantineReason.tooDeep);
    });

    test('a 10 MB string', () {
      final raw = '{"note":"${'x' * 10000000}"}';
      _rejected(raw, QuarantineReason.stringTooLong);
    });

    test('string length boundary: 1 MiB accepted, one more rejected', () {
      expect(quarantineCheck('{"n":"${'x' * 1048576}"}').accepted, isTrue);
      _rejected('{"n":"${'x' * 1048577}"}', QuarantineReason.stringTooLong);
    });

    test('a key longer than the string limit is rejected too', () {
      _rejected('{"${'k' * 1048577}":1}', QuarantineReason.stringTooLong);
    });

    test('input above the total size limit', () {
      _rejected('[${'1,' * 9000000}1]', QuarantineReason.tooLarge);
    });

    test('duplicate keys', () {
      _rejected('{"a":1,"a":2}', QuarantineReason.duplicateKey);
      _rejected('{"o":{"x":1,"y":2,"x":3}}', QuarantineReason.duplicateKey);
      _rejected('{"l":[{"k":1,"k":2}]}', QuarantineReason.duplicateKey);
    });

    test('duplicate keys spelled with a JSON escape are still duplicates', () {
      // jsonDecode keeps the LAST of "a" and "a": a smuggled override.
      _rejected('{"a":1,"' r'\' 'u0061":2}', QuarantineReason.duplicateKey,
          label: 'escaped duplicate');
    });

    test('same key in sibling objects and in nested levels is NOT a duplicate',
        () {
      expect(quarantineCheck('{"a":{"a":1},"b":[{"a":1},{"a":2}]}').accepted,
          isTrue);
    });

    test('NaN / Infinity offsets', () {
      _rejected('{"streams":[{"offsetsMs":[1,NaN,3]}]}',
          QuarantineReason.malformedJson,
          label: 'NaN literal');
      _rejected('{"streams":[{"offsetsMs":[1,1e999,3]}]}',
          QuarantineReason.invalidNumber,
          label: '1e999 is infinity');
      _rejected('{"streams":[{"values":[-1e999]}]}',
          QuarantineReason.invalidNumber);
      _rejected('{"streams":[{"lats":[Infinity]}]}',
          QuarantineReason.malformedJson);
    });

    test('malformed and wrong-shape inputs get a code and never throw', () {
      _rejected('', QuarantineReason.malformedJson);
      _rejected('{', QuarantineReason.malformedJson);
      _rejected('{"a":"unterminated}', QuarantineReason.malformedJson);
      _rejected('}', QuarantineReason.malformedJson);
      _rejected('[1,2]', QuarantineReason.notAnObject);
      _rejected('"text"', QuarantineReason.notAnObject);
      _rejected('42', QuarantineReason.notAnObject);
      _rejected('null', QuarantineReason.notAnObject);
    });

    test('limits are configurable and enforced', () {
      const tight = QuarantineLimits(maxDepth: 1, maxStringChars: 4);
      expect(quarantineCheck('{"a":[1]}', limits: tight).reason,
          QuarantineReason.tooDeep);
      expect(quarantineCheck('{"a":"abcde"}', limits: tight).reason,
          QuarantineReason.stringTooLong);
      expect(quarantineCheck('{"a":"abcd"}', limits: tight).accepted, isTrue);
    });
  });

  group('U14 valid input is accepted unchanged', () {
    test('all 100 valid corpus sessions pass and decode to the same value', () {
      final corpus = SyntheticCorpus.build();
      for (final s in corpus.valid) {
        final raw = jsonEncode(corpus.schema1Maps[s.id] ?? s.toJson());
        final r = quarantineCheck(raw);
        expect(r.accepted, isTrue, reason: '${s.id}: ${r.reason}');
        expect(r.value, jsonDecode(raw), reason: s.id);
      }
    });

    test('braces, brackets and quotes inside strings do not confuse the scan',
        () {
      const raw = r'{"note":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[ { \" } ]",'
          r'"a":"x","b":"{\"a\":1,\"a\":2}"}';
      final r = quarantineCheck(raw);
      expect(r.accepted, isTrue, reason: '${r.reason}');
      expect(r.value!['a'], 'x');
    });
  });
}
