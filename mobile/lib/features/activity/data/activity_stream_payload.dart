/// The structured payload of the private stream object (S02 design 3.1, 5.1,
/// 5.1a). Pure Dart, no Flutter imports; gzip encoding happens outside
/// `activity/data` because `dart:io` is forbidden here.
///
/// The builder is a CLOSED schema: it copies only the key sets listed below
/// and never trusts the caller. `heartRate` is hard-denied whatever the
/// caller passes; kinds beyond [kCloudStreamKinds] stay device-only (DQ-2);
/// laps carry no heart-rate key; `meta` never holds `userEdits`,
/// `explicitValues` or `mergeNotes`. The per-string regexes are PROPOSED values
/// to be reviewed by the security reviewer before the server validator is
/// written (design 5.1a).
library;

import 'activity_session.dart';
import 'lap.dart';
import 'sample_stream.dart';
import 'source_kind.dart';

/// Stream kinds that may reach the cloud (design 5.1). Heart rate is not here.
const Set<StreamKind> kCloudStreamKinds = {
  StreamKind.gps,
  StreamKind.altitude,
  StreamKind.speed,
};

/// Payload schema number.
const int kStreamPayloadSchema = 1;

/// Closed key sets, pinned by the shared fixture `stream_schema_keys.json`.
const Set<String> kStreamKeys = {
  'kind',
  'unit',
  'sourceId',
  'offsetsMs',
  'values',
  'lats',
  'lons',
  'accuracies',
};
const Set<String> kLapKeys = {
  'index',
  'kind',
  'startOffsetS',
  'durationS',
  'distanceM',
  'strokeCount',
  'strokeType',
};
const Set<String> kProvenanceKeys = {
  'sourceId',
  'sourceKind',
  'importedAt',
  'deviceModel',
  'appPackage',
  'externalId',
  'fieldsContributed',
};

/// Per-string-field regexes of the provenance schema (PROPOSED).
final Map<String, RegExp> kProvenanceStringPatterns = {
  'sourceId': RegExp(r'^[A-Za-z0-9._:-]{1,64}$'),
  'deviceModel': RegExp(r'^[A-Za-z0-9 ._()-]{1,64}$'),
  'appPackage': RegExp(r'^[a-z][a-z0-9_.]{0,127}$'),
  'externalId': RegExp(r'^[A-Za-z0-9._:-]{1,128}$'),
};

/// The shared coordinate-like denial, byte for byte the server's `COORDINATE_LIKE`
/// (`functions/src/activity_streams/schema.ts`): a number with at least two
/// decimals, or two numbers separated by a comma. No free-form string field may
/// match it.
final RegExp kCoordinateLike = RegExp(r'\d\.\d{2,}|\d\s*,\s*-?\d');

final Set<String> _kLapKindNames = {for (final k in LapKind.values) k.name};
final Set<String> _kStrokeTypeNames = {for (final k in StrokeType.values) k.name};
final Set<String> _kSourceKindNames = {for (final k in SourceKind.values) k.name};

final RegExp kFieldContributedPattern = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,31}$');
const int kMaxFieldsContributed = 32;

class ActivityStreamPayload {
  const ActivityStreamPayload._(this.kinds, this.laps, this.provenance);

  /// Streams by kind name, in closed key form.
  final Map<String, Map<String, dynamic>> kinds;

  /// Laps in the closed lap form (no heart-rate key).
  final List<Map<String, dynamic>> laps;

  /// Provenance records in the closed provenance form.
  final List<Map<String, dynamic>> provenance;

  /// Builds the payload of [s]. [allowedKinds] is intersected with
  /// [kCloudStreamKinds]; `heartRate` is never included.
  static ActivityStreamPayload fromSession(
    ActivitySession s, {
    Set<StreamKind> allowedKinds = kCloudStreamKinds,
  }) {
    final kinds = <String, Map<String, dynamic>>{};
    for (final k in StreamKind.values) {
      if (k == StreamKind.heartRate) continue;
      if (!kCloudStreamKinds.contains(k) || !allowedKinds.contains(k)) continue;
      final stream = s.streams[k];
      if (stream == null || stream.isEmpty) continue;
      final closed = _closed(stream.toJson(), kStreamKeys);
      // The server requires a clean `sourceId` on every stream; one it would
      // reject cannot be repaired, so that kind stays device-only.
      if (!_isCleanString(closed['sourceId'], kProvenanceStringPatterns['sourceId']!)) {
        continue;
      }
      kinds[k.name] = closed;
    }
    final laps = [
      for (final l in s.laps) _cleanLap(_closed(l.toJson(), kLapKeys)),
    ];
    final provenance = <Map<String, dynamic>>[];
    for (final p in s.provenance) {
      final rec = _closed(p.toJson(), kProvenanceKeys);
      final clean = _cleanProvenance(rec);
      if (clean != null) provenance.add(clean);
    }
    return ActivityStreamPayload._(kinds, laps, provenance);
  }

  /// The JSON document: `schema`, `kinds`, `meta` (closed top level).
  Map<String, dynamic> toJson() => {
        'schema': kStreamPayloadSchema,
        'kinds': kinds,
        'meta': {'laps': laps, 'provenance': provenance},
      };

  static Map<String, dynamic> _closed(
          Map<String, dynamic> m, Set<String> allowed) =>
      {
        for (final e in m.entries)
          if (allowed.contains(e.key)) e.key: e.value,
      };

  /// True when [v] is a string that matches [pattern] and is not coordinate-like
  /// (the same two checks the server applies, `checkedString` in `validate.ts`).
  static bool _isCleanString(Object? v, RegExp pattern) =>
      v is String && pattern.hasMatch(v) && !kCoordinateLike.hasMatch(v);

  /// `importedAt` in the server form: UTC ISO-8601 to whole seconds. A
  /// fractional second such as `00.123` would itself match the coordinate-like
  /// denial, so it is cut; an unparseable value yields null.
  static String? _wholeSecondIso(Object? v) {
    if (v is! String) return null;
    final t = DateTime.tryParse(v);
    if (t == null) return null;
    final u = t.toUtc();
    final iso = DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second)
        .toIso8601String();
    // `toIso8601String` of a whole second ends in `.000Z`; the server pattern
    // allows no fraction to be absent, so remove it.
    return iso.replaceFirst(RegExp(r'\.0+Z$'), 'Z');
  }

  /// Sanitises one lap: the two enum-named strings are checked against their
  /// names (an unknown lap kind falls back to `auto`, an unknown stroke type is
  /// dropped), so the server never rejects the payload for them.
  static Map<String, dynamic> _cleanLap(Map<String, dynamic> lap) {
    final out = <String, dynamic>{...lap};
    final kind = out['kind'];
    if (!(kind is String && _kLapKindNames.contains(kind))) out['kind'] = 'auto';
    final stroke = out['strokeType'];
    if (stroke != null && !(stroke is String && _kStrokeTypeNames.contains(stroke))) {
      out.remove('strokeType');
    }
    return out;
  }

  /// Drops optional string fields that fail their pattern or the coordinate-like
  /// denial; a record whose required strings (`sourceId`, `sourceKind`,
  /// `importedAt`) cannot be made valid is dropped whole, as the server would
  /// reject the payload otherwise.
  static Map<String, dynamic>? _cleanProvenance(Map<String, dynamic> rec) {
    final out = <String, dynamic>{...rec};
    for (final e in kProvenanceStringPatterns.entries) {
      final v = out[e.key];
      if (v != null && !_isCleanString(v, e.value)) {
        out.remove(e.key);
      }
    }
    if (out['sourceId'] is! String) return null;
    final kind = out['sourceKind'];
    if (!(kind is String && _kSourceKindNames.contains(kind))) return null;
    final at = _wholeSecondIso(out['importedAt']);
    if (at == null) return null;
    out['importedAt'] = at;
    final fields = out['fieldsContributed'];
    out['fieldsContributed'] = [
      for (final f in (fields is List ? fields : const []))
        if (f is String && _isCleanString(f, kFieldContributedPattern)) f,
    ].take(kMaxFieldsContributed).toList();
    return out;
  }
}
