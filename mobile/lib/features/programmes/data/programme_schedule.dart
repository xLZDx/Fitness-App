import '../../equipment/data/equipment_models.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/workout_session.dart' show WorkoutSessionExercise;
import 'programme.dart';
import 'programme_builder.dart';

/// Turns an enrolment into the rows [ScheduledSessionRepository] actually
/// stores. Pure — no I/O, no id-collision handling — so it is testable
/// without a repository and the caller (the enrol action) decides how the
/// rows get saved.
///
/// ## Why exercises, not placeholders
///
/// Every slot gets a real, injury-screened catalogue exercise, the same way
/// [ScheduledSession] already works everywhere else in the app (`workout_player_page.dart`
/// schedules one real exercise per row; there is no "TBD" exercise anywhere
/// in this model). [catalogue] must already be screened — this function does
/// not re-check injuries, matching [ScheduledSession]'s existing contract
/// that a screened caller stores an unscreened row (`session_screening_providers.dart`
/// re-screens on read, defence in depth against a profile that changes after
/// a row was written).
///
/// [catalogue] is also expected to be narrowed to what the user can actually
/// perform (`availableWith`, `exercise_filter.dart`). That filtering is done by
/// the caller rather than here on purpose: this function RELAXES a constraint
/// when a slot has no candidates — see the muscle fallback below — which is the
/// right answer for a muscle and the wrong one for equipment. Handing it the
/// narrowed list means the exercises the user cannot do are not in the pool it
/// could fall back to.
///
/// ## Day spacing
///
/// [Programme.daysPerWeek] slots are spread evenly across the 7-day week
/// starting from [Programme.startedAt]'s weekday, not bunched at the start —
/// 4 days/week lands on offsets 0/2/4/5, not 0/1/2/3. A user who enrols and
/// then sees 4 straight days on the schedule before a 3-day gap would
/// reasonably read that as the programme being poorly designed rather than as
/// an artefact of how this function laid it out.
///
/// ## Exercise rotation
///
/// The day-slot's target muscle itself advances with the week, so a programme
/// naming more muscles than it has weekly slots still reaches every one of them
/// (see the expression below for what that fixes). Within a muscle — or the
/// whole catalogue, when [ProgrammeTemplate.isFullBody], see
/// `programme_templates.dart` — candidates cycle by `(week + slot)`, so a
/// 10-week hypertrophy programme
/// does not schedule the same chest exercise ten times: it is real variety
/// bounded by what the catalogue actually offers for that muscle, not a
/// promise of novelty this function cannot keep if the candidate list is
/// short.
/// How long one session should run, when the user has not said.
///
/// The screen offers 30/45/60/75/90 (`TrainingSchedule.sessionMinutes`). This
/// is not their median — it is deliberately below it. The two ways of being
/// wrong are not symmetric: a day that is too short is one tap to extend, the
/// player has carried an add-exercise button since R11e, while a day that is
/// too long has to be abandoned half-finished, and an abandoned day reads as a
/// failure rather than as a plan that guessed high.
const kDefaultSessionMinutes = 45;

List<ScheduledSession> buildProgrammeSchedule({
  required Programme programme,
  required List<ExerciseItem> catalogue,
  int? sessionMinutes,
  List<int> preferredWeekdays = const [],
}) {
  if (catalogue.isEmpty || programme.weeks <= 0 || programme.daysPerWeek <= 0) {
    return const [];
  }

  final byMuscle = <String, List<ExerciseItem>>{};
  for (final m in programme.muscles) {
    final matches = catalogue.where((e) => e.muscles.contains(m)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (matches.isNotEmpty) byMuscle[m] = matches;
  }
  final fullBodyPool = [...catalogue]..sort((a, b) => a.id.compareTo(b.id));

  final dayOffsets = programmeDayOffsets(
    startedOn: programme.startedAt,
    daysPerWeek: programme.daysPerWeek,
    preferredWeekdays: preferredWeekdays,
  );
  // The number of sessions in a week is however many days there are to put
  // them on, which is NOT always `programme.daysPerWeek`: naming fewer
  // weekdays than the count answer shortens the week (see
  // [programmeDayOffsets]). Iterating to `daysPerWeek` against a shorter list
  // would index past its end.
  final slotsPerWeek = dayOffsets.length;
  if (slotsPerWeek == 0) return const [];
  final rows = <ScheduledSession>[];
  var seq = 0;
  final nowMicros = DateTime.now().microsecondsSinceEpoch;

  for (var week = 0; week < programme.weeks; week++) {
    for (var slot = 0; slot < slotsPerWeek; slot++) {
      List<ExerciseItem> pool;
      if (programme.muscles.isEmpty) {
        pool = fullBodyPool;
      } else {
        // Advances with the WEEK as well as the slot, so a programme with more
        // named muscles than weekly slots still reaches all of them. `slot %
        // muscles.length` did not: a 4-muscle template cut to 3 days a week
        // (which B5a's `daysPerWeek` clamp can now do, when the user says they
        // have three) would schedule muscles 0,1,2 every single week and never
        // once schedule the fourth. Not "less often" — never. When slots and
        // muscles are equal, as in every shipped template, this reduces to the
        // old expression and nothing changes.
        final muscle = programme
            .muscles[(week * slotsPerWeek + slot) % programme.muscles.length];
        pool = byMuscle[muscle] ?? fullBodyPool;
      }
      if (pool.isEmpty) continue;

      final picked = _fillDay(
        pool,
        startAt: (week + slot) % pool.length,
        targetMinutes: sessionMinutes ?? kDefaultSessionMinutes,
      );
      final exercise = picked.first;
      // Built from calendar parts, NOT `startedAt.add(Duration(days: n))`.
      // `add` moves the absolute instant by exactly n*24h and does not correct
      // for DST, so a programme started near midnight drifts onto the wrong
      // calendar day — and therefore the wrong WEEKDAY — the moment a clock
      // change falls inside its span. That was survivable while days were
      // merely "evenly spread"; now that the user names the weekdays, it would
      // break the one guarantee this gate exists to make. Same reason
      // `programme.dart:215-221` keys its day buckets in UTC.
      //
      // Overflow past the end of a month is normalised by the constructor, and
      // the time of day is carried over so a session keeps the hour it was
      // enrolled at.
      final start = programme.startedAt;
      final date = DateTime(
        start.year,
        start.month,
        start.day + week * 7 + dayOffsets[slot],
        start.hour,
        start.minute,
      );

      rows.add(ScheduledSession(
        id: '${nowMicros}_${seq}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        extraExercises: [
          for (final e in picked.skip(1))
            WorkoutSessionExercise(exerciseId: e.id, exerciseTitle: e.title),
        ],
        scheduledFor: date,
        // The whole day, not the first exercise. Everything that shows a
        // duration — Home's tile, the week strip, the notification — was
        // already reading this field and would otherwise announce ten minutes
        // for a forty-minute workout.
        durationMinutes:
            picked.fold<int>(0, (sum, e) => sum + e.durationMinutes),
        programmeId: programme.id,
      ));
      seq++;
    }
  }
  return rows;
}

/// The exercises of one day: consecutive entries of [pool] from [startAt],
/// wrapping, until adding another would overshoot [targetMinutes].
///
/// Sums each exercise's own `durationMinutes` rather than dividing the target
/// by a constant. Measured on the shipped catalogue, every one of the 1,887
/// rows says ten minutes, so today the two are the same arithmetic — but the
/// day the catalogue carries real durations, dividing would quietly keep
/// pretending they were all equal, and this does not.
///
/// Always returns at least one exercise, even when that one alone runs past
/// the target: a day with no exercises is not a shorter workout, it is a
/// missing one.
///
/// Never repeats within a day, and therefore never returns more than
/// `pool.length` — running the pool dry is a real limit of what the catalogue
/// offers for that muscle, not something to paper over by scheduling the same
/// movement twice in one session.
List<ExerciseItem> _fillDay(
  List<ExerciseItem> pool, {
  required int startAt,
  required int targetMinutes,
}) {
  final picked = <ExerciseItem>[pool[startAt]];
  var minutes = pool[startAt].durationMinutes;
  for (var step = 1; step < pool.length; step++) {
    final next = pool[(startAt + step) % pool.length];
    if (minutes + next.durationMinutes > targetMinutes) break;
    picked.add(next);
    minutes += next.durationMinutes;
  }
  return picked;
}

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
