import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/personalisation/state/personalisation_providers.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// The personalisation layer has to actually reach a screen.
///
/// A fitness model built from every logged set, a ranker, and tests for both
/// sat in `features/personalisation` and nothing watched any of it. The tab
/// named "For you" read the filtered catalog directly, so it showed every user
/// the same order — the code was correct, tested, and had no effect.
///
/// These tests are about the WIRING, not the ranking maths, which
/// `for_you_ranker_test.dart` already covers. What they pin is that the output
/// depends on the user, because that is the property the feature exists for
/// and the one that was silently absent.
///
/// **Rewritten 2026-08-15.** The fixtures used to be `WorkoutLogEntry` rows
/// injected at `workoutSessionHistoryProvider`, which is a DERIVED view. The
/// feed now orders by weekly set count, and `asLogEntries` — the function that
/// builds that view — keeps `sets.last` and drops `sets.length`. So the old
/// fixture shape could not express the input the feature reads. Overriding the
/// session stream instead is both the real source and one override rather than
/// two: the history view, the fitness profile and the novelty set all derive
/// from it.

ExerciseItem ex(String id, List<String> muscles) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      primaryMuscles: muscles,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: const ['a'],
    );

final _catalog = [
  ex('chest_a', const ['chest']),
  ex('legs_a', const ['quads']),
  ex('back_a', const ['back']),
];

/// A COMPLETED session carrying [sets] sets of one exercise.
///
/// The set count is the whole fixture. A session with an empty `sets` list
/// contributes no volume — correctly, since no set was performed — so a
/// fixture that omits it produces an all-maximum deficit, every exercise ties,
/// and the test passes on the cold-start path instead of the one it names.
WorkoutSession session(
  String exerciseId, {
  int daysAgo = 2,
  int sets = 3,
}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return WorkoutSession(
    id: 'session_${exerciseId}_$daysAgo',
    title: exerciseId,
    startedAt: at,
    completedAt: at,
    status: WorkoutSessionStatus.completed,
    durationMinutes: 30,
    exercises: [
      WorkoutSessionExercise(
        exerciseId: exerciseId,
        exerciseTitle: exerciseId,
        sets: [
          for (var i = 0; i < sets; i++) (weightKg: 20.0, reps: 10),
        ],
      ),
    ],
  );
}

/// Serves the same three exercises the feed is overridden with.
///
/// Needed as well as the feed override, and the reason is the point of the
/// test: the deficit provider builds its muscle map and its muscle VOCABULARY
/// from the REPOSITORY, not from the feed. Without this there are no known
/// muscles, every deficit map is empty, the ranker returns its input untouched,
/// and the two tests that matter fail while the cold-start one passes — which
/// is exactly what a wiring bug looks like from the outside.
class _FakeRepo implements EquipmentRepository {
  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];

  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => const [];

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => _catalog;
}

ProviderContainer _container(List<WorkoutSession> sessions) {
  final c = ProviderContainer(overrides: [
    forYouExercisesProvider.overrideWith((_) async => _catalog),
    equipmentRepositoryProvider.overrideWithValue(_FakeRepo()),
    workoutSessionsProvider.overrideWith((_) => Stream.value(sessions)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('with no history the filtered order is kept', () async {
    // Cold start. Every muscle is equally untrained, so there is nothing to
    // order by — inventing one would be a guess dressed as personalisation.
    final c = _container(const []);
    final feed = await c.read(rankedForYouProvider.future);
    expect(feed.map((e) => e.id), _catalog.map((e) => e.id));
  });

  test('training one muscle group pushes it down the feed', () async {
    // The whole promise: what you have been doing least comes first.
    final c = _container([
      session('chest_a'),
      session('chest_a', daysAgo: 3),
      session('chest_a', daysAgo: 4),
    ]);
    final feed = await c.read(rankedForYouProvider.future);

    expect(feed, hasLength(_catalog.length), reason: 'nothing may be dropped');
    expect(feed.last.id, 'chest_a',
        reason: 'the only trained group must not lead a feed that exists to '
            'surface what is being neglected');
  });

  test('two different histories produce two different feeds', () async {
    // The property that was missing. Before the wiring this passed trivially
    // for the wrong reason: both were the catalog order.
    Future<List<String>> feedFor(List<WorkoutSession> sessions) async {
      final c = _container(sessions);
      return (await c.read(rankedForYouProvider.future))
          .map((e) => e.id)
          .toList();
    }

    final chest =
        await feedFor([session('chest_a'), session('chest_a', daysAgo: 5)]);
    final legs =
        await feedFor([session('legs_a'), session('legs_a', daysAgo: 5)]);
    expect(chest, isNot(legs));
  });

  test('the ranked feed is the same set, only reordered', () async {
    final c = _container([session('legs_a')]);
    final feed = await c.read(rankedForYouProvider.future);
    expect(feed.map((e) => e.id).toSet(), _catalog.map((e) => e.id).toSet());
  });

  test('a session outside the window stops counting', () async {
    // The window is what makes the deficit a CURRENT measure rather than a
    // lifetime tally. Without it a muscle trained hard once, a year ago, stays
    // at the bottom of the feed forever.
    final stale = _container([session('chest_a', daysAgo: 30, sets: 20)]);
    final feed = await stale.read(rankedForYouProvider.future);
    expect(feed.map((e) => e.id), _catalog.map((e) => e.id),
        reason: 'a month-old session leaves every muscle equally neglected, '
            'which is the cold-start order');
  });

  test('sets, not sessions, are what count', () async {
    // Three one-set sessions and one three-set session are the same volume.
    // The old log-entry view could not tell them apart at all: it kept
    // `sets.last`, so both read as a single row per session and the
    // three-session fixture would have looked like three times the work.
    Future<List<String>> feedFor(List<WorkoutSession> sessions) async =>
        (await _container(sessions).read(rankedForYouProvider.future))
            .map((e) => e.id)
            .toList();

    final spread = await feedFor([
      session('chest_a', daysAgo: 1, sets: 1),
      session('chest_a', daysAgo: 2, sets: 1),
      session('chest_a', daysAgo: 3, sets: 1),
    ]);
    final oneGo = await feedFor([session('chest_a', daysAgo: 1, sets: 3)]);
    expect(spread, oneGo);
  });
}
