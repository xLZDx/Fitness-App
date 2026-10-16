/// The tolerant schema migration chain of a persisted activity record (S02
/// design 3.3). Pure Dart, no Flutter imports.
///
/// One pure, total step per version. A step never throws; unknown keys stay in
/// the map (and so end up in `extras` when read). A record newer than
/// [kActivitySchema] is returned untouched (read-only: unknown keys preserved,
/// never rewritten at a lower schema). `ActivitySession.tryFromJson` is the
/// final stage.
library;

import 'activity_session.dart';
import 'activity_versions.dart';
import 'summary_fields.dart';

class ActivityMigration {
  const ActivityMigration._();

  /// The migration steps, indexed by the schema they upgrade FROM.
  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
      _steps = {1: _v1ToV2};

  /// Migrates [raw] to [kActivitySchema]. Anything that is not a map yields an
  /// empty map (which `tryFromJson` then rejects). Never throws.
  static Map<String, dynamic> migrate(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    Map<String, dynamic> current;
    try {
      current = {for (final e in raw.entries) e.key.toString(): e.value};
    } catch (_) {
      return <String, dynamic>{};
    }
    var version = schemaOf(current);
    if (version > kActivitySchema) return current;
    while (version < kActivitySchema) {
      final step = _steps[version];
      if (step != null) {
        try {
          current = step(current);
        } catch (_) {
          // A step is total by contract; if one ever fails keep the input and
          // only advance the version number so the chain terminates.
        }
      }
      version += 1;
      current['schema'] = version;
    }
    return current;
  }

  /// Migrates and reads in one call; null for an unreadable record.
  static ActivitySession? read(Object? raw) =>
      ActivitySession.tryFromJson(migrate(raw));

  /// The schema number of a raw map (missing or unreadable means 1).
  static int schemaOf(Map<dynamic, dynamic> raw) {
    final s = raw['schema'];
    if (s is num && s.isFinite) {
      final n = s.toInt();
      return n < 1 ? 1 : n;
    }
    return 1;
  }

  /// Schema 1 -> 2: adds the A-5 provenance strings (defaulted to the
  /// constants of this build) and the saturating edit counter. Everything else
  /// is kept as is.
  static Map<String, dynamic> _v1ToV2(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.of(m);
    void fill(String key, String fallback) {
      final v = out[key];
      if (v is! String || !kVersionStringPattern.hasMatch(v)) {
        out[key] = fallback;
      }
    }

    fill('formulaVersion', kFormulaVersion);
    fill('metricDefinitionVersion', kMetricDefinitionVersion);
    fill('thresholdPolicyVersion', kThresholdPolicyVersion);
    out.putIfAbsent('userEditCount', () => 0);
    return out;
  }
}
