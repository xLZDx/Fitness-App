import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

AssetEquipmentRepository _repoWithRack() {
  return AssetEquipmentRepository()
    ..seedForTests(
      equipment: const [
        EquipmentItem(
          id: 'rack',
          name: 'Power Rack',
          manufacturer: 'Rogue',
          category: 'strength',
          description: '',
        ),
      ],
      exercises: const [
        ExerciseItem(
          id: 'safe_bench',
          title: 'Bench press',
          equipmentId: 'rack',
          muscles: ['chest'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 25,
          summary: 'Push pattern',
          steps: [],
        ),
        ExerciseItem(
          id: 'risky_squat',
          title: 'Back squat',
          equipmentId: 'rack',
          muscles: ['quads'],
          difficulty: ExerciseDifficulty.intermediate,
          durationMinutes: 30,
          summary: 'Compound lift',
          steps: [],
          contraindications: ['knee'],
        ),
      ],
    );
}

ProviderContainer _container({
  required AssetEquipmentRepository repo,
  required MockProfileRepository profileRepo,
  required String uid,
}) {
  return ProviderContainer(overrides: [
    equipmentRepositoryProvider.overrideWithValue(repo),
    profileRepositoryProvider.overrideWithValue(profileRepo),
    authUserProvider.overrideWith((_) => Stream.value(
          AuthUser(uid: uid, email: 'a@b.com', displayName: 'Test'),
        )),
  ]);
}

void main() {
  group('recommendedExercisesProvider', () {
    test('returns every exercise when the user has no injuries', () async {
      final profileRepo = MockProfileRepository(latency: Duration.zero);
      const uid = 'no-injury-user';
      await profileRepo.save(UserProfile(
        uid: uid,
        completedAt: DateTime(2026, 1, 1),
      ));

      final container = _container(
        repo: _repoWithRack(),
        profileRepo: profileRepo,
        uid: uid,
      );
      addTearDown(container.dispose);

      // Let the auth + profile streams settle so currentProfileProvider has
      // emitted the seeded UserProfile before the recommendation provider runs.
      await container.read(authUserProvider.future);
      await container.read(currentProfileProvider.future);

      final rec =
          await container.read(recommendedExercisesProvider('rack').future);
      expect(rec.items.map((e) => e.id),
          containsAll(['safe_bench', 'risky_squat']));
      expect(rec.hiddenForInjury, 0);
    });

    test('drops contraindicated exercises and reports the count', () async {
      final profileRepo = MockProfileRepository(latency: Duration.zero);
      const uid = 'knee-user';
      await profileRepo.save(UserProfile(
        uid: uid,
        health: const HealthHistory(injuries: [
          Injury(bodyPart: 'left knee', type: 'sprain'),
        ]),
        completedAt: DateTime(2026, 1, 1),
      ));

      final container = _container(
        repo: _repoWithRack(),
        profileRepo: profileRepo,
        uid: uid,
      );
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      await container.read(currentProfileProvider.future);

      final rec =
          await container.read(recommendedExercisesProvider('rack').future);
      expect(rec.items.map((e) => e.id), ['safe_bench']);
      expect(rec.hiddenForInjury, 1);
    });
  });

  group('forYouExercisesProvider', () {
    test('strips contraindicated exercises across the whole catalog',
        () async {
      final profileRepo = MockProfileRepository(latency: Duration.zero);
      const uid = 'knee-user';
      await profileRepo.save(UserProfile(
        uid: uid,
        health: const HealthHistory(injuries: [
          Injury(bodyPart: 'knee', type: 'sprain'),
        ]),
        completedAt: DateTime(2026, 1, 1),
      ));

      final container = _container(
        repo: _repoWithRack(),
        profileRepo: profileRepo,
        uid: uid,
      );
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      await container.read(currentProfileProvider.future);

      final list = await container.read(forYouExercisesProvider.future);
      expect(list.map((e) => e.id), ['safe_bench']);
    });
  });
}
