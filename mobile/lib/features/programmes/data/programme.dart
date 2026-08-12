import '../../equipment/data/equipment_models.dart' show ExerciseDifficulty;
import '../../workouts/data/scheduled_session.dart';

/// A multi-week training programme the user is enrolled in.
///
/// ## Why this entity exists
///
/// Three separate gates stopped at the same missing thing. R11a's Home header
/// wanted "Силовая база · Неделя 2 из 8" and could only render "this week's
/// schedule" instead (`home_dashboard.dart:23` documents the gap). R11d's
/// exercise page wanted an "add to programme" button with nothing to add to.
/// R11i's Workouts tab wanted a Programs/Library split where Programs had no
/// subject. Each worked around it honestly; a fourth was going to have to as
/// well.
///
/// ## What it is NOT
///
/// It is **not** a replacement for [ScheduledSession]. The schedule is still
/// the record of what happens on a given day, and every existing reader of it
/// keeps working untouched — a programme is a header over rows that already
/// exist, joined by the nullable [ScheduledSession.programmeId] added in the
/// same change. That direction was chosen over the alternative (a programme
/// that owns an embedded list of days) precisely because the embedded version
/// would have made the schedule two sources of truth: one inside the
/// programme, one in `scheduled_sessions`, disagreeing the first time a user
/// moved a session.
///
/// It is also not the *catalogue*. [Programme] is one user's enrolment;
/// `programme_templates.dart` holds the offer they enrolled from.
/// What a programme is FOR.
///
/// `endurance` joined the other five in O3, when onboarding started asking for
/// a single primary goal (`FitnessGoals.primary`). The design offers six
/// choices and five of them already existed here; inventing a second, parallel
/// "onboarding goal" enum and a mapping table between the two would have left
/// two vocabularies to keep in step, and nobody maintains a mapping table.
///
/// Every switch over this enum is exhaustive on purpose — adding a seventh
/// value should be a compile error at each display site, not a silent default.
enum ProgrammeGoal { strength, muscle, weightLoss, form, comeback, endurance }

/// Lifecycle. `active` is what "current programme" means; there is at most one
/// per user at a time (see `activeProgrammeProvider`), but finished ones are
/// kept rather than deleted so a user can see what they have completed.
enum ProgrammeStatus { active, completed, abandoned }

T _parseEnum<T>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if ((v as Enum).name == name) return v;
  }
  return fallback;
}

class Programme {
  const Programme({
    required this.id,
    required this.templateId,
    required this.title,
    required this.goal,
    required this.level,
    required this.weeks,
    required this.daysPerWeek,
    required this.startedAt,
    this.muscles = const [],
    this.status = ProgrammeStatus.active,
    this.endedAt,
  });

  final String id;

  /// Which `ProgrammeTemplate` this came from. Kept so a future gate can tell
  /// "the user has already run this one" without string-matching the title,
  /// which is localised and therefore not an identity.
  final String templateId;

  /// Denormalised from the template at enrolment, in the user's language at
  /// that moment — same choice, for the same reason, as
  /// `WorkoutLogEntry.exerciseTitle` (`workout_log.dart`): a completion record
  /// must keep meaning what it meant even if the catalogue entry is renamed or
  /// withdrawn.
  final String title;

  final ProgrammeGoal goal;

  /// Reuses the catalogue's own tiering (`ExerciseDifficulty`) rather than a
  /// second beginner/intermediate/advanced enum — a programme card and an
  /// exercise card that used different words for the same three tiers would
  /// be the same inconsistency `CatalogLabels`' own doc comment was written to
  /// prevent.
  final ExerciseDifficulty level;

  /// Total length. With [daysPerWeek] this is the commitment the user made,
  /// which is what [ProgrammeProgress] measures against.
  final int weeks;
  final int daysPerWeek;

  /// Catalogue muscle keys the programme focuses on, for the card's subtitle.
  /// Keys, not words — localised through `CatalogLabels.muscle` at render time,
  /// the same way `SessionDigest.muscles` is.
  final List<String> muscles;

  final DateTime startedAt;
  final ProgrammeStatus status;

  /// Set when [status] leaves `active`. Nullable for the same reason
  /// `WorkoutSession.completedAt` is: a required end date would force every
  /// running programme to invent one.
  final DateTime? endedAt;

  /// How many sessions the programme asks for in total.
  int get plannedSessions => weeks * daysPerWeek;

  Programme copyWith({
    String? id,
    String? templateId,
    String? title,
    ProgrammeGoal? goal,
    ExerciseDifficulty? level,
    int? weeks,
    int? daysPerWeek,
    List<String>? muscles,
    DateTime? startedAt,
    ProgrammeStatus? status,
    DateTime? endedAt,
  }) =>
      Programme(
        id: id ?? this.id,
        templateId: templateId ?? this.templateId,
        title: title ?? this.title,
        goal: goal ?? this.goal,
        level: level ?? this.level,
        weeks: weeks ?? this.weeks,
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        muscles: muscles ?? this.muscles,
        startedAt: startedAt ?? this.startedAt,
        status: status ?? this.status,
        endedAt: endedAt ?? this.endedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'goal': goal.name,
        'level': level.name,
        'weeks': weeks,
        'daysPerWeek': daysPerWeek,
        'muscles': muscles,
        'startedAt': startedAt.toIso8601String(),
        'status': status.name,
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
      };

  static DateTime _date(dynamic raw, String field) {
    if (raw is String) return DateTime.parse(raw);
    if (raw is DateTime) return raw;
    // Firestore Timestamp stays out of the model layer's imports; repositories
    // convert before calling, same convention as WorkoutSession.fromJson.
    throw ArgumentError(
        '$field must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
  }

  factory Programme.fromJson(Map<String, dynamic> j) {
    final rawEnded = j['endedAt'];
    return Programme(
      id: j['id'] as String,
      templateId: j['templateId'] as String? ?? '',
      title: j['title'] as String,
      goal: _parseEnum(ProgrammeGoal.values, j['goal'] as String?,
          ProgrammeGoal.strength),
      level: _parseEnum(ExerciseDifficulty.values, j['level'] as String?,
          ExerciseDifficulty.beginner),
      weeks: (j['weeks'] as num?)?.toInt() ?? 0,
      daysPerWeek: (j['daysPerWeek'] as num?)?.toInt() ?? 0,
      muscles: (j['muscles'] as List<dynamic>? ?? const [])
          .map((m) => m as String)
          .toList(growable: false),
      startedAt: _date(j['startedAt'], 'startedAt'),
      status: _parseEnum(ProgrammeStatus.values, j['status'] as String?,
          ProgrammeStatus.active),
      endedAt: rawEnded == null ? null : _date(rawEnded, 'endedAt'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Programme &&
          other.id == id &&
          other.templateId == templateId &&
          other.title == title &&
          other.goal == goal &&
          other.level == level &&
          other.weeks == weeks &&
          other.daysPerWeek == daysPerWeek &&
          _sameStrings(other.muscles, muscles) &&
          other.startedAt == startedAt &&
          other.status == status &&
          other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(id, templateId, title, goal, level, weeks,
      daysPerWeek, Object.hashAll(muscles), startedAt, status, endedAt);
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Day-bucket for [t], keyed in UTC so day arithmetic survives DST while still
/// meaning the user's local day. Same helper, same reason, as
/// `home_dashboard.dart:32` and `progress_stats.dart:35`.
DateTime _dayOf(DateTime t) {
  final local = t.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// Which week of [programme] contains [now], 1-based.
///
/// Counted from [Programme.startedAt] in whole 7-day blocks — NOT from
/// calendar Mondays. A programme started on a Thursday runs Thursday-to-
/// Wednesday; anchoring its weeks to the calendar would have made its first
/// week 4 days long and shown "week 2 of 8" three days after the user started.
///
/// Clamped to `[1, weeks]`: before the start date the answer is week 1 (the
/// user is looking at a programme that has not begun), and past the end it is
/// the last week rather than an overflowing number. A caller that needs to know
/// the programme has run out of weeks asks [isOverdue], which does not lie
/// about it.
int programmeWeek(Programme programme, {DateTime? now}) {
  if (programme.weeks <= 0) return 1;
  final days =
      _dayOf(now ?? DateTime.now()).difference(_dayOf(programme.startedAt)).inDays;
  if (days < 0) return 1;
  final week = (days ~/ 7) + 1;
  return week > programme.weeks ? programme.weeks : week;
}

/// True once more than [Programme.weeks] weeks have passed since the start.
///
/// The programme is not auto-completed when this flips: finishing is the user's
/// call (they may be a week behind and still working through it), and a
/// background auto-complete would close a programme somebody was mid-way
/// through. It exists so the UI can offer to close it rather than silently
/// pretending week 8 lasts forever.
bool programmeIsOverdue(Programme programme, {DateTime? now}) {
  if (programme.weeks <= 0) return false;
  final days =
      _dayOf(now ?? DateTime.now()).difference(_dayOf(programme.startedAt)).inDays;
  return days >= programme.weeks * 7;
}

/// How far through a programme the user is.
class ProgrammeProgress {
  const ProgrammeProgress({
    required this.done,
    required this.total,
    required this.week,
    required this.weeks,
  });

  /// Sessions belonging to the programme that are marked completed.
  final int done;

  /// [Programme.plannedSessions] — the commitment, not the number of rows
  /// currently on the schedule.
  ///
  /// Measuring against existing rows was the alternative and it is the one that
  /// misleads: rows are created as the programme is laid out, so a programme
  /// whose later weeks are not scheduled yet would read 100% complete after its
  /// first week.
  final int total;

  final int week;
  final int weeks;

  double get fraction {
    if (total <= 0) return 0;
    final f = done / total;
    // A user can complete more sessions than the programme asked for by adding
    // their own to it. That is not 140% of a programme; it is a finished one.
    return f > 1 ? 1 : f;
  }

  int get percent => (fraction * 100).round();
}

/// [ProgrammeProgress] for [programme] over [scheduled].
///
/// Only rows carrying this programme's id count. A session the user scheduled
/// on their own is theirs, not the programme's, and folding it in would let
/// unrelated work push a programme's bar forward.
ProgrammeProgress deriveProgrammeProgress(
  Programme programme,
  Iterable<ScheduledSession> scheduled, {
  DateTime? now,
}) {
  var done = 0;
  for (final s in scheduled) {
    if (s.programmeId != programme.id) continue;
    if (s.status == ScheduledSessionStatus.completed) done++;
  }
  return ProgrammeProgress(
    done: done,
    total: programme.plannedSessions,
    week: programmeWeek(programme, now: now),
    weeks: programme.weeks,
  );
}
