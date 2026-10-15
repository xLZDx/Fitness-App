/// The sport-agnostic activity vocabulary (design s31.1). Pure Dart, no Flutter
/// imports.
library;

enum SportType {
  running,
  trailRunning,
  walking,
  hiking,
  cycling,
  indoorCycling,
  mountainBiking,
  swimmingPool,
  swimmingOpenWater,
  rowing,
  strength,
  other;

  /// Unknown names degrade to [other] (extendable vocabulary).
  static SportType parse(Object? name) {
    if (name is String) {
      for (final s in values) {
        if (s.name == name) return s;
      }
    }
    return SportType.other;
  }

  /// Sports that may be the SAME workout recorded by two sources: equal, or in
  /// one family (running/trailRunning, cycling/indoorCycling/mountainBiking).
  /// Pool and open-water swimming are NEVER merged with each other.
  bool compatibleWith(SportType o) {
    if (this == o) return true;
    return _family(this) != null && _family(this) == _family(o);
  }

  static int? _family(SportType s) => switch (s) {
        SportType.running || SportType.trailRunning => 1,
        SportType.cycling ||
        SportType.indoorCycling ||
        SportType.mountainBiking =>
          2,
        _ => null,
      };
}
