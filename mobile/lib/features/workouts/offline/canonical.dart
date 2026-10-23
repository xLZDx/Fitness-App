/// Canonical JSON and the hashVersion 2 payload hash of the offline command
/// protocol (docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md section 2.2).
///
/// Everything here is pure: no clock, no randomness, no I/O. The server
/// implements the same rules in TypeScript and shared golden vectors are
/// iterated by both sides, so any change here is a protocol change.
///
/// Canonical form: UTF-8, no whitespace, object keys in recursive
/// lexicographic order (UTF-16 code unit order, the order of
/// `String.compareTo` and of the JavaScript default sort), integers only,
/// explicit `null` for nullable fixed fields.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const int kProtocolVersion = 2;
const int kHashVersion = 2;
const int kLimitsVersion = 1;

/// Largest integer both Dart and a JavaScript number represent exactly.
const int kMaxSafeInteger = 9007199254740991;

const int kMaxSetIndex = 1000;
const int kMaxReps = 1000;
const int kMaxLoadGrams = 1000000;
const int kMaxDependsOn = 3;

/// Thrown for any value the canonical form refuses (non-integer number,
/// unsafe integer, unpaired surrogate, non-string key, unknown type) and for a
/// payload that violates the closed field set of section 2.2.
class CanonicalizationException implements Exception {
  CanonicalizationException(this.message);

  final String message;

  @override
  String toString() => 'CanonicalizationException: $message';
}

/// Recursive lexicographic canonical JSON text of [value].
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(value, out, r'$');
  return out.toString();
}

/// UTF-8 canonical bytes of [value]. These are the bytes that are stored in
/// the queue record, hashed, and sent verbatim.
Uint8List canonicalBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJson(value)));

/// Lowercase hex SHA-256 of [bytes] (the `payloadHash` of section 2.2).
String payloadHashHex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

void _write(Object? v, StringBuffer out, String path) {
  if (v == null) {
    out.write('null');
  } else if (v is bool) {
    out.write(v ? 'true' : 'false');
  } else if (v is int) {
    if (v > kMaxSafeInteger || v < -kMaxSafeInteger) {
      throw CanonicalizationException('integer out of safe range at $path');
    }
    out.write(v.toString());
  } else if (v is String) {
    _writeString(v, out, path);
  } else if (v is List) {
    out.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) out.write(',');
      _write(v[i], out, '$path[$i]');
    }
    out.write(']');
  } else if (v is Map) {
    final keys = <String>[];
    for (final k in v.keys) {
      if (k is! String) {
        throw CanonicalizationException('non-string key at $path');
      }
      keys.add(k);
    }
    keys.sort();
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      _writeString(keys[i], out, '$path.key');
      out.write(':');
      _write(v[keys[i]], out, '$path.${keys[i]}');
    }
    out.write('}');
  } else {
    // double, num, DateTime and every other type are refused: "integers only".
    throw CanonicalizationException(
        'unsupported type ${v.runtimeType} at $path');
  }
}

/// JSON string escaping with the same output as `JSON.stringify`: only `"`,
/// `\`, and control characters below U+0020 are escaped (control characters
/// as `\b \f \n \r \t` or lowercase `\u00xx`); everything else is emitted raw.
void _writeString(String s, StringBuffer out, String path) {
  out.write('"');
  final units = s.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        out.writeCharCode(c);
        out.writeCharCode(units[i + 1]);
        i++;
        continue;
      }
      throw CanonicalizationException('unpaired surrogate at $path');
    }
    if (c >= 0xDC00 && c <= 0xDFFF) {
      throw CanonicalizationException('unpaired surrogate at $path');
    }
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (c < 0x20) {
          out.write(r'\u00');
          out.write(c.toRadixString(16).padLeft(2, '0'));
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}

// Mirrors functions/src/workout_commands/canonical.ts (parseCommandPayload).
final RegExp _operationIdPattern = RegExp(r'^[A-Za-z0-9_-]{30}$');
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final RegExp _titleKeyPattern =
    RegExp(r'^(default|day:[A-Za-z0-9_-]{1,64}|plan:[A-Za-z0-9_-]{1,64})$');
final RegExp _sourcePattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

const int kMaxGenerationOrEpoch = 1000000;
const int kMaxSeq = 2147483647;
const int kMaxUidLength = 128;

// Firestore reserves ids of the form __name__ (server RESERVED_ID).
final RegExp _reservedIdPattern = RegExp(r'^__.*__$');

/// A 30 character operation id (8 character uid tag plus 22 characters),
/// not of the reserved form `__...__`.
bool isValidOperationId(String id) =>
    _operationIdPattern.hasMatch(id) && !_reservedIdPattern.hasMatch(id);

/// Session, exercise, install and day ids: `^[A-Za-z0-9_-]{1,128}$`, not of
/// the reserved form `__...__`.
bool isValidIdString(String id) =>
    _idPattern.hasMatch(id) && !_reservedIdPattern.hasMatch(id);

/// The CompleteSet body field set of section 2.2 (package body plus
/// `performedAtClientMs`). The set is closed: a missing or extra key is
/// rejected.
const List<String> kCompleteSetBodyKeys = <String>[
  'mode',
  'setId',
  'performedConfirmed',
  'actualReps',
  'actualRepsConfirmed',
  'targetReps',
  'loadGrams',
  'source',
  'performedAtClientMs',
];

/// `set_` plus [setIndex] zero-padded to 4 digits (section 2.1).
String displaySetId(int setIndex) => 'set_${setIndex.toString().padLeft(4, '0')}';

/// `{sessionId}:{exerciseId}:{setIndex}` (section 2.1).
String logicalSetIdOf(String sessionId, String exerciseId, int setIndex) =>
    '$sessionId:$exerciseId:$setIndex';

/// Builds the hashed canonical object of section 2.2 for a CompleteSet APPEND
/// as a plain map. Pure; validates the closed field set and the limits that
/// are known from the spec. Feed the result to [canonicalBytes].
///
/// [body] must contain exactly [kCompleteSetBodyKeys]; nullable values are
/// passed as explicit `null`. V0 supports `mode == 'APPEND'` only.
Map<String, Object?> buildCompleteSetPayload({
  required String operationId,
  required String uid,
  required String sessionId,
  required String originDeviceInstallId,
  required int sessionGeneration,
  required int acceptedEpoch,
  required int seq,
  required List<String> dependsOn,
  required String exerciseId,
  required int setIndex,
  Map<String, Object?>? sessionInit,
  required Map<String, Object?> body,
}) {
  if (!isValidOperationId(operationId)) {
    throw CanonicalizationException('invalid operationId');
  }
  if (uid.isEmpty || uid.length > kMaxUidLength) {
    throw CanonicalizationException('uid must be 1..$kMaxUidLength characters');
  }
  if (!isValidIdString(sessionId)) {
    throw CanonicalizationException('invalid sessionId');
  }
  if (!isValidIdString(exerciseId)) {
    throw CanonicalizationException('invalid exerciseId');
  }
  if (!isValidIdString(originDeviceInstallId)) {
    throw CanonicalizationException('invalid originDeviceInstallId');
  }
  if (sessionGeneration < 1 || sessionGeneration > kMaxGenerationOrEpoch) {
    throw CanonicalizationException(
        'sessionGeneration must be in 1..$kMaxGenerationOrEpoch');
  }
  if (acceptedEpoch < 0 || acceptedEpoch > kMaxGenerationOrEpoch) {
    throw CanonicalizationException(
        'acceptedEpoch must be in 0..$kMaxGenerationOrEpoch');
  }
  if (seq < 1 || seq > kMaxSeq) {
    throw CanonicalizationException('seq must be in 1..$kMaxSeq');
  }
  if (setIndex < 1 || setIndex > kMaxSetIndex) {
    throw CanonicalizationException('setIndex must be in 1..$kMaxSetIndex');
  }
  if (dependsOn.length > kMaxDependsOn) {
    throw CanonicalizationException('dependsOn has more than $kMaxDependsOn entries');
  }
  final deps = List<String>.of(dependsOn)..sort();
  for (var i = 0; i < deps.length; i++) {
    if (!isValidOperationId(deps[i])) {
      throw CanonicalizationException('invalid dependsOn entry');
    }
    if (deps[i] == operationId) {
      throw CanonicalizationException('dependsOn contains the operation itself');
    }
    if (i > 0 && deps[i] == deps[i - 1]) {
      throw CanonicalizationException('duplicate dependsOn entry');
    }
  }
  _validateCompleteSetBody(body, setIndex);
  if (sessionInit != null) _validateSessionInit(sessionInit);

  return <String, Object?>{
    'protocolVersion': kProtocolVersion,
    'hashVersion': kHashVersion,
    'limitsVersion': kLimitsVersion,
    'operationId': operationId,
    'uid': uid,
    'sessionId': sessionId,
    'originDeviceInstallId': originDeviceInstallId,
    'sessionGeneration': sessionGeneration,
    'acceptedEpoch': acceptedEpoch,
    'seq': seq,
    'dependsOn': deps,
    'exerciseId': exerciseId,
    'operation': 'CompleteSet',
    'logicalSetId': logicalSetIdOf(sessionId, exerciseId, setIndex),
    'sessionInit': sessionInit == null ? null : Map<String, Object?>.of(sessionInit),
    'body': <String, Object?>{for (final k in kCompleteSetBodyKeys) k: body[k]},
  };
}

void _validateSessionInit(Map<String, Object?> init) {
  const keys = {'titleKey', 'dayId', 'startedAtClientMs'};
  if (init.length != keys.length || !init.keys.every(keys.contains)) {
    throw CanonicalizationException(
        'sessionInit must have exactly titleKey, dayId, startedAtClientMs');
  }
  final titleKey = init['titleKey'];
  if (titleKey is! String || !_titleKeyPattern.hasMatch(titleKey)) {
    throw CanonicalizationException(
        'sessionInit.titleKey must be default, day:<id> or plan:<id>');
  }
  final dayId = init['dayId'];
  if (dayId != null && (dayId is! String || !isValidIdString(dayId))) {
    throw CanonicalizationException('sessionInit.dayId must be an id or null');
  }
  final startedAt = init['startedAtClientMs'];
  if (startedAt is! int || startedAt < 0 || startedAt > kMaxSafeInteger) {
    throw CanonicalizationException(
        'sessionInit.startedAtClientMs must be a non-negative integer');
  }
}

void _validateCompleteSetBody(Map<String, Object?> body, int setIndex) {
  if (body.length != kCompleteSetBodyKeys.length ||
      !kCompleteSetBodyKeys.every(body.containsKey)) {
    throw CanonicalizationException(
        'CompleteSet body must have exactly: ${kCompleteSetBodyKeys.join(', ')}');
  }
  if (body['mode'] != 'APPEND') {
    throw CanonicalizationException('V0 supports mode APPEND only');
  }
  if (body['setId'] != displaySetId(setIndex)) {
    throw CanonicalizationException('body.setId does not match setIndex');
  }
  _requireBool(body, 'performedConfirmed');
  _requireBool(body, 'actualRepsConfirmed');
  _requireIntOrNull(body, 'actualReps', kMaxReps);
  _requireIntOrNull(body, 'targetReps', kMaxReps);
  _requireIntOrNull(body, 'loadGrams', kMaxLoadGrams);
  final source = body['source'];
  if (source is! String || !_sourcePattern.hasMatch(source)) {
    throw CanonicalizationException('body.source must match [A-Za-z0-9_-]{1,32}');
  }
  final at = body['performedAtClientMs'];
  if (at is! int || at < 0 || at > kMaxSafeInteger) {
    throw CanonicalizationException(
        'body.performedAtClientMs must be a non-negative integer');
  }
}

void _requireBool(Map<String, Object?> body, String key) {
  if (body[key] is! bool) {
    throw CanonicalizationException('body.$key must be a boolean');
  }
}

void _requireIntOrNull(Map<String, Object?> body, String key, int max) {
  final v = body[key];
  if (v == null) return;
  if (v is! int || v < 0 || v > max) {
    throw CanonicalizationException('body.$key must be null or an integer in 0..$max');
  }
}
