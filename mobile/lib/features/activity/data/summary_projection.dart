/// The pure projection behind the cloud summary (S02 design 3.2 rules 1-4):
/// `derive` (raw recomputation), `recompute` (raw plus explicit values),
/// `effective` (recompute plus cloud overrides), version reconciliation, the
/// value-based override lifecycle, explicit edits and the atomic resolution of
/// candidates. No clock, no random, no I/O. Pure Dart, no Flutter imports.
library;

import 'activity_session.dart';
import 'activity_versions.dart';
import 'summary_fields.dart';
import 'summary_overrides.dart';

/// The user's choice for a field that carries a candidate.
enum CandidateChoice {
  /// Use the newly computed value: drop the explicit value and the override.
  useComputed,

  /// Keep the explicit value: drop the override.
  keepMine,

  /// Use the cloud value: keep (or keep alone) the override.
  useCloud,
}

/// What a three-way step says about the resolved local value.
enum ResolutionMerge {
  /// The local value must be written to the cloud summary.
  write,

  /// Nothing to write (server already holds it, or nothing was resolved).
  noWrite,

  /// The server changed again since the base: the local value is preserved and
  /// the entry stays `sync_conflict`.
  conflict,
}

/// The result of resolving a candidate: ONE value carrying the new record
/// (explicit values, overrides and candidate changed together) and the merge
/// outcome.
class CandidateResolution {
  const CandidateResolution(this.record, this.merge, this.field, this.localValue);

  final ActivitySession record;
  final ResolutionMerge merge;
  final String field;

  /// The value chosen for the field (null when nothing was resolved).
  final double? localValue;
}

bool _numEq(Object? a, Object? b) =>
    a == null || b == null ? a == b : (a as num).toDouble() == (b as num).toDouble();

class SummaryProjection {
  const SummaryProjection._();

  /// RAW recomputation: the values the record itself produces, whatever
  /// explicit values and overrides hold. Null for a field without a value.
  static Map<String, double?> derive(ActivitySession s) {
    final f = s.summary.toFieldMap();
    return {
      'movingTimeS': s.movingTimeS,
      'distanceM': f['distanceM'],
      'ascentM': f['ascentM'],
      'descentM': f['descentM'],
      'avgSpeedMps': f['avgSpeedMps'],
      'avgCadence': f['avgCadence'],
      'avgPowerW': f['avgPowerW'],
      'normalizedPowerW': f['normalizedPowerW'],
      'activeEnergyKcal': f['activeEnergyKcal'],
      'steps': f['steps'],
      'strokeCount': f['strokeCount'],
      'poolLengthM': f['poolLengthM'],
      'lapCount': f['lapCount'] ??
          (s.laps.isEmpty ? null : s.laps.length.toDouble()),
      'avgSwolf': f['avgSwolf'],
      'routeTrimMeters': s.privacy.routeTrimMeters,
    };
  }

  /// `derive` overlaid with the canonical explicit values. This is what the
  /// design calls `recompute(record)`; the drop rules compare against it.
  static Map<String, double?> recompute(ActivitySession s) {
    final out = derive(s);
    for (final e in s.explicitValues.entries) {
      out[e.key] = e.value.value;
    }
    return out;
  }

  /// `recompute` overlaid with the cloud overrides: the values the summary
  /// writes. The device-only `editHistory` ring is never read.
  static Map<String, double?> effective(ActivitySession s) {
    final out = recompute(s);
    for (final e in s.summaryOverrides.entries) {
      out[e.key] = e.value.value;
    }
    return out;
  }

  /// Version reconciliation, explicit-value reconciliation and the value-based
  /// override lifecycle for a PASSIVE change (design 3.2 rule 2). Runs on every
  /// load and write; idempotent. [inForce] is the triple in force (default: the
  /// triple of this build).
  static ActivitySession reconcile(ActivitySession s, {CalcVersions? inForce}) {
    final versions = inForce ?? CalcVersions.current;
    final raw = derive(s);

    // Explicit values: an explicit value is never replaced by a changed raw
    // derivation; the new raw value is offered as a source candidate.
    final explicit = <String, ExplicitValue>{};
    for (final e in s.explicitValues.entries) {
      final x = e.value;
      final r = raw[e.key];
      if (r == null || _numEq(r, x.atDerived)) {
        explicit[e.key] = x;
      } else if (_numEq(r, x.value) || _numEq(r, x.editDerived)) {
        explicit[e.key] = x.copyWith(atDerived: r, clearCandidate: true);
      } else {
        explicit[e.key] = x.copyWith(atDerived: r, sourceCandidate: r);
      }
    }

    final recomputed = {...raw, for (final e in explicit.entries) e.key: e.value.value};

    // Overrides: version reconciliation first, then the value rules.
    final overrides = <String, SummaryOverride>{};
    for (final e in s.summaryOverrides.entries) {
      var o = e.value;
      final rc = recomputed[e.key];
      if (rc == null) {
        overrides[e.key] = o;
        continue;
      }
      if (o.atVersions != versions) {
        o = _numEq(rc, o.atComputed)
            ? o.copyWith(atVersions: versions)
            : o.copyWith(
                atComputed: rc, atVersions: versions, recalcCandidate: rc);
      }
      if (_numEq(rc, o.value)) continue; // converged
      if (!_numEq(rc, o.atComputed)) continue; // local derivation really changed
      overrides[e.key] = o;
    }

    return s.copyWith(
      versions: versions,
      explicitValues: explicit,
      summaryOverrides: overrides,
    );
  }

  /// An EXPLICIT user edit operation naming its target fields (kind X). Drops
  /// the overrides of the named fields in the same step, replaces their
  /// explicit entries, appends to the history ring and counts once (saturating
  /// at 64). Throws [ArgumentError] for an empty or invalid edit.
  static ActivitySession applyExplicitEdit(
      ActivitySession s, Map<String, double> edits) {
    if (edits.isEmpty) {
      throw ArgumentError('an edit must name at least one field');
    }
    for (final e in edits.entries) {
      final bound = kSummaryNumericBounds[e.key];
      if (bound == null) {
        throw ArgumentError('field ${e.key} cannot be edited');
      }
      if (!bound.accepts(e.value)) {
        throw ArgumentError('value for ${e.key} is out of range');
      }
    }
    var seq = 0;
    for (final x in s.explicitValues.values) {
      if (x.seq > seq) seq = x.seq;
    }
    for (final h in s.editHistory) {
      if (h.seq > seq) seq = h.seq;
    }
    seq += 1;
    final raw = derive(s);
    final explicit = {...s.explicitValues};
    final overrides = {...s.summaryOverrides};
    final userEdits = {...s.userEdits};
    final history = [...s.editHistory];
    final names = edits.keys.toList()..sort();
    for (final f in names) {
      final v = edits[f]!;
      explicit[f] = ExplicitValue(
        value: v,
        atDerived: raw[f],
        editDerived: raw[f],
        seq: seq,
      );
      overrides.remove(f);
      userEdits[f] = v;
      history.add(EditHistoryEntry(field: f, value: v, seq: seq));
    }
    final count = s.userEditCount + 1;
    return s.copyWith(
      explicitValues: explicit,
      summaryOverrides: overrides,
      userEdits: userEdits,
      editHistory: trimEditHistory(history),
      userEditCount: count > kUserEditCountCap ? kUserEditCountCap : count,
    );
  }

  /// Adopts a SERVER-ONLY change of [field] as an override (rule 1). Returns
  /// null when this device cannot recompute the field (no local value) or the
  /// server value is out of bound: the caller keeps a resolvable
  /// `sync_conflict`. No override is created when the value equals the local
  /// recomputation (an existing one is removed).
  static ActivitySession? adoptServerValue(
    ActivitySession s,
    String field,
    double serverValue,
    int serverRev, {
    CalcVersions? inForce,
  }) {
    final bound = kSummaryNumericBounds[field];
    if (bound == null || !bound.accepts(serverValue)) return null;
    final rc = recompute(s)[field];
    if (rc == null) return null;
    final overrides = {...s.summaryOverrides};
    if (_numEq(rc, serverValue)) {
      overrides.remove(field);
    } else {
      overrides[field] = SummaryOverride(
        value: serverValue,
        atComputed: rc,
        atVersions: inForce ?? CalcVersions.current,
        atRev: serverRev,
      );
    }
    return s.copyWith(summaryOverrides: overrides);
  }

  /// "Keep cloud" on a field the device cannot reproduce (rule 3): creates the
  /// override with `atComputed` = the value the device holds. Null when the
  /// device holds no value to compare.
  static ActivitySession keepCloudValue(
    ActivitySession s,
    String field,
    double serverValue,
    int serverRev, {
    CalcVersions? inForce,
  }) =>
      adoptServerValue(s, field, serverValue, serverRev, inForce: inForce) ??
      s;

  /// The choices offered for [field]: empty without a candidate; with an
  /// explicit value {useComputed, keepMine} plus useCloud when an override
  /// exists; with an override only {useComputed, useCloud}.
  static Set<CandidateChoice> offeredChoices(ActivitySession s, String field) {
    final ex = s.explicitValues[field];
    final ov = s.summaryOverrides[field];
    final hasCandidate = ex?.sourceCandidate != null || ov?.recalcCandidate != null;
    if (!hasCandidate) return const {};
    if (ex != null) {
      return {
        CandidateChoice.useComputed,
        CandidateChoice.keepMine,
        if (ov != null) CandidateChoice.useCloud,
      };
    }
    return {CandidateChoice.useComputed, CandidateChoice.useCloud};
  }

  /// Resolves the candidate of [field] as ONE atomic operation over the
  /// explicit value, the override and the candidate (design 3.2, GPT-PM round 9
  /// MAJOR-01L). The merge compares the chosen local value with the CURRENT
  /// [baseSummary] and [serverSummary]. Idempotent: a field without a candidate
  /// is returned unchanged with [ResolutionMerge.noWrite].
  static CandidateResolution resolveCandidate(
    ActivitySession s,
    String field,
    CandidateChoice choice, {
    required Map<String, Object?> baseSummary,
    required Map<String, Object?> serverSummary,
  }) {
    final ex = s.explicitValues[field];
    final ov = s.summaryOverrides[field];
    final cand = ex?.sourceCandidate ?? ov?.recalcCandidate;
    if (cand == null) {
      return CandidateResolution(s, ResolutionMerge.noWrite, field, null);
    }
    if (!offeredChoices(s, field).contains(choice)) {
      throw ArgumentError('choice $choice is not offered for $field');
    }
    final raw = derive(s)[field];
    final explicit = {...s.explicitValues};
    final overrides = {...s.summaryOverrides};
    double local;
    switch (choice) {
      case CandidateChoice.useComputed:
        explicit.remove(field);
        overrides.remove(field);
        local = cand;
      case CandidateChoice.keepMine:
        explicit[field] = ex!.copyWith(atDerived: raw, clearCandidate: true);
        overrides.remove(field);
        local = ex.value;
      case CandidateChoice.useCloud:
        explicit.remove(field);
        overrides[field] = ex != null
            ? ov!.copyWith(atComputed: raw, clearCandidate: true)
            : ov!.copyWith(clearCandidate: true);
        final next = s.copyWith(
          explicitValues: explicit,
          summaryOverrides: overrides,
        );
        return CandidateResolution(
            next, ResolutionMerge.noWrite, field, ov!.value);
    }
    final next = s.copyWith(
      explicitValues: explicit,
      summaryOverrides: overrides,
    );
    final server = serverSummary[field];
    final base = baseSummary[field];
    final ResolutionMerge merge;
    if (_numEq(server, local)) {
      merge = ResolutionMerge.noWrite;
    } else if (_numEq(server, base)) {
      merge = ResolutionMerge.write;
    } else {
      merge = ResolutionMerge.conflict;
    }
    return CandidateResolution(next, merge, field, local);
  }
}
