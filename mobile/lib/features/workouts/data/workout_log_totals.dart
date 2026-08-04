/// The two numbers about a workout history that a recent window cannot answer.
///
/// ## Why this type exists
///
/// The history listener used to be unbounded: `orderBy('completedAt').snapshots()`
/// with no limit, attached on the landing screen, so every cold start re-read
/// every workout the user had ever logged. That cost grows with how long
/// someone has been a customer rather than with how many people are using the
/// app at once, which makes it the one thing here that gets worse precisely as
/// the product succeeds.
///
/// Windowing the listener is the fix, and the trap is that two of the numbers
/// on screen are genuinely all-time: the workouts counter on Home and Progress
/// (`ProgressStats.total`) and the longest-streak record. Adding `.limit()`
/// and letting those keep deriving from the visible rows would have quietly
/// changed what they mean — a user with three years of history would watch
/// their total drop to the window size and their record shrink. A silently
/// wrong number is worse than the read cost it saves.
///
/// So the window answers everything derived from recent activity, and this
/// answers the two that are not.
class WorkoutLogTotals {
  const WorkoutLogTotals({
    required this.total,
    required this.longestStreakDays,
  });

  /// Every workout ever logged, counted server-side.
  ///
  /// Exact rather than accumulated. Firestore's aggregation query bills one
  /// read per 1,000 documents and returns a count without transferring the
  /// documents, so this is both cheaper than reading the collection and
  /// immune to the drift a stored counter develops the first time a write
  /// fails halfway.
  final int total;

  /// The longest run of consecutive days ever recorded, as a high-water mark.
  ///
  /// A record can only be *set* while the days that make it are in the window,
  /// which is when it gets written down. It can never be lowered afterwards,
  /// which is what "record" means and is why a high-water mark is the right
  /// shape rather than a recomputation.
  final int longestStreakDays;

  static const zero = WorkoutLogTotals(total: 0, longestStreakDays: 0);

  WorkoutLogTotals copyWith({int? total, int? longestStreakDays}) =>
      WorkoutLogTotals(
        total: total ?? this.total,
        longestStreakDays: longestStreakDays ?? this.longestStreakDays,
      );

  Map<String, dynamic> toJson() => {
        'total': total,
        'longestStreakDays': longestStreakDays,
      };

  factory WorkoutLogTotals.fromJson(Map<String, dynamic> json) =>
      WorkoutLogTotals(
        total: (json['total'] as num?)?.toInt() ?? 0,
        longestStreakDays: (json['longestStreakDays'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is WorkoutLogTotals &&
      other.total == total &&
      other.longestStreakDays == longestStreakDays;

  @override
  int get hashCode => Object.hash(total, longestStreakDays);

  @override
  String toString() =>
      'WorkoutLogTotals(total: $total, longestStreakDays: $longestStreakDays)';
}
