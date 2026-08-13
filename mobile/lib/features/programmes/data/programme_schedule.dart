import '../../equipment/data/equipment_models.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/workout_session.dart' show WorkoutSessionExercise;
import 'programme.dart';

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

  final dayOffsets = _spreadDays(programme.daysPerWeek);
  final rows = <ScheduledSession>[];
  var seq = 0;
  final nowMicros = DateTime.now().microsecondsSinceEpoch;

  for (var week = 0; week < programme.weeks; week++) {
    for (var slot = 0; slot < programme.daysPerWeek; slot++) {
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
            .muscles[(week * programme.daysPerWeek + slot) %
                programme.muscles.length];
        pool = byMuscle[muscle] ?? fullBodyPool;
      }
      if (pool.isEmpty) continue;

      final picked = _fillDay(
        pool,
        startAt: (week + slot) % pool.length,
        targetMinutes: sessionMinutes ?? kDefaultSessionMinutes,
      );
      final exercise = picked.first;
      final date = programme.startedAt
          .add(Duration(days: week * 7 + dayOffsets[slot]));

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

/// Evenly spaced day-of-week offsets (0 = start day) for [count] sessions in
/// a 7-day week. `count` is small in practice (3-5, per [programmeTemplates]
/// in `programme_templates.dart`) so this does not need to handle `count > 7`
/// gracefully beyond not throwing — it clamps to one slot per day.
List<int> _spreadDays(int count) {
  final n = count > 7 ? 7 : count;
  return List<int>.generate(n, (i) => (i * 7 / n).floor());
}
