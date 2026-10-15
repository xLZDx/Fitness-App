/// One lap or interval of an activity (design s31.1). Pure Dart, no Flutter
/// imports.
library;

enum LapKind {
  auto,
  manual,
  poolLength,
  interval;

  static LapKind parse(Object? name) {
    if (name is String) {
      for (final k in values) {
        if (k.name == name) return k;
      }
    }
    return LapKind.auto;
  }
}

enum StrokeType {
  free,
  back,
  breast,
  fly,
  mixed;

  static StrokeType? parse(Object? name) {
    if (name is! String) return null;
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

class Lap {
  const Lap({
    required this.index,
    required this.kind,
    required this.startOffsetS,
    required this.durationS,
    this.distanceM,
    this.avgHrBpm,
    this.strokeCount,
    this.strokeType,
  });

  final int index;
  final LapKind kind;
  final double startOffsetS;
  final double durationS;
  final double? distanceM;
  final double? avgHrBpm;
  final int? strokeCount;
  final StrokeType? strokeType;

  Map<String, dynamic> toJson() => {
        'index': index,
        'kind': kind.name,
        'startOffsetS': startOffsetS,
        'durationS': durationS,
        if (distanceM != null) 'distanceM': distanceM,
        if (avgHrBpm != null) 'avgHrBpm': avgHrBpm,
        if (strokeCount != null) 'strokeCount': strokeCount,
        if (strokeType != null) 'strokeType': strokeType!.name,
      };

  /// Tolerant read; unknown keys are ignored. Null when index or timing are
  /// unreadable.
  static Lap? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['index'];
    final start = raw['startOffsetS'];
    final dur = raw['durationS'];
    if (index is! num || start is! num || dur is! num) return null;
    double? d(Object? v) => v is num ? v.toDouble() : null;
    final strokes = raw['strokeCount'];
    return Lap(
      index: index.toInt(),
      kind: LapKind.parse(raw['kind']),
      startOffsetS: start.toDouble(),
      durationS: dur.toDouble(),
      distanceM: d(raw['distanceM']),
      avgHrBpm: d(raw['avgHrBpm']),
      strokeCount: strokes is num ? strokes.toInt() : null,
      strokeType: StrokeType.parse(raw['strokeType']),
    );
  }
}
