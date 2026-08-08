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
  });

  final String id;
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

  ScheduledSession copyWith({
    String? id,
    String? exerciseId,
    String? exerciseTitle,
    DateTime? scheduledFor,
    int? durationMinutes,
    ScheduledSessionStatus? status,
    String? notes,
    String? programmeId,
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'exerciseTitle': exerciseTitle,
        'scheduledFor': scheduledFor.toIso8601String(),
        'durationMinutes': durationMinutes,
        'status': status.name,
        if (notes != null) 'notes': notes,
        if (programmeId != null) 'programmeId': programmeId,
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
          other.programmeId == programmeId;

  @override
  int get hashCode => Object.hash(id, exerciseId, exerciseTitle, scheduledFor,
      durationMinutes, status, notes, programmeId);
}
