/// Summary numbers of one activity, all nullable and in canonical SI units
/// (design s31.1). Pace is DERIVED and never stored. Pure Dart, no Flutter
/// imports.
library;

class ActivitySummary {
  const ActivitySummary({
    this.distanceM,
    this.ascentM,
    this.descentM,
    this.avgHrBpm,
    this.maxHrBpm,
    this.avgSpeedMps,
    this.avgCadence,
    this.avgPowerW,
    this.normalizedPowerW,
    this.activeEnergyKcal,
    this.steps,
    this.strokeCount,
    this.poolLengthM,
    this.lapCount,
    this.avgSwolf,
    this.extras = const {},
  });

  /// Unknown JSON keys, kept so a round trip loses nothing (S02 design 3.3).
  final Map<String, dynamic> extras;

  final double? distanceM;
  final double? ascentM;
  final double? descentM;
  final double? avgHrBpm;
  final double? maxHrBpm;
  final double? avgSpeedMps;
  final double? avgCadence;
  final double? avgPowerW;
  final double? normalizedPowerW;
  final double? activeEnergyKcal;
  final double? steps;
  final double? strokeCount;
  final double? poolLengthM;
  final double? lapCount;
  final double? avgSwolf;

  static const empty = ActivitySummary();

  /// Field names, in a fixed order, to value. Used by the merger and JSON.
  Map<String, double?> toFieldMap() => {
        'distanceM': distanceM,
        'ascentM': ascentM,
        'descentM': descentM,
        'avgHrBpm': avgHrBpm,
        'maxHrBpm': maxHrBpm,
        'avgSpeedMps': avgSpeedMps,
        'avgCadence': avgCadence,
        'avgPowerW': avgPowerW,
        'normalizedPowerW': normalizedPowerW,
        'activeEnergyKcal': activeEnergyKcal,
        'steps': steps,
        'strokeCount': strokeCount,
        'poolLengthM': poolLengthM,
        'lapCount': lapCount,
        'avgSwolf': avgSwolf,
      };

  static ActivitySummary fromFieldMap(Map<String, double?> m) => ActivitySummary(
        distanceM: m['distanceM'],
        ascentM: m['ascentM'],
        descentM: m['descentM'],
        avgHrBpm: m['avgHrBpm'],
        maxHrBpm: m['maxHrBpm'],
        avgSpeedMps: m['avgSpeedMps'],
        avgCadence: m['avgCadence'],
        avgPowerW: m['avgPowerW'],
        normalizedPowerW: m['normalizedPowerW'],
        activeEnergyKcal: m['activeEnergyKcal'],
        steps: m['steps'],
        strokeCount: m['strokeCount'],
        poolLengthM: m['poolLengthM'],
        lapCount: m['lapCount'],
        avgSwolf: m['avgSwolf'],
      );

  /// Only set fields are written (missing optional fields read back as null).
  Map<String, dynamic> toJson() => {
        ...extras,
        for (final e in toFieldMap().entries)
          if (e.value != null) e.key: e.value,
      };

  static ActivitySummary fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final names = empty.toFieldMap().keys.toSet();
    final base = fromFieldMap({
      for (final n in names) n: raw[n] is num ? (raw[n] as num).toDouble() : null,
    });
    final extras = {
      for (final e in raw.entries)
        if (!names.contains(e.key)) e.key.toString(): e.value,
    };
    if (extras.isEmpty) return base;
    return base.withExtras(Map.unmodifiable(extras));
  }

  /// A copy carrying [extras] (used by the tolerant reader).
  ActivitySummary withExtras(Map<String, dynamic> extras) =>
      ActivitySummary(
        distanceM: distanceM,
        ascentM: ascentM,
        descentM: descentM,
        avgHrBpm: avgHrBpm,
        maxHrBpm: maxHrBpm,
        avgSpeedMps: avgSpeedMps,
        avgCadence: avgCadence,
        avgPowerW: avgPowerW,
        normalizedPowerW: normalizedPowerW,
        activeEnergyKcal: activeEnergyKcal,
        steps: steps,
        strokeCount: strokeCount,
        poolLengthM: poolLengthM,
        lapCount: lapCount,
        avgSwolf: avgSwolf,
        extras: extras,
      );
}
