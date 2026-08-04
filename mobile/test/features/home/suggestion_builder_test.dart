import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

final now = DateTime(2026, 7, 30, 12);

ExerciseItem ex(
  String id, {
  String? equipment,
  List<String> primary = const ['chest'],
  int minutes = 8,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
}) {
  return ExerciseItem(
    id: id,
    title: 'Title $id',
    equipmentId: equipment,
    muscles: primary,
    primaryMuscles: primary,
    difficulty: difficulty,
    durationMinutes: minutes,
    summary: '',
    steps: const [],
  );
}

WorkoutLogEntry log(String exerciseId, DateTime at) => WorkoutLogEntry(
      id: 'log-$exerciseId',
      exerciseId: exerciseId,
      exerciseTitle: 'Title $exerciseId',
      completedAt: at,
      durationMinutes: 10,
    );

UserProfile profileWith({
  FitnessGoals goals = FitnessGoals.empty,
  List<Injury> injuries = const [],
  WorkoutDuration? duration,
}) {
  return UserProfile.empty('u1').copyWith(
    goals: goals,
    health: HealthHistory.empty.copyWith(injuries: injuries),
    motivation: MotivationPrefs.empty.copyWith(preferredDuration: duration),
    completedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('buildSuggestions', () {
    test('an empty catalog yields no suggestions, not filler', () {
      expect(
        buildSuggestions(
            candidates: const [], profile: null, recentLogs: const []),
        isEmpty,
      );
    });

    test('every suggestion points at a real catalog exercise', () {
      final catalog = [
        ex('a', primary: ['chest']),
        ex('b', primary: ['back']),
        ex('c', primary: ['quads']),
      ];
      final out = buildSuggestions(
        candidates: catalog,
        profile: profileWith(),
        recentLogs: const [],
        now: now,
      );
      final ids = catalog.map((e) => e.id).toSet();
      expect(out, isNotEmpty);
      for (final s in out) {
        expect(ids, contains(s.exerciseId),
            reason: 'the card navigates to /workout/<id>, so the id must exist');
      }
    });

    test('skips what was done in the last 48 hours', () {
      final out = buildSuggestions(
        candidates: [
          ex('yesterday', primary: ['chest']),
          ex('fresh', primary: ['back']),
        ],
        profile: profileWith(),
        recentLogs: [log('yesterday', now.subtract(const Duration(hours: 20)))],
        now: now,
      );
      expect(out.map((s) => s.exerciseId), isNot(contains('yesterday')));
      expect(out.map((s) => s.exerciseId), contains('fresh'));
    });

    test('does not skip something done last week', () {
      final out = buildSuggestions(
        candidates: [ex('old', primary: ['chest'])],
        profile: profileWith(),
        recentLogs: [log('old', now.subtract(const Duration(days: 5)))],
        now: now,
      );
      expect(out.map((s) => s.exerciseId), contains('old'));
    });

    test('prefers an untrained muscle and says so', () {
      final out = buildSuggestions(
        candidates: [
          ex('chesty', primary: ['chest']),
          ex('backy', primary: ['back']),
        ],
        profile: profileWith(),
        // Chest was trained 3 days ago; back has not been.
        recentLogs: [log('chesty', now.subtract(const Duration(days: 3)))],
        now: now,
      );
      expect(out.first.exerciseId, 'backy');
      expect(out.first.reason, contains('not trained back this week'));
    });

    test('a weight-loss goal surfaces cardio with a matching reason', () {
      final out = buildSuggestions(
        candidates: [
          ex('press', equipment: 'bench_press', primary: ['chest']),
          ex('run', equipment: 'treadmill', primary: ['quads']),
        ],
        profile: profileWith(goals: const FitnessGoals(weightLoss: true)),
        recentLogs: const [],
        now: now,
      );
      expect(out.first.exerciseId, 'run');
      expect(out.first.reason, contains('weight-loss'));
    });

    test('an endurance goal names endurance, not weight loss', () {
      final out = buildSuggestions(
        candidates: [ex('row', equipment: 'rowing_machine', primary: ['back'])],
        profile: profileWith(goals: const FitnessGoals(endurance: true)),
        recentLogs: const [],
        now: now,
      );
      expect(out.first.reason, contains('endurance'));
    });

    test('a strength goal surfaces resistance work over cardio', () {
      final out = buildSuggestions(
        candidates: [
          ex('run', equipment: 'treadmill', primary: ['quads']),
          ex('squat', equipment: 'squat_rack', primary: ['glutes']),
        ],
        profile: profileWith(goals: const FitnessGoals(strength: true)),
        recentLogs: const [],
        now: now,
      );
      expect(out.first.exerciseId, 'squat');
      expect(out.first.reason, contains('strength'));
    });

    test('a preferred session length is honoured', () {
      final out = buildSuggestions(
        candidates: [
          ex('long', primary: ['chest'], minutes: 60),
          ex('short', primary: ['back'], minutes: 12),
        ],
        profile: profileWith(duration: WorkoutDuration.under15),
        recentLogs: const [],
        now: now,
      );
      expect(out.first.exerciseId, 'short');
      expect(out.first.reason, contains('session length'));
    });

    test('does not repeat the same primary muscle while variety is available',
        () {
      final out = buildSuggestions(
        candidates: [
          ex('c1', primary: ['chest']),
          ex('c2', primary: ['chest']),
          ex('c3', primary: ['chest']),
          ex('b1', primary: ['back']),
          ex('q1', primary: ['quads']),
        ],
        profile: profileWith(),
        recentLogs: const [],
        now: now,
        limit: 3,
      );
      final muscles = out.map((s) => s.exerciseId[0]).toSet();
      expect(muscles, hasLength(3),
          reason: 'three different muscle groups, not three bench variants');
    });

    test('tops the list up rather than showing a short list', () {
      // Only two muscle groups exist, but four exercises do.
      final out = buildSuggestions(
        candidates: [
          ex('c1', primary: ['chest']),
          ex('c2', primary: ['chest']),
          ex('b1', primary: ['back']),
          ex('b2', primary: ['back']),
        ],
        profile: profileWith(),
        recentLogs: const [],
        now: now,
        limit: 4,
      );
      expect(out, hasLength(4));
      expect(out.map((s) => s.exerciseId).toSet(), hasLength(4),
          reason: 'no duplicates while topping up');
    });

    test('respects the limit', () {
      final out = buildSuggestions(
        candidates: [
          for (var i = 0; i < 20; i++) ex('e$i', primary: ['m$i']),
        ],
        profile: profileWith(),
        recentLogs: const [],
        now: now,
        limit: 5,
      );
      expect(out, hasLength(5));
    });

    test('is deterministic across calls', () {
      final catalog = [
        ex('a', primary: ['chest']),
        ex('b', primary: ['back']),
        ex('c', primary: ['quads']),
        ex('d', primary: ['calves']),
      ];
      List<WorkoutSuggestion> run() => buildSuggestions(
            candidates: catalog,
            profile: profileWith(goals: const FitnessGoals(strength: true)),
            recentLogs: [log('a', now.subtract(const Duration(days: 4)))],
            now: now,
          );
      expect(run(), run(),
          reason: 'the section must not reshuffle on every rebuild');
    });

    test('never claims an exercise is safe for a reported injury', () {
      // This test previously asserted the opposite, and asserting it is how
      // the claim survived. `buildSuggestions` said "Safe with the injuries
      // you listed" for any exercise that reached it, on the reasoning that
      // the list is post-filter -- true of the code, false of the world.
      // `filterContraindicated` keeps every untagged exercise, and no
      // exercise in the shipped catalog is tagged, so the claim rested on a
      // check that examined nothing.
      //
      // A reason must be something the app can verify. This one could not be.
      final out = buildSuggestions(
        candidates: [ex('safe', primary: ['chest'])],
        profile: profileWith(
          injuries: const [Injury(bodyPart: 'knee', type: 'strain')],
        ),
        recentLogs: const [],
        now: now,
      );
      expect(out.first.reason, isNot(contains('injuries you listed')));
      expect(out.first.reason, isNot(contains('Safe with')));
      expect(out.first.reason, isNotEmpty,
          reason: 'the card still needs a reason -- the honest ones remain');
    });

    test('works with no profile at all', () {
      final out = buildSuggestions(
        candidates: [ex('a', primary: ['chest'])],
        profile: null,
        recentLogs: const [],
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.reason, isNotEmpty);
    });

    test('every suggestion carries a non-empty reason', () {
      final out = buildSuggestions(
        candidates: [
          for (var i = 0; i < 6; i++) ex('e$i', primary: ['m$i']),
        ],
        profile: profileWith(goals: const FitnessGoals(generalFitness: true)),
        recentLogs: const [],
        now: now,
      );
      for (final s in out) {
        expect(s.reason.trim(), isNotEmpty);
      }
    });
  });
}
