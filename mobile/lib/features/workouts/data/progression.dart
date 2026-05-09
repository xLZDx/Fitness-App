import 'workout_log.dart';

/// Pure progressive-overload solver. Given the user's last N logs of an
/// exercise, suggest the next-session weight.
///
/// Rules (linear progression with difficulty-aware adjustment):
///   1. No history → return null (UI shows "set your starting weight").
///   2. Last session rated `tooHard` → drop 5% (round to 2.5kg).
///   3. Last 3 sessions rated `tooEasy` AND hit rep target → bump 5%.
///   4. Last 2 sessions rated `justRight` AND hit rep target → bump
///      `defaultIncrement` (2.5 kg for compound, 1.25 kg for isolation).
///   5. Otherwise → repeat last weight.
///
/// This is the same shape Fitbod and Hevy Trainer use; adding the
/// difficulty signal (rule 2 + 3) is the unique twist — Freeletics reads
/// difficulty but doesn't apply progressive overload, Fitbod does
/// progression but ignores subjective effort.

class ProgressionSuggestion {
  const ProgressionSuggestion({
    required this.suggestedKg,
    required this.reason,
    required this.isDecrease,
  });

  final double suggestedKg;

  /// Human-readable explanation; surfaced in the UI as a small caption
  /// below the suggested weight ("Last 3 felt easy → +5%").
  final String reason;

  /// True when the suggestion is a deload (smaller than last session).
  /// UI shows in a different colour so the user notices.
  final bool isDecrease;
}

/// Default increment per category. Compound lifts (squat / bench / etc.)
/// advance in 2.5 kg jumps; small isolation work in 1.25 kg.
const _kDefaultCompoundJump = 2.5;
const _kDefaultIsolationJump = 1.25;

ProgressionSuggestion? suggestNextWeight({
  required List<WorkoutLogEntry> historyForExercise,
  int targetReps = 8,
  bool isCompound = true,
}) {
  // Most recent first; we only care about the last 3.
  final recent = historyForExercise.where((l) => l.weightKg != null).toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

  if (recent.isEmpty) return null;

  final last = recent.first;
  final lastKg = last.weightKg!;
  final increment = isCompound ? _kDefaultCompoundJump : _kDefaultIsolationJump;

  double round(double kg) => (kg / 2.5).round() * 2.5;

  // Rule 2 — too hard last time. Deload.
  if (last.difficulty == DifficultyRating.tooHard) {
    return ProgressionSuggestion(
      suggestedKg: round(lastKg * 0.95),
      reason: 'Last session felt too hard — back off 5% to recover.',
      isDecrease: true,
    );
  }

  final hitTarget = (last.repsCompleted ?? 0) >= targetReps;

  // Rule 3 — three sessions of "too easy" + made reps. Big bump.
  if (recent.length >= 3 &&
      recent.take(3).every((l) =>
          l.difficulty == DifficultyRating.tooEasy &&
          (l.repsCompleted ?? 0) >= targetReps)) {
    return ProgressionSuggestion(
      suggestedKg: round(lastKg * 1.05),
      reason: 'Last 3 felt easy and you hit reps — push 5% up.',
      isDecrease: false,
    );
  }

  // Rule 4 — two sessions of "just right" + made reps. Steady micro-bump.
  if (recent.length >= 2 &&
      recent.take(2).every((l) =>
          l.difficulty == DifficultyRating.justRight &&
          (l.repsCompleted ?? 0) >= targetReps)) {
    return ProgressionSuggestion(
      suggestedKg: round(lastKg + increment),
      reason: 'Made reps two sessions in a row — add ${increment} kg.',
      isDecrease: false,
    );
  }

  // Rule 5 — repeat last weight (didn't earn a jump yet).
  return ProgressionSuggestion(
    suggestedKg: lastKg,
    reason: hitTarget
        ? 'Repeat last weight — keep grinding the rep target.'
        : 'Repeat last weight — finish all reps before progressing.',
    isDecrease: false,
  );
}
