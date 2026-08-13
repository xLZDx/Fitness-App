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

/// Replaces the ENTRY exercise -- `exercises[0]`, always the exercise the
/// player page was opened on -- with [updated], keeping every exercise after
/// it untouched.
///
/// R11e's player only ever APPENDS beyond index 0 (`_AddExerciseButton`,
/// `workout_player_page.dart`), so "index 0" and "the entry exercise" are the
/// same thing for the lifetime of a session -- position, not `exerciseId`, is
/// what identifies it here, matching how the player's own "already logged"
/// lookup already worked (`already?.exercises.first`).
///
/// Exists because the obvious inline version -- `exercises: [updated]` --
/// silently dropped every exercise appended after the first the moment the
/// entry exercise's own set was re-edited. That bug shipped once already in
/// this file's history; this function is here so it cannot ship a second
/// time from a different call site.
List<WorkoutSessionExercise> replaceEntryExercise(
  List<WorkoutSessionExercise> exercises,
  WorkoutSessionExercise updated,
) {
  if (exercises.isEmpty) return [updated];
  return [updated, ...exercises.skip(1)];
}

/// Replaces the exercise with the same `exerciseId` as [updated], or appends it
/// if the session does not hold it yet.
///
/// The identity sibling of [replaceEntryExercise], for the case that function's
/// own doc comment rules out. Position identifies the entry exercise only while
/// the player can be entered on exactly one exercise per session. Opening a
/// scheduled DAY breaks that: exercises two, three and four of the day are
/// logged into the same session as exercise one, and `replaceEntryExercise`
/// would write every one of them over index 0 — a four-exercise day would
/// persist as a one-exercise session whose title kept changing.
///
/// `exerciseId` is a safe key here because no session holds the same exercise
/// twice: `_fillDay` (`programme_schedule.dart`) never repeats one inside a
/// day, and the player's own add-exercise picker excludes ids already present.
/// If that ever stops being true this replaces the FIRST match, which is the
/// same thing `replaceEntryExercise` does to index 0 — not a new failure mode,
/// just a differently-keyed one.
List<WorkoutSessionExercise> upsertExerciseById(
  List<WorkoutSessionExercise> exercises,
  WorkoutSessionExercise updated,
) {
  final at = exercises.indexWhere((e) => e.exerciseId == updated.exerciseId);
  if (at < 0) return [...exercises, updated];
  return [
    ...exercises.take(at),
    updated,
    ...exercises.skip(at + 1),
  ];
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
/// [WorkoutSession].
///
/// R11e superseded the F3.3-era `asLogEntryView()`, which returned exactly
/// one [WorkoutLogEntry] per session (only the first exercise and its last
/// set) -- valid only while the player wrote at most one exercise per
/// session, which R11e's player loop stops being true. [asLogEntries] emits
/// ONE ROW PER EXERCISE instead, all sharing [WorkoutLogEntry.sessionId] =
/// [id] but each with its own [WorkoutLogEntry.id] -- so a 5-exercise gym
/// visit surfaces all five to muscle recovery, progression and
/// personal-record tracking (all keyed by `exerciseId`, unaffected by how
/// many rows share a session) while still counting as the ONE workout it
/// is, in whatever reads [WorkoutLogEntry.sessionId] rather than counting
/// rows (`deriveProgress`, `deriveWeekTotals` -- see their own doc comments).
///
/// Each exercise contributes its LAST set's weight/reps, same simplification
/// [WorkoutLogEntry]'s one-weight-one-reps shape already made for the
/// single-exercise case -- now applied per exercise instead of applied once
/// and then discarding every exercise after the first.
///
/// A session with zero exercises (should not happen, but [exercises] is not
/// guaranteed non-empty by the type) still contributes one placeholder row --
/// the same fallback `asLogEntryView()` used -- so a session that is
/// `completed` always counts toward the streak/total it earned by being
/// marked complete at all.
extension WorkoutSessionLogView on WorkoutSession {
  List<WorkoutLogEntry> asLogEntries() {
    if (exercises.isEmpty) {
      return [
        WorkoutLogEntry(
          id: id,
          sessionId: id,
          exerciseId: '',
          exerciseTitle: '',
          completedAt: completedAt ?? startedAt,
          durationMinutes: durationMinutes ?? 0,
          notes: notes,
        ),
      ];
    }
    return [
      for (var i = 0; i < exercises.length; i++)
        () {
          final exercise = exercises[i];
          final set = exercise.sets.isNotEmpty ? exercise.sets.last : null;
          return WorkoutLogEntry(
            // Plain `id` for the single-exercise case -- the common one,
            // and every row this app has ever written before R11e -- so a
            // session with one exercise produces the exact same
            // WorkoutLogEntry.id `asLogEntryView()` used to. Only suffixed
            // by index once there is more than one exercise to distinguish
            // between; index-qualified rather than exerciseId-qualified
            // because the same exercise could in principle appear twice in
            // one session (e.g. both a warm-up and a main lift), and two
            // rows sharing an `id` would upsert onto each other the moment
            // either is ever persisted standalone.
            id: exercises.length == 1 ? id : '${id}_$i',
            sessionId: id,
            exerciseId: exercise.exerciseId,
            exerciseTitle: exercise.exerciseTitle,
            completedAt: completedAt ?? startedAt,
            durationMinutes: durationMinutes ?? 0,
            notes: notes,
            weightKg: set?.weightKg,
            repsCompleted: set?.reps,
            difficulty: exercise.difficulty,
          );
        }(),
    ];
  }
}
