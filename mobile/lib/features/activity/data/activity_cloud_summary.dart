/// The scalar cloud summary of one activity (S02 design 3.1, 3.2). Pure Dart,
/// no Flutter imports.
///
/// Scalars only: no list, no map, no geometry, no heart rate, no friend data.
/// Values are the EFFECTIVE projection of the record (raw derivation, explicit
/// user values, cloud overrides). Every emitted value is inside the bound the
/// rules enforce; a value outside it is omitted rather than emitted.
library;

import 'activity_session.dart';
import 'sample_stream.dart';
import 'summary_fields.dart';
import 'summary_projection.dart';

class ActivityCloudSummary {
  const ActivityCloudSummary._();

  /// Builds the summary document map.
  ///
  /// [previousSummary] and [previousRev] are the summary last stored for this
  /// activity (the journal's `baseSummary` and `baseRev`). `rev` is 1 for the
  /// first summary; otherwise the previous `rev`, raised by exactly one when
  /// some summary VALUE changed. `rev` never depends on a clock. [updatedAt]
  /// is a client-clock hint only and is emitted when given.
  ///
  /// Throws [StateError] for a read-only (newer-schema) session: this build
  /// does not write such a record.
  static Map<String, Object> fromSession(
    ActivitySession s, {
    Map<String, Object?>? previousSummary,
    int? previousRev,
    DateTime? updatedAt,
  }) {
    if (s.isReadOnly) {
      throw StateError('a schema ${s.schema} record is read-only');
    }
    final out = <String, Object>{
      'schema': s.schema,
      'sport': s.sport.name,
      'startUtc': s.startUtc,
      'endUtc': s.endUtc,
    };
    if (kSummaryIntBounds['utcOffsetMinutes']!.accepts(s.utcOffsetMinutes)) {
      out['utcOffsetMinutes'] = s.utcOffsetMinutes;
    }
    final eff = SummaryProjection.effective(s);
    for (final e in kSummaryNumericBounds.entries) {
      final v = eff[e.key];
      if (v != null && e.value.accepts(v)) out[e.key] = v;
    }
    if (s.provenance.isNotEmpty) {
      final first = s.provenance.first;
      if (first.sourceId.isNotEmpty && first.sourceId.length <= 64) {
        out['primarySourceId'] = first.sourceId;
      }
      out['primarySourceKind'] = first.sourceKind.name;
    }
    out['sourceCount'] = _cap(s.provenance.length);
    out['userEditCount'] = s.userEditCount;
    out['mergeNoteCount'] = _cap(s.mergeNotes.length);
    final gps = s.streams[StreamKind.gps];
    out['hasRoute'] = gps != null && !gps.isEmpty;
    _putVersion(out, 'formulaVersion', s.formulaVersion);
    _putVersion(out, 'metricDefinitionVersion', s.metricDefinitionVersion);
    _putVersion(out, 'thresholdPolicyVersion', s.thresholdPolicyVersion);
    final terms = s.sourceTermsSnapshot;
    if (terms != null && kSourceTermsPattern.hasMatch(terms)) {
      out['sourceTermsSnapshot'] = terms;
    }
    out['rev'] = _nextRev(out, previousSummary, previousRev);
    if (updatedAt != null) out['updatedAt'] = updatedAt.toUtc();
    return out;
  }

  static int _cap(int n) => n > 64 ? 64 : n;

  static void _putVersion(Map<String, Object> out, String key, String v) {
    if (kVersionStringPattern.hasMatch(v)) out[key] = v;
  }

  static int _nextRev(
    Map<String, Object> now,
    Map<String, Object?>? previous,
    int? previousRev,
  ) {
    if (previous == null) return 1;
    final prev = previousRev ??
        (previous['rev'] is int ? previous['rev'] as int : 0);
    final keys = <String>{...now.keys, ...previous.keys}
      ..removeAll(kSummaryBookkeepingKeys);
    var changed = false;
    for (final k in keys) {
      final a = now[k];
      final b = previous[k];
      final same = a is num && b is num ? a.toDouble() == b.toDouble() : a == b;
      if (!same) {
        changed = true;
        break;
      }
    }
    final next = changed ? prev + 1 : prev;
    if (next < 1) return 1;
    return next > 1000000 ? 1000000 : next;
  }
}
