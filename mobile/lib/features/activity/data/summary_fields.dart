/// The cloud-summary field vocabulary of S02 design 3.2: the key allowlist and
/// the numeric bounds. This is the single source of the allowlist; the rules
/// file `firestore.rules` must carry the same keys and bounds (a parity test
/// parses the rules and compares). Pure Dart, no Flutter imports.
library;

/// Inclusive numeric bounds of one summary key.
class FieldBound {
  const FieldBound(this.min, this.max);

  final double min;
  final double max;

  bool accepts(num v) => v.isFinite && v >= min && v <= max;
}

/// Numeric summary keys that the app derives from the session and that may
/// carry an explicit user value or a cloud override (design 3.2 table).
const Map<String, FieldBound> kSummaryNumericBounds = {
  'movingTimeS': FieldBound(0, 604800),
  'distanceM': FieldBound(0, 10000000),
  'ascentM': FieldBound(0, 100000),
  'descentM': FieldBound(0, 100000),
  'avgSpeedMps': FieldBound(0, 120),
  'avgCadence': FieldBound(0, 400),
  'avgPowerW': FieldBound(0, 5000),
  'normalizedPowerW': FieldBound(0, 5000),
  'activeEnergyKcal': FieldBound(0, 50000),
  'steps': FieldBound(0, 1000000),
  'strokeCount': FieldBound(0, 100000),
  'poolLengthM': FieldBound(0, 1000),
  'lapCount': FieldBound(0, 1000),
  'avgSwolf': FieldBound(0, 300),
  'routeTrimMeters': FieldBound(0, 2000),
};

/// Fields a user edit or a cloud override may name.
final Set<String> kOverridableSummaryFields =
    Set.unmodifiable(kSummaryNumericBounds.keys);

/// Integer-valued summary keys with their bounds.
const Map<String, FieldBound> kSummaryIntBounds = {
  'schema': FieldBound(1, 1000),
  'utcOffsetMinutes': FieldBound(-840, 840),
  'sourceCount': FieldBound(0, 64),
  'userEditCount': FieldBound(0, 64),
  'mergeNoteCount': FieldBound(0, 64),
  'rev': FieldBound(1, 1000000),
};

/// Keys the summary document must always carry (design 3.2, 4).
const List<String> kSummaryRequiredKeys = [
  'schema',
  'sport',
  'startUtc',
  'endUtc',
  'rev',
];

/// Keys that never take part in change detection or the three-way merge:
/// `rev` orders writes and `updatedAt` is a client-clock hint only.
const Set<String> kSummaryBookkeepingKeys = {'rev', 'updatedAt'};

/// Keys that are immutable after creation (they feed the deterministic id).
const Set<String> kSummaryImmutableKeys = {'startUtc', 'sport'};

/// The complete allowlist of keys of `users/{uid}/activities/{id}`.
final Set<String> kSummaryAllowedKeys = Set.unmodifiable({
  ...kSummaryNumericBounds.keys,
  ...kSummaryIntBounds.keys,
  'sport',
  'startUtc',
  'endUtc',
  'primarySourceId',
  'primarySourceKind',
  'hasRoute',
  'formulaVersion',
  'metricDefinitionVersion',
  'thresholdPolicyVersion',
  'sourceTermsSnapshot',
  'updatedAt',
});

/// Shape of `sport` in the summary (open pattern, design 3.2).
final RegExp kSummarySportPattern = RegExp(r'^[a-z][A-Za-z0-9]{0,31}$');

/// Shape of the A-5 strings. Whitespace is not allowed, so terms text cannot
/// be smuggled through `sourceTermsSnapshot`.
final RegExp kVersionStringPattern = RegExp(r'^[A-Za-z0-9._:-]{1,32}$');
final RegExp kSourceTermsPattern = RegExp(r'^[A-Za-z0-9._:+/=-]{1,64}$');
