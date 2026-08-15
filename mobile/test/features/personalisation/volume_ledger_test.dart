import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/personalisation/data/volume_ledger.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

/// Weekly sets per muscle, and the priority built on it.
///
/// The old training-priority signal was `1 - averageFor(muscles)` over a
/// three-value difficulty rating. It had two defects that no amount of tuning
/// could remove, and this file asserts the replacement does not inherit either:
///
/// 1. It read a *tolerance* answer as a *targeting* answer, so the muscle a
///    user kept reporting as too hard was surfaced more.
/// 2. It was a closed loop — the ranking chose what was shown, which chose
///    what was rated, which updated the ranking — so a muscle could stay top
///    of the list on evidence the ranking itself had generated.
///
/// Deficit has the opposite sign on the second point by construction: training
/// a muscle lowers its priority. The test named "training a muscle lowers its
/// own priority" is the one that pins that, and it is the reason this measure
/// was chosen over the alternatives.

WorkoutSession _session(
  String id,
  DateTime at,
  List<(String exerciseId, int sets)> work,
) =>
    WorkoutSession(
      id: id,
      title: 'session $id',
      startedAt: at,
      completedAt: at,
      exercises: [
        for (final (exerciseId, sets) in work)
          WorkoutSessionExercise(
            exerciseId: exerciseId,
            exerciseTitle: exerciseId,
            sets: List.filled(sets, (weightKg: 60.0, reps: 8)),
          ),
      ],
    );

final _now = DateTime(2026, 8, 15, 12);

const _muscles = <String, ExerciseMuscles>{
  'bench': (primary: ['chest'], secondary: ['triceps', 'shoulders']),
  'row': (primary: ['back'], secondary: ['biceps']),
  'squat': (primary: ['quads'], secondary: ['glutes']),
  'untagged': (primary: [], secondary: []),
  // A real catalogue shape: 'glutes' appears in BOTH lists. Rows written by
  // different hands do this, and it is not a data error — a hip thrust really
  // is a glute movement that also uses the glutes as support.
  'thrust': (primary: ['glutes'], secondary: ['glutes', 'hamstrings']),
};

const _allMuscles = ['chest', 'back', 'quads', 'triceps', 'shoulders', 'biceps',
  'glutes', 'hamstrings'];

Map<String, MuscleVolume> _volume(List<WorkoutSession> sessions) =>
    weeklyVolume(sessions,
        musclesByExerciseId: _muscles, now: _now);

void main() {
  group('sets are counted, which is the whole point', () {
    test('a five-set session counts five sets, not one', () {
      // `asLogEntries` keeps `sets.last` and drops `sets.length`, so every
      // existing consumer sees this as a single row. That is the defect.
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('bench', 5)]),
      ]);

      expect(v['chest']!.sets, 5.0);
    });

    test('a supporting muscle counts for less than a primary one', () {
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('bench', 4)]),
      ]);

      expect(v['chest']!.sets, 4.0);
      expect(v['triceps']!.sets, 4.0 * kSecondaryMuscleWeight);
      expect(v['triceps']!.sets, lessThan(v['chest']!.sets),
          reason: 'counting a secondary as a full set is the error this '
              'replaces — a bench press is not four sets of triceps work');
    });

    test('a muscle listed as both primary and secondary is credited once', () {
      // Found by mutation: deleting the de-duplication guard changed nothing,
      // because no fixture had a muscle in both lists. Without the guard a
      // catalogue row that names glutes twice inflates them by 1.5x, and the
      // feed then reports a muscle as nearly done on work that was counted and
      // then counted again.
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('thrust', 4)]),
      ]);

      expect(v['glutes']!.sets, 4.0,
          reason: 'the primary weight, not primary + secondary');
      expect(v['hamstrings']!.sets, 4.0 * kSecondaryMuscleWeight,
          reason: 'the genuinely-secondary muscle is unaffected');
    });

    test('frequency is counted separately from volume', () {
      // Ten sets in one session and ten across three are different stimuli.
      final oneDay = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('row', 9)]),
      ]);
      final threeDays = _volume([
        for (var d = 1; d <= 3; d++)
          _session('s$d', _now.subtract(Duration(days: d)), [('row', 3)]),
      ]);

      expect(oneDay['back']!.sets, threeDays['back']!.sets);
      expect(oneDay['back']!.sessions, 1);
      expect(threeDays['back']!.sessions, 3);
    });

    test('work outside the window is not counted', () {
      final v = _volume([
        _session('old', _now.subtract(const Duration(days: 9)), [('row', 6)]),
      ]);

      expect(v, isEmpty);
    });

    test('an exercise with no attribution contributes nothing, silently', () {
      // 182 catalogue rows carry no muscle tag. Attributing them to a default
      // group would be a wrong answer to "what has been neglected", which is
      // worse than no answer for a measure whose only job is that question.
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [
          ('untagged', 5),
          ('bench', 2),
        ]),
      ]);

      expect(v.keys, contains('chest'));
      expect(v['chest']!.sets, 2.0);
    });

    test('a planned-but-unperformed exercise contributes nothing', () {
      // Zero sets is not a session for that muscle.
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('bench', 0)]),
      ]);

      expect(v, isEmpty);
    });
  });

  group('deficit orders muscles by what is missing', () {
    test('an untrained muscle is the maximum deficit, not a missing entry', () {
      // The muscles that matter most are exactly the ones absent from the
      // ledger. Reading the vocabulary off the ledger would silently drop
      // them — they would rank nowhere instead of first.
      final d = volumeDeficit(_volume([]), _allMuscles);

      expect(d['hamstrings'], 1.0);
      expect(d.keys.toSet(), _allMuscles.toSet());
    });

    test('meeting the target zeroes the deficit and does not go negative', () {
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)),
            [('row', kWeeklySetTarget.toInt() * 3)]),
      ]);
      final d = volumeDeficit(v, _allMuscles);

      expect(d['back'], 0.0,
          reason: 'a muscle trained well past target must not rank BELOW '
              'zero and pull ahead of nothing');
    });

    test('the trained muscle ranks below the untrained one', () {
      final v = _volume([
        _session('s1', _now.subtract(const Duration(days: 1)), [('squat', 6)]),
      ]);
      final d = volumeDeficit(v, _allMuscles);

      expect(d['quads']!, lessThan(d['hamstrings']!));
    });
  });

  group('the feedback loop runs the right way', () {
    test('training a muscle lowers its own priority', () {
      // THE load-bearing property. The signal this replaces did the opposite:
      // reporting a muscle as too hard raised its priority, which surfaced it
      // more, which produced more ratings of it. Sets performed cannot do
      // that — doing the work is what removes the reason to do it.
      final before = volumeDeficit(_volume([]), _allMuscles)['chest']!;
      final after = volumeDeficit(
        _volume([
          _session('s1', _now.subtract(const Duration(days: 1)), [('bench', 4)]),
        ]),
        _allMuscles,
      )['chest']!;

      expect(after, lessThan(before));
    });

    test('and no difficulty rating can change it in either direction', () {
      // Two identical sessions; only the rating differs. Under the old signal
      // this flipped the muscle from bottom of the ranking to top. Priority
      // must not move at all — that separation IS the decision taken here.
      WorkoutSession rated(DifficultyRating? d) => WorkoutSession(
            id: 's1',
            title: 's1',
            startedAt: _now.subtract(const Duration(days: 1)),
            completedAt: _now.subtract(const Duration(days: 1)),
            exercises: [
              WorkoutSessionExercise(
                exerciseId: 'bench',
                exerciseTitle: 'bench',
                sets: List.filled(4, (weightKg: 60.0, reps: 8)),
                difficulty: d,
              ),
            ],
          );

      final hard = volumeDeficit(
          _volume([rated(DifficultyRating.tooHard)]), _allMuscles)['chest'];
      final easy = volumeDeficit(
          _volume([rated(DifficultyRating.tooEasy)]), _allMuscles)['chest'];
      final unrated = volumeDeficit(_volume([rated(null)]), _allMuscles)['chest'];

      expect(hard, easy);
      expect(hard, unrated);
    });
  });

  group('exercise priority', () {
    test('reads primary muscles, not the diluted full list', () {
      // A bench press averaged over chest + triceps + shoulders is diluted by
      // groups it barely trains. `deficit` here says chest is fully met and
      // the supporting groups are not; the exercise must follow chest.
      const deficit = {
        'chest': 0.0,
        'triceps': 1.0,
        'shoulders': 1.0,
      };

      expect(exercisePriority(_muscles['bench']!, deficit), 0.0);
    });

    test('falls back to secondary muscles when there is no primary', () {
      const only = (primary: <String>[], secondary: ['glutes']);
      expect(exercisePriority(only, const {'glutes': 0.4}), 0.4);
    });

    test('an unattributed exercise returns null, not a neutral score', () {
      // Scoring these at the mid-point put 182 catalogue rows in the same tie
      // class as every unrated muscle, from which a greedy top-N fill could
      // take a whole session. "No signal" must not read as "no deficit".
      expect(exercisePriority(_muscles['untagged']!, const {}), isNull);
    });

    test('an exercise whose muscles are all unknown returns null', () {
      expect(exercisePriority(_muscles['bench']!, const {}), isNull);
    });
  });
}
