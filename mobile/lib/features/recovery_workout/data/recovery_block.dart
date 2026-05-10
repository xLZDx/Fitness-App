/// MK.7 — Recovery as a first-class workout.
///
/// Reframes the brand: instead of grinding the user, we dignify
/// rest as programming. A "recovery block" is a structured session
/// (mobility / breathwork / zone-2 / yoga / sauna time) the user can
/// schedule + log just like a strength workout.
class RecoveryBlock {
  const RecoveryBlock({
    required this.id,
    required this.title,
    required this.kind,
    required this.durationMinutes,
    required this.description,
    this.heartRateGuidance,
    this.intensityFactor = 0.4,
  });

  final String id;
  final String title;
  final RecoveryKind kind;
  final int durationMinutes;
  final String description;

  /// Optional — when wearables are connected, surface a target HR band.
  final HeartRateGuidance? heartRateGuidance;

  /// 0..1 perceived effort multiplier. Used by the deload detector so
  /// recovery blocks don't push the difficulty trend up.
  final double intensityFactor;
}

enum RecoveryKind {
  mobility,
  breathwork,
  zone2Cardio,
  yoga,
  sauna,
  walk,
  meditation,
}

class HeartRateGuidance {
  const HeartRateGuidance({required this.minBpm, required this.maxBpm});
  final int minBpm;
  final int maxBpm;
}
