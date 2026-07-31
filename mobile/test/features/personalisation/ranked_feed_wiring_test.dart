import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/personalisation/state/personalisation_providers.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/state/workout_log_providers.dart';

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

ExerciseItem ex(String id, List<String> muscles) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
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

/// A COMPLETED AND RATED session.
///
/// The rating is not decoration: `buildProfile` skips every log whose
/// difficulty is null, so an unrated workout teaches the model nothing. That
/// is a defensible design — a log with no rating carries no information about
/// how hard the work was — but it means the feed only personalises for someone
/// who answers the sheet that appears on "Mark complete". A fixture without it
/// produces an empty profile, the ranker returns its input untouched, and a
/// test written that way passes for the wrong reason.
WorkoutLogEntry log(String exerciseId,
        {int daysAgo = 2,
        DifficultyRating rating = DifficultyRating.tooEasy}) =>
    WorkoutLogEntry(
      id: 'log_$exerciseId$daysAgo',
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      completedAt: DateTime.now().subtract(Duration(days: daysAgo)),
      durationMinutes: 30,
      difficulty: rating,
    );

/// Serves the same three exercises the feed is overridden with.
///
/// Needed as well as the feed override, and the reason is the point of the
/// test: `fitnessProfileProvider` builds its muscle map from the REPOSITORY,
/// not from the feed. Without this the profile came back null, the ranker
/// returned its input untouched, and the first draft of these tests passed the
/// "no history" case and failed the two that matter — which is exactly what a
/// wiring bug looks like from the outside.
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

ProviderContainer _container(List<WorkoutLogEntry> logs) {
  final c = ProviderContainer(overrides: [
    forYouExercisesProvider.overrideWith((_) async => _catalog),
    equipmentRepositoryProvider.overrideWithValue(_FakeRepo()),
    workoutLogsProvider.overrideWith((_) => Stream.value(logs)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('with no history the filtered order is kept', () async {
    // Cold start. Inventing an order from nothing would be a guess dressed as
    // personalisation.
    final c = _container(const []);
    // The log stream has to deliver before the model is built from it.
    await c.read(workoutLogsProvider.future);
    await c.read(fitnessProfileProvider.future);
    final feed = await c.read(rankedForYouProvider.future);
    expect(feed.map((e) => e.id), _catalog.map((e) => e.id));
  });

  test('training one muscle group pushes it down the feed', () async {
    // The whole promise: what you have been doing least comes first.
    final c = _container([
      log('chest_a'),
      log('chest_a', daysAgo: 3),
      log('chest_a', daysAgo: 4),
    ]);
    // The log stream has to deliver before the model is built from it.
    await c.read(workoutLogsProvider.future);
    await c.read(fitnessProfileProvider.future);
    final feed = await c.read(rankedForYouProvider.future);

    expect(feed, hasLength(_catalog.length), reason: 'nothing may be dropped');
    expect(feed.last.id, 'chest_a',
        reason: 'the only trained group must not lead a feed that exists to '
            'surface what is being neglected');
  });

  test('two different histories produce two different feeds', () async {
    // The property that was missing. Before the wiring this passed trivially
    // for the wrong reason: both were the catalog order.
    Future<List<String>> feedFor(List<WorkoutLogEntry> logs) async {
      final c = _container(logs);
      await c.read(workoutLogsProvider.future);
      await c.read(fitnessProfileProvider.future);
      return (await c.read(rankedForYouProvider.future))
          .map((e) => e.id)
          .toList();
    }

    final chest = await feedFor([log('chest_a'), log('chest_a', daysAgo: 5)]);
    final legs = await feedFor([log('legs_a'), log('legs_a', daysAgo: 5)]);
    expect(chest, isNot(legs));
  });

  test('the ranked feed is the same set, only reordered', () async {
    final c = _container([log('legs_a')]);
    // The log stream has to deliver before the model is built from it.
    await c.read(workoutLogsProvider.future);
    await c.read(fitnessProfileProvider.future);
    final feed = await c.read(rankedForYouProvider.future);
    expect(feed.map((e) => e.id).toSet(), _catalog.map((e) => e.id).toSet());
  });
}
