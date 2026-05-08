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
  });

  final String id;
  final String exerciseId;
  final String exerciseTitle;
  final DateTime completedAt;
  final int durationMinutes;
  final String? notes;

  WorkoutLogEntry copyWith({
    String? id,
    String? exerciseId,
    String? exerciseTitle,
    DateTime? completedAt,
    int? durationMinutes,
    String? notes,
  }) =>
      WorkoutLogEntry(
        id: id ?? this.id,
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseTitle: exerciseTitle ?? this.exerciseTitle,
        completedAt: completedAt ?? this.completedAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'exerciseTitle': exerciseTitle,
        'completedAt': completedAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        if (notes != null) 'notes': notes,
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
    return WorkoutLogEntry(
      id: j['id'] as String,
      exerciseId: j['exerciseId'] as String,
      exerciseTitle: j['exerciseTitle'] as String? ?? j['exerciseId'] as String,
      completedAt: completedAt,
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      notes: j['notes'] as String?,
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
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
      id, exerciseId, exerciseTitle, completedAt, durationMinutes, notes);
}
