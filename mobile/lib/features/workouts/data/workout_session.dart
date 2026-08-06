import 'set_capture.dart';
import 'workout_log.dart' show DifficultyRating, WorkoutLogEntry;

/// F3.1 — see `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`.
///
/// A session can outlive one build/close of the app (start it, get
/// interrupted, come back), so [completedAt] is nullable and [status] is
/// explicit rather than inferred from "is completedAt set" — the same
/// distinction [WorkoutLogEntry] never needed (it is written once, at
/// completion, atomically) and `ScheduledSession` already makes.
enum WorkoutSessionStatus { pending, completed, abandoned }

extension WorkoutSessionStatusX on WorkoutSessionStatus {
  static WorkoutSessionStatus parse(String? name) =>
      WorkoutSessionStatus.values.firstWhere((s) => s.name == name,
          orElse: () => WorkoutSessionStatus.pending);
}

/// One exercise within a [WorkoutSession].
///
/// Deliberately NOT the catalog's `ExerciseItem` embedded here: that type
/// carries video/poster/steps/contraindications — the full catalog row, not
/// a completion record. Embedding it would bake stale catalog data into
/// every session and blow the document budget for no benefit. This mirrors
/// why `WorkoutLogEntry` denormalises `exerciseTitle` rather than storing an
/// `ExerciseItem` reference (`workout_log.dart`): a completion record must
/// keep meaning what it meant even after the catalog entry is renamed or
/// removed.
class WorkoutSessionExercise {
  const WorkoutSessionExercise({
    required this.exerciseId,
    required this.exerciseTitle,
    this.groupId,
    this.sets = const [],
    this.difficulty,
  });

  final String exerciseId;
  final String exerciseTitle;

  /// Superset grouping. Nullable and unused today — added now because
  /// retrofitting a group key onto a flat list after the fact is the
  /// expensive version of this change; adding an unused nullable field is
  /// not.
  final String? groupId;

  /// One [SetCapture] per set actually performed. Replaces the single
  /// weight/reps pair `WorkoutLogEntry` carries — `SetCaptureSheet` already
  /// captures one pair per set; a session with multiple sets per exercise
  /// needs the list, not the pair, or later sets silently overwrite earlier
  /// ones.
  final List<SetCapture> sets;
  final DifficultyRating? difficulty;

  WorkoutSessionExercise copyWith({
    String? exerciseId,
    String? exerciseTitle,
    String? groupId,
    List<SetCapture>? sets,
    DifficultyRating? difficulty,
  }) =>
      WorkoutSessionExercise(
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseTitle: exerciseTitle ?? this.exerciseTitle,
        groupId: groupId ?? this.groupId,
        sets: sets ?? this.sets,
        difficulty: difficulty ?? this.difficulty,
      );

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseTitle': exerciseTitle,
        if (groupId != null) 'groupId': groupId,
        'sets': sets
            .map((s) => {
                  if (s.weightKg != null) 'weightKg': s.weightKg,
                  if (s.reps != null) 'reps': s.reps,
                })
            .toList(),
        if (difficulty != null) 'difficulty': difficulty!.name,
      };

  factory WorkoutSessionExercise.fromJson(Map<String, dynamic> j) {
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
    final rawSets = j['sets'] as List<dynamic>? ?? const [];
    return WorkoutSessionExercise(
      exerciseId: j['exerciseId'] as String,
      exerciseTitle: j['exerciseTitle'] as String? ?? j['exerciseId'] as String,
      groupId: j['groupId'] as String?,
      sets: rawSets.map((raw) {
        final m = raw as Map<String, dynamic>;
        return (
          weightKg: (m['weightKg'] as num?)?.toDouble(),
          reps: (m['reps'] as num?)?.toInt(),
        );
      }).toList(),
      difficulty: difficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSessionExercise &&
          other.exerciseId == exerciseId &&
          other.exerciseTitle == exerciseTitle &&
          other.groupId == groupId &&
          _listEquals(other.sets, sets) &&
          other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(
      exerciseId, exerciseTitle, groupId, Object.hashAll(sets), difficulty);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One workout, one or more exercises. Written when the user starts a
/// workout (`status: pending`) and updated on completion or abandonment.
///
/// Backfilled from every existing [WorkoutLogEntry] (F3.3) as a one-exercise,
/// already-`completed` session — see the plan doc for why that backfill is
/// additive (`workout_logs` is never rewritten) rather than a live migration.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.title,
    required this.exercises,
    required this.startedAt,
    this.completedAt,
    this.status = WorkoutSessionStatus.pending,
    this.durationMinutes,
    this.notes,
  });

  final String id;
  final String title;
  final List<WorkoutSessionExercise> exercises;
  final DateTime startedAt;

  /// Null until [status] is `completed`. A session can be interrupted; a
  /// required completion time would force every unfinished session to lie
  /// about one.
  final DateTime? completedAt;
  final WorkoutSessionStatus status;

  /// Derived once completed. Not required earlier, unlike
  /// `WorkoutLogEntry.durationMinutes`, which is only ever written once, at
  /// completion.
  final int? durationMinutes;
  final String? notes;

  WorkoutSession copyWith({
    String? id,
    String? title,
    List<WorkoutSessionExercise>? exercises,
    DateTime? startedAt,
    DateTime? completedAt,
    WorkoutSessionStatus? status,
    int? durationMinutes,
    String? notes,
  }) =>
      WorkoutSession(
        id: id ?? this.id,
        title: title ?? this.title,
        exercises: exercises ?? this.exercises,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'startedAt': startedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'status': status.name,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (notes != null) 'notes': notes,
      };

  static DateTime _parseDate(dynamic raw, String field) {
    if (raw is String) return DateTime.parse(raw);
    if (raw is DateTime) return raw;
    // Firestore Timestamp; kept out of the model layer's imports, same
    // convention as WorkoutLogEntry.fromJson -- repos convert before calling.
    throw ArgumentError(
        '$field must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
  }

  factory WorkoutSession.fromJson(Map<String, dynamic> j) {
    final rawCompleted = j['completedAt'];
    return WorkoutSession(
      id: j['id'] as String,
      title: j['title'] as String,
      exercises: (j['exercises'] as List<dynamic>? ?? const [])
          .map(
              (e) => WorkoutSessionExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      startedAt: _parseDate(j['startedAt'], 'startedAt'),
      completedAt:
          rawCompleted == null ? null : _parseDate(rawCompleted, 'completedAt'),
      status: WorkoutSessionStatusX.parse(j['status'] as String?),
      durationMinutes: (j['durationMinutes'] as num?)?.toInt(),
      notes: j['notes'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSession &&
          other.id == id &&
          other.title == title &&
          _listEquals(other.exercises, exercises) &&
          other.startedAt == startedAt &&
          other.completedAt == completedAt &&
          other.status == status &&
          other.durationMinutes == durationMinutes &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(exercises),
      startedAt, completedAt, status, durationMinutes, notes);
}

/// F3.3 read-convergence adapter: lets every existing consumer that reads
/// workout history stay typed against [WorkoutLogEntry] -- `progress_stats`,
/// `suggestion_builder`, `progression`, `deload_detector`, `fitness_model`,
/// and the GDPR data export -- while the actual data source moves to
/// [WorkoutSession]. Rewriting those five pure functions to accept
/// [WorkoutSession] directly was the alternative; this adapter was chosen
/// because it is additive to already-reviewed code instead of touching it.
///
/// Valid only because every session today holds exactly one exercise and at
/// most one set -- the same constraint F3.4 keeps until a future gate (R3+)
/// builds real multi-exercise logging (see the plan doc). A session with >1
/// exercise, or an exercise with >1 set, loses information through this
/// view (only the first exercise and the last set survive) -- silently
/// correct today, silently lossy the day that constraint stops holding.
/// Whoever builds multi-exercise sessions must replace this adapter's call
/// sites with real [WorkoutSession]-typed reads, not widen it.
extension WorkoutSessionLogView on WorkoutSession {
  WorkoutLogEntry asLogEntryView() {
    final exercise = exercises.isNotEmpty
        ? exercises.first
        : const WorkoutSessionExercise(exerciseId: '', exerciseTitle: '');
    final set = exercise.sets.isNotEmpty ? exercise.sets.last : null;
    return WorkoutLogEntry(
      id: id,
      exerciseId: exercise.exerciseId,
      exerciseTitle: exercise.exerciseTitle,
      completedAt: completedAt ?? startedAt,
      durationMinutes: durationMinutes ?? 0,
      notes: notes,
      weightKg: set?.weightKg,
      repsCompleted: set?.reps,
      difficulty: exercise.difficulty,
    );
  }
}
