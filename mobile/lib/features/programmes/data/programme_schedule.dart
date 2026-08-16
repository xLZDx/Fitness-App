/// Day placement, session-length defaults, and the plan-to-rows writer.
///
/// Gate G-E removed `buildProgrammeSchedule` and `_fillDay` from this file.
/// They decided WHAT to train by walking the catalogue when a slot came up
/// empty, which is the defect F021/F022 name; `buildProgramme`
/// (`programme_builder.dart`) decides that against a declared
/// `ProgrammeSpec` and refuses when it cannot. What is left here is the
/// WHEN, plus [scheduleFromPlan], which turns a built plan into repository
/// rows without making a single training decision of its own.
library;

import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/workout_session.dart' show WorkoutSessionExercise;
import 'programme.dart';
import 'programme_builder.dart';

/// How long one session should run, when the user has not said.
///
/// The screen offers 30/45/60/75/90 (`TrainingSchedule.sessionMinutes`). This
/// is not their median — it is deliberately below it. The two ways of being
/// wrong are not symmetric: a day that is too short is one tap to extend, the
/// player has carried an add-exercise button since R11e, while a day that is
/// too long has to be abandoned half-finished, and an abandoned day reads as a
/// failure rather than as a plan that guessed high.
const kDefaultSessionMinutes = 45;

/// Which days of the week this programme's sessions land on, as offsets from
/// [startedOn] (0 = the start day itself).
///
/// B5d. The questionnaire asks which weekdays the user trains
/// (`step_schedule.dart:82-89`, stored as `TrainingSchedule.preferredWeekdays`)
/// and, until this function existed, nothing in the scheduling path ever read
/// the answer: [_spreadDays] laid sessions out evenly and a user who said
/// "Monday, Wednesday, Friday" was given Monday, Wednesday, Thursday — or any
/// other three days, depending only on which weekday they happened to enrol.
/// Asking a question and then visibly ignoring the answer is worse than not
/// asking it.
///
/// When the user named no days, nothing changes: the even spread is still the
/// best available guess and is what every existing enrolment was built with.
///
/// ## When the two answers disagree
///
/// The questionnaire also asks how many days a week (`daysPerWeek`), so a user
/// can say "four days" and then tick three weekdays. The named days win, and
/// the programme becomes a three-day one:
///
/// - Naming a weekday is the more specific answer. Scheduling someone on a day
///   they were shown and did not tick is the one outcome that reads as the app
///   overriding them, which is exactly the complaint this gate is closing.
/// - The opposite error is milder and self-correcting: a day short is one tap
///   on the player's add-exercise button, or an untouched extra rest day.
///
/// More named days than [daysPerWeek] keeps the count answer and takes the
/// [daysPerWeek] days that come soonest after [startedOn] — sorted by distance
/// from the start day, which is only Monday-to-Sunday order when the programme
/// happens to start on a Monday.
///
/// The caller must keep `Programme.daysPerWeek` equal to this list's length —
/// `deriveProgrammeProgress` counts completed sessions against that number, so
/// a programme claiming four days a week over a three-day schedule would
/// report progress it can never reach.
List<int> programmeDayOffsets({
  required DateTime startedOn,
  required int daysPerWeek,
  required List<int> preferredWeekdays,
}) {
  final wanted = _namedWeekdays(preferredWeekdays);
  if (wanted.isEmpty) return _spreadDays(daysPerWeek);

  final offsets = wanted
      .map((weekday) => (weekday - startedOn.weekday + 7) % 7)
      .toList()
    ..sort();
  return offsets.length <= daysPerWeek
      ? offsets
      : offsets.take(daysPerWeek).toList();
}

/// The weekdays [preferredWeekdays] actually names, deduplicated and sorted.
///
/// `DateTime.monday`..`DateTime.sunday` are 1..7. Anything outside that is not
/// a weekday the questionnaire could have written, so it is dropped rather
/// than wrapped into a wrong day — `TrainingSchedule.preferredWeekdays` is
/// deliberately unvalidated at the model (`profile_models.dart:683`), so a
/// hand-written 9 would otherwise become a real day nobody asked for.
List<int> _namedWeekdays(List<int> preferredWeekdays) =>
    preferredWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();

/// How many sessions a week [programmeDayOffsets] will schedule, without
/// needing a start date.
///
/// Exists so a screen can state the cadence BEFORE enrolment — the card that
/// offers a questionnaire-built programme (`workouts_page.dart`) has to name a
/// number, and the alternative was doing this arithmetic a second time in the
/// widget, where it could drift from the generator's.
///
/// Date-independent by construction: [programmeDayOffsets] maps each named
/// weekday to exactly one offset and then truncates to [daysPerWeek], so the
/// COUNT depends only on how many weekdays were named — which day the
/// programme starts on moves the offsets, never how many there are.
int programmeScheduledDays({
  required int daysPerWeek,
  required List<int> preferredWeekdays,
}) {
  final wanted = _namedWeekdays(preferredWeekdays).length;
  if (wanted == 0) return _spreadDays(daysPerWeek).length;
  return wanted <= daysPerWeek ? wanted : daysPerWeek;
}

/// Evenly spaced day-of-week offsets (0 = start day) for [count] sessions in
/// a 7-day week. `count` is small in practice (3-5, per [programmeTemplates]
/// in `programme_templates.dart`) so this does not need to handle `count > 7`
/// gracefully beyond not throwing — it clamps to one slot per day.
List<int> _spreadDays(int count) {
  final n = count > 7 ? 7 : count;
  return List<int>.generate(n, (i) => (i * 7 / n).floor());
}

/// Turns a role-built plan into the rows the scheduled-session repository
/// stores.
///
/// Gate P. `buildProgrammeSchedule` decides WHAT to train and WHEN in one pass;
/// this only does the when, because `buildProgramme` has already done the what
/// and done it against a spec. Splitting them is what lets the structural rules
/// be tested without a calendar and the calendar rules without a catalogue.
///
/// Day placement is identical to `buildProgrammeSchedule`'s and for the same
/// reason: built from calendar PARTS, never `add(Duration(days:))`, so a clock
/// change inside the programme's span cannot move a session onto the wrong
/// weekday.
List<ScheduledSession> scheduleFromPlan({
  required Programme programme,
  required List<PlannedSession> plan,
  required List<int> dayOffsets,
}) {
  if (plan.isEmpty || dayOffsets.isEmpty) return const [];
  final rows = <ScheduledSession>[];
  final nowMicros = DateTime.now().microsecondsSinceEpoch;
  var seq = 0;

  for (final session in plan) {
    if (session.exercises.isEmpty) continue;
    final offset = dayOffsets[session.dayIndex % dayOffsets.length];
    final start = programme.startedAt;
    final date = DateTime(
      start.year,
      start.month,
      start.day + session.week * 7 + offset,
      start.hour,
      start.minute,
    );
    final first = session.exercises.first.exercise;
    rows.add(ScheduledSession(
      id: '${nowMicros}_${seq}_${first.id}',
      exerciseId: first.id,
      exerciseTitle: first.title,
      extraExercises: [
        for (final e in session.exercises.skip(1))
          WorkoutSessionExercise(
              exerciseId: e.exercise.id, exerciseTitle: e.exercise.title),
      ],
      scheduledFor: date,
      durationMinutes: session.exercises
          .fold<int>(0, (sum, e) => sum + e.exercise.durationMinutes),
      programmeId: programme.id,
    ));
    seq++;
  }
  return rows;
}
