// Feeds every shared golden vector of the offline workout command protocol to
// the Dart canonicalizer. The file is produced by the server side.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('../docs/v1/fixtures/workout_command_golden_vectors.json');

  test('the golden vector file exists and holds vectors', () {
    expect(file.existsSync(), isTrue, reason: 'fixture missing: ${file.path}');
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(doc['hashVersion'], kHashVersion);
    expect((doc['vectors']! as List).length, greaterThan(5));
  });

  if (!file.existsSync()) return;
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final vectors = (doc['vectors']! as List).cast<Map<String, Object?>>();

  test('vector names are unique', () {
    final names = vectors.map((v) => v['name']).toList();
    expect(names.toSet().length, names.length);
  });

  for (final v in vectors) {
    final name = v['name']! as String;
    test('vector $name', () {
      final obj = v['payloadObject'];
      final text = v['payloadText']! as String;
      final hash = v['payloadHash']! as String;
      if (obj != null) {
        final canon = canonicalJson(obj);
        expect(canon, v['canonicalText'], reason: 'canonical text');
        expect(canon, text, reason: 'payloadText equals canonicalText');
        expect(payloadHashHex(canonicalBytes(obj)), hash, reason: 'sha256');
        expect(payloadHashHex(utf8.encode(canon)), hash);
      } else {
        // Raw-text vector: only the hash of the literal text is checkable.
        expect(payloadHashHex(utf8.encode(text)), hash);
      }
      final auth = v['authUid'];
      if (auth is String && v['uidTag'] != null) {
        expect(uidTagOf(auth), v['uidTag'], reason: 'uidTag');
      }
      if (obj is Map && obj['operationId'] is String && v['uidTag'] is String) {
        final id = obj['operationId']! as String;
        // A deliberately mismatching id is allowed only for uid-mismatch vectors.
        if (v['expectedPrepare'] == 'OK') {
          expect(id.startsWith(v['uidTag']! as String), isTrue);
          expect(isValidOperationId(id), isTrue);
        }
      }
    });
  }

  // Every vector the server rejects as INVALID_PAYLOAD whose logical payload is
  // known must also be refused by the Dart builder, so a client cannot mint it.
  const envelopeOnly = <String>{'client_hash_does_not_match_bytes'};
  // The builder is a producer: it NORMALISES dependsOn into ascending order
  // instead of refusing it, so the unsorted text can never be produced by it.
  const normalised = <String>{
    'depends_on_unsorted_rejected',
    'depends_on_wrong_order_underscore_before_upper_rejected',
  };
  for (final v in vectors) {
    final name = v['name']! as String;
    if (v['expectedPrepare'] != 'INVALID_PAYLOAD' || v['payloadObject'] == null) {
      continue;
    }
    if (envelopeOnly.contains(name)) {
      test('invalid vector $name: payload builds, only the envelope hash is wrong',
          () {
        final obj = v['payloadObject']! as Map<String, Object?>;
        expect(() => _buildFromObject(obj), returnsNormally);
        expect(payloadHashHex(canonicalBytes(obj)), isNot(v['sentPayloadHash']));
      });
      continue;
    }
    if (normalised.contains(name)) {
      test('invalid vector $name: the builder emits ascending dependsOn, never the invalid text',
          () {
        final obj = v['payloadObject']! as Map<String, Object?>;
        final built = _buildFromObject(obj);
        final deps = (built['dependsOn']! as List).cast<String>();
        expect(deps, List<String>.of(deps)..sort());
        expect(canonicalJson(built), isNot(canonicalJson(obj)));
        expect(payloadHashHex(canonicalBytes(built)), isNot(v['payloadHash']));
      });
      continue;
    }
    test('invalid vector $name: the Dart builder throws CanonicalizationException',
        () {
      final obj = v['payloadObject']! as Map<String, Object?>;
      expect(() => _buildFromObject(obj),
          throwsA(isA<CanonicalizationException>()));
    });
  }
}

/// Maps a logical payload object onto the typed builder, strictly: a wrong
/// shape is itself a CanonicalizationException.
Map<String, Object?> _buildFromObject(Map<String, Object?> o) {
  CanonicalizationException bad(String m) => CanonicalizationException(m);
  const keys = <String>{
    'protocolVersion', 'hashVersion', 'limitsVersion', 'operationId', 'uid',
    'sessionId', 'originDeviceInstallId', 'sessionGeneration', 'acceptedEpoch',
    'seq', 'dependsOn', 'exerciseId', 'operation', 'logicalSetId',
    'sessionInit', 'body',
  };
  if (o.length != keys.length || !o.keys.every(keys.contains)) {
    throw bad('payload key set');
  }
  T field<T>(String k) {
    final v = o[k];
    if (v is! T) throw bad('field $k has the wrong type');
    return v;
  }

  if (field<int>('protocolVersion') != kProtocolVersion ||
      field<int>('hashVersion') != kHashVersion ||
      field<int>('limitsVersion') != kLimitsVersion ||
      field<String>('operation') != 'CompleteSet') {
    throw bad('version or operation');
  }
  final sessionId = field<String>('sessionId');
  final exerciseId = field<String>('exerciseId');
  final logical = field<String>('logicalSetId');
  final prefix = '$sessionId:$exerciseId:';
  if (!logical.startsWith(prefix)) throw bad('logicalSetId prefix');
  final indexText = logical.substring(prefix.length);
  final setIndex = int.tryParse(indexText);
  if (setIndex == null || setIndex.toString() != indexText) {
    throw bad('logicalSetId index is not canonical decimal');
  }
  final init = o['sessionInit'];
  return buildCompleteSetPayload(
    operationId: field<String>('operationId'),
    uid: field<String>('uid'),
    sessionId: sessionId,
    originDeviceInstallId: field<String>('originDeviceInstallId'),
    sessionGeneration: field<int>('sessionGeneration'),
    acceptedEpoch: field<int>('acceptedEpoch'),
    seq: field<int>('seq'),
    dependsOn: List<String>.from(field<List<Object?>>('dependsOn')),
    exerciseId: exerciseId,
    setIndex: setIndex,
    sessionInit: init == null ? null : Map<String, Object?>.from(init as Map),
    body: Map<String, Object?>.from(field<Map<String, Object?>>('body')),
  );
}
