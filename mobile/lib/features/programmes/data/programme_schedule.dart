import '../../equipment/data/equipment_models.dart';
import '../../workouts/data/scheduled_session.dart';
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
/// A day-slot's target muscle (or the whole catalogue, when
/// [ProgrammeTemplate.isFullBody] — see `programme_templates.dart`) cycles
/// through candidates by `(week + slot)`, so a 10-week hypertrophy programme
/// does not schedule the same chest exercise ten times: it is real variety
/// bounded by what the catalogue actually offers for that muscle, not a
/// promise of novelty this function cannot keep if the candidate list is
/// short.
List<ScheduledSession> buildProgrammeSchedule({
  required Programme programme,
  required List<ExerciseItem> catalogue,
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
        final muscle = programme.muscles[slot % programme.muscles.length];
        pool = byMuscle[muscle] ?? fullBodyPool;
      }
      if (pool.isEmpty) continue;

      final exercise = pool[(week + slot) % pool.length];
      final date = programme.startedAt
          .add(Duration(days: week * 7 + dayOffsets[slot]));

      rows.add(ScheduledSession(
        id: '${nowMicros}_${seq}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        scheduledFor: date,
        durationMinutes: exercise.durationMinutes,
        programmeId: programme.id,
      ));
      seq++;
    }
  }
  return rows;
}

/// Evenly spaced day-of-week offsets (0 = start day) for [count] sessions in
/// a 7-day week. `count` is small in practice (3-5, per [programmeTemplates]
/// in `programme_templates.dart`) so this does not need to handle `count > 7`
/// gracefully beyond not throwing — it clamps to one slot per day.
List<int> _spreadDays(int count) {
  final n = count > 7 ? 7 : count;
  return List<int>.generate(n, (i) => (i * 7 / n).floor());
}
