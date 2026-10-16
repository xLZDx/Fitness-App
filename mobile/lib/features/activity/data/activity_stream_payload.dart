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
import 'sample_stream.dart';

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
      kinds[k.name] = _closed(stream.toJson(), kStreamKeys);
    }
    final laps = [
      for (final l in s.laps) _closed(l.toJson(), kLapKeys),
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

  /// Drops string fields that do not match their pattern; a record without a
  /// valid `sourceId` is dropped whole.
  static Map<String, dynamic>? _cleanProvenance(Map<String, dynamic> rec) {
    final out = <String, dynamic>{...rec};
    for (final e in kProvenanceStringPatterns.entries) {
      final v = out[e.key];
      if (v != null && !(v is String && e.value.hasMatch(v))) {
        out.remove(e.key);
      }
    }
    if (out['sourceId'] is! String) return null;
    final fields = out['fieldsContributed'];
    out['fieldsContributed'] = [
      for (final f in (fields is List ? fields : const []))
        if (f is String && kFieldContributedPattern.hasMatch(f)) f,
    ].take(kMaxFieldsContributed).toList();
    return out;
  }
}
