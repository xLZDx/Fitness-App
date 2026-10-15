/// One weigh-in and the pure helpers that read a weight series (design s5.3,
/// s12.5, D-72). No Flutter imports; the Firestore mapping lives in `state/`.
library;

import '../../../core/math/series_math.dart';
import 'safety_clamps.dart';

/// Where a weigh-in came from. The last writer of a day wins.
enum WeightSource { manual, scan }

/// `users/{uid}/weight_entries/{yyyy-MM-dd}`: `{schema: 1, kg, at, source}`.
///
/// The document id is the LOCAL date of the measurement ([dayKey]); the maths
/// uses [at], not the key, so a timezone change that yields two entries on one
/// real day is harmless.
class WeightEntry {
  const WeightEntry({
    required this.at,
    required this.kg,
    this.source = WeightSource.manual,
  });

  final DateTime at;
  final double kg;
  final WeightSource source;

  /// True when [kg] is inside the plausible range (30..300) used everywhere.
  static bool isValidKg(double kg) =>
      kg.isFinite &&
      kg >= SafetyClamps.weightMinKg &&
      kg <= SafetyClamps.weightMaxKg;

  /// The document id: the local calendar day of [at], `yyyy-MM-dd`.
  String get dayKey => weightDayKey(at);

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'kg': kg,
        'at': at.toIso8601String(),
        'source': source.name,
      };

  /// Tolerant read: returns null for a document that cannot be a weigh-in
  /// (missing/odd `kg`, out-of-range weight, unreadable `at`). `at` may be a
  /// [DateTime], an ISO string or epoch milliseconds; an unknown `source`
  /// reads as manual.
  static WeightEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kg = raw['kg'];
    if (kg is! num || !isValidKg(kg.toDouble())) return null;
    final rawAt = raw['at'];
    DateTime? at;
    if (rawAt is DateTime) {
      at = rawAt;
    } else if (rawAt is String) {
      at = DateTime.tryParse(rawAt);
    } else if (rawAt is int) {
      at = DateTime.fromMillisecondsSinceEpoch(rawAt);
    }
    if (at == null) return null;
    final source = raw['source'] == WeightSource.scan.name
        ? WeightSource.scan
        : WeightSource.manual;
    return WeightEntry(at: at, kg: kg.toDouble(), source: source);
  }

  @override
  bool operator ==(Object other) =>
      other is WeightEntry &&
      other.at == at &&
      other.kg == kg &&
      other.source == source;

  @override
  int get hashCode => Object.hash(at, kg, source);
}

/// `yyyy-MM-dd` of [at] in its own (local) calendar.
String weightDayKey(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year.toString().padLeft(4, '0')}-${two(at.month)}-${two(at.day)}';
}

/// The newest entry no older than [maxAgeDays] at [now] (an age of exactly
/// [maxAgeDays] still counts), or null.
WeightEntry? latestWeightWithin(
  Iterable<WeightEntry> entries,
  DateTime now, {
  int maxAgeDays = SafetyClamps.currentWeightFreshDays,
}) {
  WeightEntry? best;
  for (final e in entries) {
    final ageMinutes = now.difference(e.at).inMinutes;
    if (ageMinutes > maxAgeDays * 1440) continue;
    if (best == null || e.at.isAfter(best.at)) best = e;
  }
  return best;
}

/// Weekly weight slope in kg/week by Theil-Sen on the raw entries of the last
/// 21 days, requiring at least 3 entries spanning at least 7 days; null means
/// "not enough data".
double? weightSlopeKgPerWeek(
  Iterable<WeightEntry> entries, {
  DateTime? asOf,
}) =>
    theilSenSlopePerWeek(
      [for (final e in entries) SeriesPoint(e.at, e.kg)],
      asOf: asOf,
    );

/// Smoothed weight trend (tau 7 days, plain exponential weight) at the newest
/// entry, or null for an empty series.
double? smoothedWeightKg(Iterable<WeightEntry> entries) {
  final series = ewmaSeries(
    [for (final e in entries) SeriesPoint(e.at, e.kg)],
    tauDays: kWeightTauDays,
  );
  return series.isEmpty ? null : series.last;
}

/// Weight smoothing time constant in days [OWN].
const double kWeightTauDays = 7;
