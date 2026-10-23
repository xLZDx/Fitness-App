import 'dart:convert';
import 'dart:math';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

Matcher get _canonErr => throwsA(isA<CanonicalizationException>());

Map<String, Object?> _payload({
  String operationId = _op1,
  List<String> dependsOn = const <String>[],
  Map<String, Object?>? body,
  int setIndex = 1,
  int seq = 1,
  Map<String, Object?>? sessionInit,
}) =>
    buildCompleteSetPayload(
      operationId: operationId,
      uid: kUid,
      sessionId: 'sess-1',
      originDeviceInstallId: kDevice,
      sessionGeneration: 1,
      acceptedEpoch: 0,
      seq: seq,
      dependsOn: dependsOn,
      exerciseId: 'ex-1',
      setIndex: setIndex,
      sessionInit: sessionInit,
      body: body ?? setBody(setIndex),
    );

String _id(String c) => c * 30;
const String _op1 = 'oooooooooooooooooooooooooooooo';

void main() {
  group('canonicalJson: ordering and shape', () {
    test('keys are sorted recursively, arrays keep their order, no whitespace',
        () {
      final text = canonicalJson(<String, Object?>{
        'b': 1,
        'a': <String, Object?>{'z': 1, 'y': <Object?>[3, 1, 2], 'x': null},
        'A': true,
      });
      expect(text, '{"A":true,"a":{"x":null,"y":[3,1,2],"z":1},"b":1}');
    });

    test('insertion order of the map never changes the text', () {
      final m1 = <String, Object?>{'a': 1, 'b': 2, 'c': 3};
      final m2 = <String, Object?>{'c': 3, 'a': 1, 'b': 2};
      expect(canonicalJson(m1), canonicalJson(m2));
      expect(canonicalJson(m1), '{"a":1,"b":2,"c":3}');
    });

    test('keys order is UTF-16 code unit order, not code point order', () {
      // U+1F600 is the surrogate pair D83D DE00; U+FF5E is a single unit FF5E.
      // UTF-16 order puts the emoji first (0xD83D < 0xFF5E); code point order
      // would put it last. This is the JavaScript default sort order.
      final text = canonicalJson(<String, Object?>{
        '～': 1,
        '\u{1F600}': 2,
      });
      expect(text, '{"\u{1F600}":2,"～":1}');
    });

    test('uppercase sorts before lowercase and digits before letters', () {
      expect(canonicalJson(<String, Object?>{'a': 0, 'B': 0, '1': 0}),
          '{"1":0,"B":0,"a":0}');
    });

    test('scalars, empties and nulls', () {
      expect(canonicalJson(null), 'null');
      expect(canonicalJson(true), 'true');
      expect(canonicalJson(false), 'false');
      expect(canonicalJson(<String, Object?>{}), '{}');
      expect(canonicalJson(<Object?>[]), '[]');
      expect(canonicalJson(<String, Object?>{'k': null}), '{"k":null}');
      expect(canonicalJson(0), '0');
      expect(canonicalJson(-7), '-7');
    });
  });

  group('canonicalJson: string escaping', () {
    test('quote, backslash and the five short control escapes', () {
      expect(canonicalJson('a"b\\c'), r'"a\"b\\c"');
      expect(canonicalJson('\b\f\n\r\t'), r'"\b\f\n\r\t"');
    });

    test('other control characters use lowercase \\u00xx', () {
      expect(canonicalJson('\u0000'), r'"\u0000"');
      expect(canonicalJson('\u0001'), r'"\u0001"');
      expect(canonicalJson('\u001f'), r'"\u001f"');
      expect(canonicalJson('\u000b'), r'"\u000b"');
    });

    test('characters JSON.stringify leaves raw stay raw', () {
      // DEL, slash, angle brackets, ampersand, U+2028/2029 are NOT escaped.
      expect(canonicalJson('\u007f/<>&  '),
          '"\u007f/<>&  "');
    });

    test('keys are escaped like values', () {
      expect(canonicalJson(<String, Object?>{'a"b\n': 1}), r'{"a\"b\n":1}');
    });

    test('non-ASCII text is emitted raw and encoded as UTF-8', () {
      expect(canonicalJson('é日本'), '"é日本"');
      expect(canonicalBytes('é').toList(), <int>[0x22, 0xC3, 0xA9, 0x22]);
      expect(canonicalBytes('日').toList(),
          <int>[0x22, 0xE6, 0x97, 0xA5, 0x22]);
      // A surrogate pair becomes one 4-byte UTF-8 sequence.
      expect(canonicalBytes('\u{1F600}').toList(),
          <int>[0x22, 0xF0, 0x9F, 0x98, 0x80, 0x22]);
    });

    test('combining sequence and precomposed form are NOT normalised', () {
      // No Unicode normalisation: the two spellings hash differently.
      expect(canonicalJson('é'), isNot(canonicalJson('é')));
    });
  });

  group('canonicalJson: refusals', () {
    test('doubles are rejected, including whole-valued ones', () {
      expect(() => canonicalJson(1.5), _canonErr);
      expect(() => canonicalJson(1.0), _canonErr);
      expect(() => canonicalJson(double.nan), _canonErr);
      expect(() => canonicalJson(double.infinity), _canonErr);
      expect(() => canonicalJson(<String, Object?>{'a': 2.0}), _canonErr);
      expect(() => canonicalJson(<Object?>[1, 2.5]), _canonErr);
    });

    test('integer limits: +-(2^53-1) accepted, one beyond rejected', () {
      expect(canonicalJson(kMaxSafeInteger), '9007199254740991');
      expect(canonicalJson(-kMaxSafeInteger), '-9007199254740991');
      expect(() => canonicalJson(kMaxSafeInteger + 1), _canonErr);
      expect(() => canonicalJson(-kMaxSafeInteger - 1), _canonErr);
      expect(() => canonicalJson(1 << 62), _canonErr);
    });

    test('lone surrogates are rejected in values and in keys', () {
      expect(() => canonicalJson('\uD800'), _canonErr);
      expect(() => canonicalJson('a\uDBFFb'), _canonErr);
      expect(() => canonicalJson('\uDC00'), _canonErr);
      expect(() => canonicalJson('\uDFFFx'), _canonErr);
      // Reversed pair (low then high) is two lone surrogates.
      expect(() => canonicalJson('\uDE00\uD83D'), _canonErr);
      expect(() => canonicalJson(<String, Object?>{'\uD800': 1}), _canonErr);
      expect(() => canonicalJson(<String, Object?>{'k': <Object?>['\uDC00']}),
          _canonErr);
    });

    test('a well-formed pair is accepted', () {
      expect(canonicalJson('😀'), '"\u{1F600}"');
    });

    test('non-string keys and unsupported types are rejected', () {
      expect(() => canonicalJson(<Object?, Object?>{1: 'x'}), _canonErr);
      expect(() => canonicalJson(DateTime(2026)), _canonErr);
      expect(() => canonicalJson(Object()), _canonErr);
      expect(() => canonicalJson(<Object?>{1, 2}), _canonErr);
    });
  });

  group('payload hash', () {
    test('SHA-256 known-answer vectors, lowercase hex', () {
      expect(payloadHashHex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(payloadHashHex(const <int>[]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(payloadHashHex(canonicalBytes(<String, Object?>{'a': 1})),
          '015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862');
    });

    test('hash depends only on content, not on map insertion order', () {
      final a = _payload();
      final shuffled = <String, Object?>{
        for (final k in (a.keys.toList()..shuffle(Random(3)))) k: a[k],
      };
      expect(payloadHashHex(canonicalBytes(shuffled)),
          payloadHashHex(canonicalBytes(a)));
    });

    test('a one-unit change in any field changes the hash', () {
      final base = payloadHashHex(canonicalBytes(_payload()));
      expect(payloadHashHex(canonicalBytes(_payload(seq: 2))), isNot(base));
      expect(payloadHashHex(canonicalBytes(_payload(operationId: 'o' * 29 + '2'))),
          isNot(base));
      expect(
          payloadHashHex(canonicalBytes(
              _payload(body: setBody(1, reps: 9)))),
          isNot(base));
    });

    test('canonical bytes are deterministic across repeated calls', () {
      final p = _payload();
      expect(canonicalBytes(p), canonicalBytes(p));
      expect(payloadHashHex(canonicalBytes(p)).length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(payloadHashHex(canonicalBytes(p))),
          isTrue);
    });
  });

  group('buildCompleteSetPayload', () {
    test('produces the closed field set with explicit nulls', () {
      final p = _payload(body: setBody(2, loadGrams: null), setIndex: 2);
      expect(p.keys.toSet(), <String>{
        'protocolVersion', 'hashVersion', 'limitsVersion', 'operationId',
        'uid', 'sessionId', 'originDeviceInstallId', 'sessionGeneration',
        'acceptedEpoch', 'seq', 'dependsOn', 'exerciseId', 'operation',
        'logicalSetId', 'sessionInit', 'body',
      });
      expect(p['protocolVersion'], 2);
      expect(p['hashVersion'], 2);
      expect(p['limitsVersion'], 1);
      expect(p['operation'], 'CompleteSet');
      expect(p['logicalSetId'], 'sess-1:ex-1:2');
      expect(p['sessionInit'], isNull);
      expect(p.containsKey('sessionInit'), isTrue);
      final body = p['body']! as Map<String, Object?>;
      expect(body['loadGrams'], isNull);
      expect(body.containsKey('loadGrams'), isTrue);
      expect(body['setId'], 'set_0002');
      // The canonical text carries the nulls literally.
      expect(canonicalJson(p), contains('"sessionInit":null'));
      expect(canonicalJson(p), contains('"loadGrams":null'));
    });

    test('dependsOn is sorted and limited to 3 distinct valid ids', () {
      expect(_payload(dependsOn: [_id('b'), _id('a')])['dependsOn'],
          <String>[_id('a'), _id('b')]);
      expect(() => _payload(dependsOn: [_id('a'), _id('b'), _id('c'), _id('d')]),
          _canonErr);
      expect(() => _payload(dependsOn: [_id('a'), _id('a')]), _canonErr);
      expect(() => _payload(dependsOn: ['bad id!']), _canonErr);
    });

    test('invalid identifiers and counters are rejected', () {
      expect(() => _payload(operationId: ''), _canonErr);
      expect(() => _payload(operationId: 'has space'), _canonErr);
      expect(() => _payload(operationId: 'a' * 31), _canonErr);
      expect(() => _payload(operationId: 'a' * 29), _canonErr);
      expect(_payload(operationId: 'a' * 30)['operationId'], 'a' * 30);
      expect(() => _payload(seq: 0), _canonErr);
      expect(() => _payload(setIndex: 0), _canonErr);
      expect(() => _payload(setIndex: 1001, body: setBody(1001)), _canonErr);
      expect(_payload(setIndex: 1000, body: setBody(1000))['logicalSetId'],
          'sess-1:ex-1:1000');
    });

    test('body: extra, missing, mistyped or out-of-range fields are rejected',
        () {
      final ok = setBody(1);
      expect(() => _payload(body: {...ok, 'extra': 1}), _canonErr);
      expect(() => _payload(body: Map.of(ok)..remove('source')), _canonErr);
      expect(() => _payload(body: {...ok, 'mode': 'CORRECT'}), _canonErr);
      expect(() => _payload(body: {...ok, 'setId': 'set_0009'}), _canonErr);
      expect(() => _payload(body: {...ok, 'performedConfirmed': 1}), _canonErr);
      expect(() => _payload(body: {...ok, 'actualReps': 8.0}), _canonErr);
      expect(() => _payload(body: {...ok, 'actualReps': -1}), _canonErr);
      expect(() => _payload(body: {...ok, 'actualReps': 1001}), _canonErr);
      expect(_payload(body: {...ok, 'actualReps': 1000})['body'], isNotNull);
      expect(() => _payload(body: {...ok, 'loadGrams': 1000001}), _canonErr);
      expect(_payload(body: {...ok, 'loadGrams': 1000000})['body'], isNotNull);
      expect(() => _payload(body: {...ok, 'source': null}), _canonErr);
      expect(() => _payload(body: {...ok, 'performedAtClientMs': -1}),
          _canonErr);
      expect(() => _payload(body: {...ok, 'performedAtClientMs': 1.5}),
          _canonErr);
    });

    test('sessionInit must be exactly its three fields', () {
      final init = <String, Object?>{
        'titleKey': 'day:push_day',
        'dayId': null,
        'startedAtClientMs': 1700000000000,
      };
      expect(_payload(sessionInit: init)['sessionInit'], init);
      expect(() => _payload(sessionInit: {...init, 'x': 1}), _canonErr);
      expect(
          () => _payload(sessionInit: Map.of(init)..remove('dayId')), _canonErr);
      expect(() => _payload(sessionInit: {...init, 'titleKey': 5}), _canonErr);
      expect(() => _payload(sessionInit: {...init, 'startedAtClientMs': 1.0}),
          _canonErr);
    });
  });

  group('operation ids', () {
    test('uidTag is 8 base64url characters and matches the spec vector', () {
      expect(uidTagOf('alice'), 'S4cVY4sr');
      expect(uidTagOf('alice').length, 8);
      expect(uidTagOf('alice'), isNot(uidTagOf('bob')));
      expect(uidTagOf('alice'), uidTagOf('alice'));
    });

    test('minted id: 30 chars, valid, prefixed by the uid tag, seed-stable',
        () {
      final id = mintOperationId('alice', random: Random(1));
      expect(id.length, 30);
      expect(isValidOperationId(id), isTrue);
      expect(id.startsWith('S4cVY4sr'), isTrue);
      expect(mintOperationId('alice', random: Random(1)), id);
      expect(mintOperationId('alice', random: Random(2)), isNot(id));
    });

    test('secure ids do not collide over 2000 mints', () {
      final ids = <String>{for (var i = 0; i < 2000; i++) mintOperationId('u')};
      expect(ids.length, 2000);
    });

    test('operation id pattern boundaries', () {
      expect(isValidOperationId('A-z_9' + 'x' * 25), isTrue);
      expect(isValidOperationId('A-z_9'), isFalse); // exactly 30 required
      expect(isValidOperationId(''), isFalse);
      expect(isValidOperationId('a.' + 'b' * 28), isFalse);
      expect(isValidOperationId('${'a' * 29}\n'), isFalse);
      expect(isValidOperationId('é' + 'b' * 29), isFalse);
    });
  });
}
