/// Record-level state behind the cloud summary (S02 design 3.2 rules 1-2):
/// explicit user values and cloud overrides. Plain data with tolerant JSON;
/// the projection functions live in `summary_projection.dart`. Pure Dart, no
/// Flutter imports.
library;

import 'activity_versions.dart';
import 'summary_fields.dart';

double? _finiteOrNull(Object? v) =>
    v is num && v.isFinite ? v.toDouble() : null;

/// A value the user typed for one summary field. At most one entry per field.
class ExplicitValue {
  const ExplicitValue({
    required this.value,
    required this.atDerived,
    required this.seq,
    required this.editDerived,
    this.sourceCandidate,
  });

  /// The user's value; it wins over the raw derivation until reconsidered.
  final double value;

  /// The raw `derive(record)[field]` last seen under this entry (null when the
  /// raw derivation had no value). Moves when the raw value changes.
  final double? atDerived;

  /// The raw derivation at edit time; used to clear a candidate when the raw
  /// value returns to it.
  final double? editDerived;

  /// Order of the explicit edit operations of the record (higher = later).
  final int seq;

  /// A newer raw value offered to the user ("use the new computed value").
  final double? sourceCandidate;

  ExplicitValue copyWith({
    double? atDerived,
    bool clearCandidate = false,
    double? sourceCandidate,
  }) =>
      ExplicitValue(
        value: value,
        atDerived: atDerived ?? this.atDerived,
        seq: seq,
        editDerived: editDerived,
        sourceCandidate:
            clearCandidate ? null : (sourceCandidate ?? this.sourceCandidate),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'atDerived': atDerived,
        'seq': seq,
        if (editDerived != atDerived) 'editDerived': editDerived,
        if (sourceCandidate != null) 'sourceCandidate': sourceCandidate,
      };

  /// Null when the field is not overridable, the value is out of bound or not
  /// a number, `atDerived` is absent, or `seq` is not a non-negative int.
  static ExplicitValue? tryFromJson(String field, Object? raw) {
    final bound = kSummaryNumericBounds[field];
    if (bound == null || raw is! Map) return null;
    final value = _finiteOrNull(raw['value']);
    if (value == null || !bound.accepts(value)) return null;
    if (!raw.containsKey('atDerived')) return null;
    final atDerived = raw['atDerived'];
    if (atDerived != null && _finiteOrNull(atDerived) == null) return null;
    final seq = raw['seq'];
    if (seq is! num || !seq.isFinite || seq < 0) return null;
    final candidate = _finiteOrNull(raw['sourceCandidate']);
    return ExplicitValue(
      value: value,
      atDerived: _finiteOrNull(atDerived),
      seq: seq.toInt(),
      editDerived: raw.containsKey('editDerived')
          ? _finiteOrNull(raw['editDerived'])
          : _finiteOrNull(atDerived),
      sourceCandidate:
          candidate != null && bound.accepts(candidate) ? candidate : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExplicitValue &&
      other.value == value &&
      other.atDerived == atDerived &&
      other.editDerived == editDerived &&
      other.seq == seq &&
      other.sourceCandidate == sourceCandidate;

  @override
  int get hashCode =>
      Object.hash(value, atDerived, editDerived, seq, sourceCandidate);
}

/// A cloud value adopted for one derived field, kept while the local
/// derivation still produces the stale value it masks.
class SummaryOverride {
  const SummaryOverride({
    required this.value,
    required this.atComputed,
    required this.atVersions,
    required this.atRev,
    this.recalcCandidate,
  });

  /// The adopted server value.
  final double value;

  /// `recompute(record)[field]` at adoption time (the stale local value).
  final double atComputed;

  /// The calculation versions in force at adoption time.
  final CalcVersions atVersions;

  /// The stored server revision the value came from.
  final int atRev;

  /// A recalculated value offered after a calculation-version change.
  final double? recalcCandidate;

  SummaryOverride copyWith({
    double? atComputed,
    CalcVersions? atVersions,
    bool clearCandidate = false,
    double? recalcCandidate,
  }) =>
      SummaryOverride(
        value: value,
        atComputed: atComputed ?? this.atComputed,
        atVersions: atVersions ?? this.atVersions,
        atRev: atRev,
        recalcCandidate:
            clearCandidate ? null : (recalcCandidate ?? this.recalcCandidate),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'atComputed': atComputed,
        'atVersions': atVersions.toJson(),
        'atRev': atRev,
        if (recalcCandidate != null) 'recalcCandidate': recalcCandidate,
      };

  /// Null when the field is not overridable, a number is missing or out of
  /// bound, or `atVersions` is missing (a missing triple cannot be compared).
  static SummaryOverride? tryFromJson(String field, Object? raw) {
    final bound = kSummaryNumericBounds[field];
    if (bound == null || raw is! Map) return null;
    final value = _finiteOrNull(raw['value']);
    final atComputed = _finiteOrNull(raw['atComputed']);
    final versions = CalcVersions.tryFromJson(raw['atVersions']);
    final atRev = raw['atRev'];
    if (value == null || atComputed == null || versions == null) return null;
    if (!bound.accepts(value) || !bound.accepts(atComputed)) return null;
    if (atRev is! num || !atRev.isFinite || atRev < 0) return null;
    final candidate = _finiteOrNull(raw['recalcCandidate']);
    return SummaryOverride(
      value: value,
      atComputed: atComputed,
      atVersions: versions,
      atRev: atRev.toInt(),
      recalcCandidate:
          candidate != null && bound.accepts(candidate) ? candidate : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SummaryOverride &&
      other.value == value &&
      other.atComputed == atComputed &&
      other.atVersions == atVersions &&
      other.atRev == atRev &&
      other.recalcCandidate == recalcCandidate;

  @override
  int get hashCode =>
      Object.hash(value, atComputed, atVersions, atRev, recalcCandidate);
}

/// One entry of the device-only edit history ring (informational, never read
/// by the projection).
class EditHistoryEntry {
  const EditHistoryEntry({
    required this.field,
    required this.value,
    required this.seq,
  });

  final String field;
  final double value;
  final int seq;

  Map<String, dynamic> toJson() => {'field': field, 'value': value, 'seq': seq};

  /// Null for anything that is not `{field: String, value: finite, seq: int}`.
  static EditHistoryEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final field = raw['field'];
    final value = _finiteOrNull(raw['value']);
    final seq = raw['seq'];
    if (field is! String || value == null || seq is! num || !seq.isFinite) {
      return null;
    }
    return EditHistoryEntry(field: field, value: value, seq: seq.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is EditHistoryEntry &&
      other.field == field &&
      other.value == value &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(field, value, seq);
}

/// Keeps the newest [kUserEditsRingSize] entries (the oldest are dropped).
List<EditHistoryEntry> trimEditHistory(List<EditHistoryEntry> entries) =>
    entries.length <= kUserEditsRingSize
        ? entries
        : entries.sublist(entries.length - kUserEditsRingSize);

/// Tolerant read of the `explicitValues` map; bad entries are dropped one by
/// one without touching the others.
Map<String, ExplicitValue> readExplicitValues(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, ExplicitValue>{};
  for (final e in raw.entries) {
    final f = e.key.toString();
    final parsed = ExplicitValue.tryFromJson(f, e.value);
    if (parsed != null) out[f] = parsed;
  }
  return out;
}

/// Tolerant read of the `summaryOverrides` map.
Map<String, SummaryOverride> readSummaryOverrides(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, SummaryOverride>{};
  for (final e in raw.entries) {
    final f = e.key.toString();
    final parsed = SummaryOverride.tryFromJson(f, e.value);
    if (parsed != null) out[f] = parsed;
  }
  return out;
}

/// Tolerant read of the history ring, trimmed to the newest entries.
List<EditHistoryEntry> readEditHistory(Object? raw) {
  if (raw is! List) return const [];
  return trimEditHistory([
    for (final e in raw)
      if (EditHistoryEntry.tryFromJson(e) case final x?) x,
  ]);
}

/// Serialises a field map with sorted keys, so equal records encode equally.
Map<String, dynamic> encodeSorted<T>(
  Map<String, T> m,
  Map<String, dynamic> Function(T) enc,
) =>
    {
      for (final k in (m.keys.toList()..sort())) k: enc(m[k] as T),
    };
