/// Schema and calculation-version constants of the persisted activity record
/// (S02 design 3.3, A-5 provenance fields). Pure Dart, no Flutter imports.
library;

/// The schema this build writes. `schema = 1` records are read through the
/// migration chain; a record above this value is read-only (never written back
/// at a lower schema).
const int kActivitySchema = 2;

/// Version strings written into new records (A-5). Each is at most 32 chars
/// (the cloud summary bound, design 3.2).
const String kFormulaVersion = 'formula-1';
const String kMetricDefinitionVersion = 'metrics-1';
const String kThresholdPolicyVersion = 'thresholds-1';

/// Maximum length of the three calculation-version strings in the summary.
const int kMaxVersionStringLength = 32;

/// Maximum length of `sourceTermsSnapshot` (a terms-version id or hash).
const int kMaxSourceTermsSnapshotLength = 64;

/// The saturation cap of `userEditCount` (rules range 0..64, design 3.2).
const int kUserEditCountCap = 64;

/// Size of the device-only `userEdits` history ring (newest entries kept).
const int kUserEditsRingSize = 64;

/// The triple of calculation versions in force (design 3.2 rule 2).
class CalcVersions {
  const CalcVersions({
    this.formulaVersion = kFormulaVersion,
    this.metricDefinitionVersion = kMetricDefinitionVersion,
    this.thresholdPolicyVersion = kThresholdPolicyVersion,
  });

  /// The versions this build computes with.
  static const CalcVersions current = CalcVersions();

  final String formulaVersion;
  final String metricDefinitionVersion;
  final String thresholdPolicyVersion;

  Map<String, String> toJson() => {
        'formulaVersion': formulaVersion,
        'metricDefinitionVersion': metricDefinitionVersion,
        'thresholdPolicyVersion': thresholdPolicyVersion,
      };

  /// Null unless all three are non-empty strings (a missing triple cannot be
  /// compared).
  static CalcVersions? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final f = raw['formulaVersion'];
    final m = raw['metricDefinitionVersion'];
    final t = raw['thresholdPolicyVersion'];
    if (f is! String || m is! String || t is! String) return null;
    if (f.isEmpty || m.isEmpty || t.isEmpty) return null;
    return CalcVersions(
      formulaVersion: f,
      metricDefinitionVersion: m,
      thresholdPolicyVersion: t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalcVersions &&
      other.formulaVersion == formulaVersion &&
      other.metricDefinitionVersion == metricDefinitionVersion &&
      other.thresholdPolicyVersion == thresholdPolicyVersion;

  @override
  int get hashCode =>
      Object.hash(formulaVersion, metricDefinitionVersion, thresholdPolicyVersion);
}
