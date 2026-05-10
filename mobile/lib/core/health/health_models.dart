/// Cross-platform health-data primitives.
///
/// Stays platform-neutral so the same models flow through Android Health
/// Connect, iOS HealthKit, and the in-memory mock used by tests. Adding
/// a new platform = a new HealthService impl, no model changes.
class HealthSnapshot {
  const HealthSnapshot({
    required this.dateUtc,
    this.steps,
    this.activeMinutes,
    this.restingHeartRateBpm,
    this.sleepScore,
    this.hrvMs,
    this.activityRingPercent,
  });

  /// Calendar day (UTC midnight) the snapshot covers.
  final DateTime dateUtc;

  final int? steps;
  final int? activeMinutes;
  final int? restingHeartRateBpm;

  /// 0–100 scaled sleep quality. Apple's "sleep stages" + Android's
  /// "sleep session" both reduce to this.
  final int? sleepScore;

  /// Heart-rate variability (RMSSD-style milliseconds). Surfaced when
  /// the platform exposes a daily aggregate.
  final double? hrvMs;

  /// Apple "activity ring" close percentage / Google Fit "move minutes"
  /// progress, normalised 0–100.
  final int? activityRingPercent;

  Map<String, dynamic> toJson() => {
        'dateUtc': dateUtc.toIso8601String(),
        if (steps != null) 'steps': steps,
        if (activeMinutes != null) 'activeMinutes': activeMinutes,
        if (restingHeartRateBpm != null)
          'restingHeartRateBpm': restingHeartRateBpm,
        if (sleepScore != null) 'sleepScore': sleepScore,
        if (hrvMs != null) 'hrvMs': hrvMs,
        if (activityRingPercent != null)
          'activityRingPercent': activityRingPercent,
      };
}

/// Workout written *to* the health platform (so it lands in Apple's
/// activity ring / Google Fit's history).
class HealthWorkoutWrite {
  const HealthWorkoutWrite({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
    this.estimatedCalories,
  });

  final String id;
  final String title;
  final DateTime startedAt;
  final int durationMinutes;
  final int? estimatedCalories;
}

enum HealthAuthStatus {
  /// Permission was granted (or the platform doesn't require explicit
  /// permission, which is the case for iOS read-only metrics in some
  /// configurations).
  granted,

  /// User explicitly declined.
  denied,

  /// Permission has not been requested yet.
  notDetermined,

  /// Platform doesn't support health data (web, desktop, OS too old).
  unsupported,
}
