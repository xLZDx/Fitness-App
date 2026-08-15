import 'workout_session.dart' show WorkoutSessionExercise;

/// Lifecycle of a scheduled workout. `pending` is the only state set on
/// creation; the user (or the auto-marker) transitions it to `completed`
/// when the matching log lands, or `cancelled` if they dismiss it.
enum ScheduledSessionStatus { pending, completed, cancelled }

class ScheduledSession {
  const ScheduledSession({
    required this.id,
    required this.exerciseId,
    required this.exerciseTitle,
    required this.scheduledFor,
    required this.durationMinutes,
    this.status = ScheduledSessionStatus.pending,
    this.notes,
    this.programmeId,
    this.extraExercises = const [],
    this.deloadFactor,
  });

  final String id;

  /// The FIRST exercise of the day. Read [exercises] instead unless you
  /// genuinely mean "the one to show when there is room for one".
  ///
  /// B5b turned a scheduled day into several exercises (operator, 2026-08-13:
  /// "день — это одна тренировка из нескольких упражнений, а не несколько
  /// отдельных тренировок в один день"). These two fields stayed exactly where
  /// they were, holding exercise number one, because the alternative — a single
  /// list replacing them — would have rewritten 24 construction and read sites
  /// in `lib/` and 20 in `test/` in the same change that alters what Firestore
  /// stores. Keeping them is what made the data change provable on its own:
  /// every existing caller compiles and behaves identically, so a green suite
  /// means the shape moved and the behaviour did not.
  final String exerciseId;
  final String exerciseTitle;
  final DateTime scheduledFor;
  final int durationMinutes;
  final ScheduledSessionStatus status;
  final String? notes;

  /// Which `Programme` laid this session out, or null for a session the user
  /// scheduled on their own.
  ///
  /// Nullable and additive: every row written before the programme entity
  /// existed reads back with this null, and every existing consumer of
  /// [ScheduledSession] (Home's week strip, the offline prefetch, the GDPR
  /// export) keeps working unchanged because none of them look at it.
  /// [deriveProgrammeProgress] (`programmes/data/programme.dart`) is the one
  /// reader that does.
  final String? programmeId;

  /// Exercises two and onward. Storage, not the API — read [exercises].
  ///
  /// [WorkoutSessionExercise] rather than a new plan-only pair type, because
  /// the operator's stated reason for choosing this shape was that the plan
  /// should sit in the same form as the record of what was performed
  /// (`WorkoutSession.exercises`) — today they differ, and that difference is
  /// the only thing making plan and fact awkward to compare. Reusing the type
  /// makes starting a workout from a planned day a field-for-field copy.
  ///
  /// Its `sets` are empty and its `difficulty` is null in a plan, which is not
  /// an ambiguity: a `ScheduledSession` is never a completion record, so
  /// "no sets" here reads as "not done yet" and cannot be confused with "did
  /// nothing". `groupId` is meaningful at plan time too — "these two are a
  /// superset" is a statement a plan is entitled to make.
  ///
  /// Empty for every row written before B5b, and for every day that genuinely
  /// holds one exercise. Absence in the stored document IS the discriminator —
  /// the same structural migration `Injury.fromJson` and
  /// `EquipmentAccess._storedGymAccess` already use, and the reason no
  /// migration script is needed: a version field would have to be written by a
  /// migration that has not run, onto documents that already exist.
  final List<WorkoutSessionExercise> extraExercises;

  /// The factor an accepted deload already applied to [durationMinutes], or
  /// null for a session no deload has touched.
  ///
  /// This field is what makes "accept deload" idempotent. It used to be
  /// asserted in a comment — *"Idempotent on reload because the action just
  /// rescales the durations"* — which is the opposite of what rescaling does:
  /// a second pass multiplied 45 → 22 → 11, and the UI hiding the button once
  /// the verdict cleared is a hope about the UI, not a property of the write.
  /// A row that carries a factor is skipped, so pressing twice, retrying after
  /// a partial failure, or two devices racing all land on the same durations.
  ///
  /// Nullable and additive, like [programmeId]: absence in the stored document
  /// IS "never deloaded", so no migration has to run over existing rows.
  final double? deloadFactor;

  /// Every exercise of this day, in order, starting with [exerciseId].
  ///
  /// The API every new reader should use. Never empty: a scheduled day always
  /// has at least the exercise it was created for.
  List<WorkoutSessionExercise> get exercises => [
        WorkoutSessionExercise(
            exerciseId: exerciseId, exerciseTitle: exerciseTitle),
        ...extraExercises,
      ];

  /// How many exercises this day holds. `1` for every row written before B5b.
  int get exerciseCount => 1 + extraExercises.length;

  ScheduledSession copyWith({
    String? id,
    String? exerciseId,
    String? exerciseTitle,
    DateTime? scheduledFor,
    int? durationMinutes,
    ScheduledSessionStatus? status,
    String? notes,
    String? programmeId,
    List<WorkoutSessionExercise>? extraExercises,
    double? deloadFactor,
  }) =>
      ScheduledSession(
        id: id ?? this.id,
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseTitle: exerciseTitle ?? this.exerciseTitle,
        scheduledFor: scheduledFor ?? this.scheduledFor,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        programmeId: programmeId ?? this.programmeId,
        extraExercises: extraExercises ?? this.extraExercises,
        deloadFactor: deloadFactor ?? this.deloadFactor,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        // Still written, always, and still holding exercise number one. An
        // older build of the app reading a multi-exercise day sees the first
        // exercise and behaves exactly as it did before, instead of finding
        // the field gone and failing the required cast in `fromJson`.
        'exerciseId': exerciseId,
        'exerciseTitle': exerciseTitle,
        'scheduledFor': scheduledFor.toIso8601String(),
        'durationMinutes': durationMinutes,
        'status': status.name,
        if (notes != null) 'notes': notes,
        if (programmeId != null) 'programmeId': programmeId,
        if (extraExercises.isNotEmpty)
          'extraExercises': extraExercises.map((e) => e.toJson()).toList(),
        if (deloadFactor != null) 'deloadFactor': deloadFactor,
      };

  factory ScheduledSession.fromJson(Map<String, dynamic> j) {
    final raw = j['scheduledFor'];
    DateTime when;
    if (raw is String) {
      when = DateTime.parse(raw);
    } else if (raw is DateTime) {
      when = raw;
    } else {
      throw ArgumentError(
          'scheduledFor must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
    }
    final statusName = j['status'] as String? ?? 'pending';
    final status = ScheduledSessionStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => ScheduledSessionStatus.pending,
    );
    return ScheduledSession(
      id: j['id'] as String,
      exerciseId: j['exerciseId'] as String,
      exerciseTitle: j['exerciseTitle'] as String? ?? j['exerciseId'] as String,
      scheduledFor: when,
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      status: status,
      notes: j['notes'] as String?,
      programmeId: j['programmeId'] as String?,
      extraExercises: ((j['extraExercises'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) =>
              WorkoutSessionExercise.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      deloadFactor: (j['deloadFactor'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledSession &&
          other.id == id &&
          other.exerciseId == exerciseId &&
          other.exerciseTitle == exerciseTitle &&
          other.scheduledFor == scheduledFor &&
          other.durationMinutes == durationMinutes &&
          other.status == status &&
          other.notes == notes &&
          other.programmeId == programmeId &&
          other.deloadFactor == deloadFactor &&
          _sameExercises(other.extraExercises, extraExercises);

  @override
  int get hashCode => Object.hash(id, exerciseId, exerciseTitle, scheduledFor,
      durationMinutes, status, notes, programmeId,
      Object.hash(deloadFactor, Object.hashAll(extraExercises)));
}

/// Element-wise, order-sensitive. Two days holding the same exercises in a
/// different order are different days: the order is what the player follows.
bool _sameExercises(
  List<WorkoutSessionExercise> a,
  List<WorkoutSessionExercise> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
