/// TX.3 — Buddy Matching.
///
/// In-gym presence sharing via BLE: two phones in the same building
/// scanning a public service-UUID can pair into a "buddy session" and
/// share rest-timer / set-completion events. No server hop required;
/// the server only stores the consent record + post-session summary.
class BuddyProfile {
  const BuddyProfile({
    required this.uid,
    required this.displayName,
    required this.gymId,
    required this.experienceLevel,
    required this.preferredGoals,
    this.lastSeenAt,
    this.shareableMetrics = const {},
  });

  final String uid;
  final String displayName;
  final String gymId;
  final String experienceLevel; // 'beginner' | 'intermediate' | 'advanced'
  final List<String> preferredGoals;
  final DateTime? lastSeenAt;

  /// Metrics the user opted to share with their buddy. Keys: 'currentSet',
  /// 'restTimer', 'workoutTitle'. Default off — explicit opt-in only.
  final Map<String, bool> shareableMetrics;
}

class BuddyMatchScore {
  const BuddyMatchScore({
    required this.profile,
    required this.score,
    required this.reasons,
  });

  final BuddyProfile profile;
  final double score; // 0..1
  final List<String> reasons;
}

/// Pure scoring function — same gym + same experience level + at least
/// one shared goal scores highest. Higher is better.
List<BuddyMatchScore> rankBuddies(
  BuddyProfile self,
  Iterable<BuddyProfile> candidates,
) {
  final out = <BuddyMatchScore>[];
  for (final c in candidates) {
    if (c.uid == self.uid) continue;
    if (c.gymId != self.gymId) continue;

    var score = 0.0;
    final reasons = <String>[];

    score += 0.4;
    reasons.add('Same gym');

    if (c.experienceLevel == self.experienceLevel) {
      score += 0.3;
      reasons.add('Same experience level');
    }

    final shared = c.preferredGoals
        .toSet()
        .intersection(self.preferredGoals.toSet());
    if (shared.isNotEmpty) {
      score += 0.3 * (shared.length / self.preferredGoals.length).clamp(0, 1);
      reasons.add('Shared goal: ${shared.first.replaceAll('_', ' ')}');
    }
    out.add(BuddyMatchScore(profile: c, score: score, reasons: reasons));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}
