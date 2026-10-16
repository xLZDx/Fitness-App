/// JSON-safe storage form of a cloud summary map and the equality used by the
/// sync layer (S02 design 3.2). The journal keeps `baseSummary` inside
/// `record.json`, so timestamps are stored as ISO-8601 strings; in memory a
/// summary always holds `DateTime` values (as `ActivityCloudSummary` emits and
/// as a `ActivitySummaryBackend` must return them).
library;

import '../data/summary_fields.dart';

const Set<String> _kTimestampKeys = {'startUtc', 'endUtc', 'updatedAt'};

/// Encodes [summary] for `record.json`: `DateTime` -> UTC ISO-8601 string.
Map<String, Object?> encodeSummary(Map<String, Object?> summary) => {
      for (final e in summary.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
    };

/// Decodes a stored summary: timestamp keys that hold strings become UTC
/// `DateTime`; everything else is kept. Null stays null.
Map<String, Object?>? decodeSummary(Map<String, Object?>? stored) {
  if (stored == null) return null;
  return {
    for (final e in stored.entries)
      e.key: _kTimestampKeys.contains(e.key) && e.value is String
          ? (DateTime.tryParse(e.value as String)?.toUtc() ?? e.value)
          : e.value,
  };
}

bool _sameValue(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  if (a is DateTime && b is DateTime) return a.toUtc() == b.toUtc();
  return a == b;
}

/// True when [a] and [b] hold the same value for every allowlisted key except
/// the bookkeeping keys (`rev`, `updatedAt`).
bool summariesEqual(Map<String, Object?> a, Map<String, Object?> b) {
  final keys = <String>{...a.keys, ...b.keys}
    ..removeAll(kSummaryBookkeepingKeys)
    ..retainWhere(kSummaryAllowedKeys.contains);
  for (final k in keys) {
    if (!_sameValue(a[k], b[k])) return false;
  }
  return true;
}

/// The server revision of a summary map, or 0 when absent or malformed.
int summaryRev(Map<String, Object?>? summary) {
  final r = summary?['rev'];
  return r is num ? r.toInt() : 0;
}
