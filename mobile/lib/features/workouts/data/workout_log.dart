/// User's perceived effort on a completed set. Read by the recommendation
/// pipeline (`exercise_filter.dart`) + `progression.dart` to nudge tier-fit
/// ordering and next-session weight in the right direction. Freeletics'
/// AI Coach reads a similar signal; nobody else in the top-20 does.
enum DifficultyRating {
  tooEasy,
  justRight,
  tooHard,
}

extension DifficultyRatingX on DifficultyRating {
  /// −1 / 0 / +1 — the only form the recommendation model needs.
  int get score {
    switch (this) {
      case DifficultyRating.tooEasy:
        return -1;
      case DifficultyRating.justRight:
        return 0;
      case DifficultyRating.tooHard:
        return 1;
    }
  }
}

/// One completed workout, written when the user taps "Mark complete" on
/// the workout player. The exercise title is denormalised so the progress
/// tab can render history without re-fetching the catalog (and so logs
/// keep their human-readable label even if a curated exercise is later
/// renamed or removed).
class WorkoutLogEntry {
  const WorkoutLogEntry({
    required this.id,
    required this.exerciseId,
    required this.exerciseTitle,
    required this.completedAt,
    required this.durationMinutes,
    this.notes,
    this.weightKg,
    this.repsCompleted,
    this.difficulty,
  });

  final String id;
  final String exerciseId;
  final String exerciseTitle;
  final DateTime completedAt;
  final int durationMinutes;
  final String? notes;

  /// Working weight on the bar (or selectorized cable stack). Optional —
  /// some exercises (mobility, body-weight work) don't carry a load.
  final double? weightKg;

  /// Reps actually completed on the working set. Used by progression to
  /// detect "made the rep target".
  final int? repsCompleted;

  /// User's post-workout perceived-effort rating. The progression engine
  /// reads this; the recommendation pipeline re-ranks tier-fit on the
  /// rolling average.
  final DifficultyRating? difficulty;

  WorkoutLogEntry copyWith({
    String? id,
    String? exerciseId,
    String? exerciseTitle,
    DateTime? completedAt,
    int? durationMinutes,
    String? notes,
    double? weightKg,
    int? repsCompleted,
    DifficultyRating? difficulty,
  }) =>
      WorkoutLogEntry(
        id: id ?? this.id,
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseTitle: exerciseTitle ?? this.exerciseTitle,
        completedAt: completedAt ?? this.completedAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        notes: notes ?? this.notes,
        weightKg: weightKg ?? this.weightKg,
        repsCompleted: repsCompleted ?? this.repsCompleted,
        difficulty: difficulty ?? this.difficulty,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'exerciseTitle': exerciseTitle,
        'completedAt': completedAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        if (notes != null) 'notes': notes,
        if (weightKg != null) 'weightKg': weightKg,
        if (repsCompleted != null) 'repsCompleted': repsCompleted,
        if (difficulty != null) 'difficulty': difficulty!.name,
      };

  factory WorkoutLogEntry.fromJson(Map<String, dynamic> j) {
    final raw = j['completedAt'];
    DateTime completedAt;
    if (raw is String) {
      completedAt = DateTime.parse(raw);
    } else if (raw is DateTime) {
      completedAt = raw;
    } else {
      // Firestore Timestamp; we don't import the type here to keep the
      // model layer free of Firebase deps. Repos convert before calling.
      throw ArgumentError(
          'completedAt must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
    }
    DifficultyRating? difficulty;
    final dn = j['difficulty'] as String?;
    if (dn != null) {
      for (final r in DifficultyRating.values) {
        if (r.name == dn) {
          difficulty = r;
          break;
        }
      }
    }
    return WorkoutLogEntry(
      id: j['id'] as String,
      exerciseId: j['exerciseId'] as String,
      exerciseTitle: j['exerciseTitle'] as String? ?? j['exerciseId'] as String,
      completedAt: completedAt,
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      notes: j['notes'] as String?,
      weightKg: (j['weightKg'] as num?)?.toDouble(),
      repsCompleted: (j['repsCompleted'] as num?)?.toInt(),
      difficulty: difficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutLogEntry &&
          other.id == id &&
          other.exerciseId == exerciseId &&
          other.exerciseTitle == exerciseTitle &&
          other.completedAt == completedAt &&
          other.durationMinutes == durationMinutes &&
          other.notes == notes &&
          other.weightKg == weightKg &&
          other.repsCompleted == repsCompleted &&
          other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(id, exerciseId, exerciseTitle, completedAt,
      durationMinutes, notes, weightKg, repsCompleted, difficulty);
}
