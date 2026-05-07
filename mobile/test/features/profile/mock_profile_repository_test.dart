import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

void main() {
  group('MockProfileRepository', () {
    late MockProfileRepository repo;

    setUp(() => repo = MockProfileRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    test('load returns null for an unknown uid', () async {
      expect(await repo.load('nope'), isNull);
      expect(repo.cached('nope'), isNull);
    });

    test('save persists and load returns the same profile', () async {
      final p = UserProfile.empty('uid-1').copyWith(
        personal: const PersonalInfo(age: 28),
      );
      await repo.save(p);

      final loaded = await repo.load('uid-1');
      expect(loaded, isNotNull);
      expect(loaded!.uid, 'uid-1');
      expect(loaded.personal.age, 28);
      expect(repo.cached('uid-1')!.personal.age, 28);
    });

    test('watch replays the current value to new subscribers', () async {
      final p = UserProfile.empty('uid-1').copyWith(
        personal: const PersonalInfo(age: 35),
      );
      await repo.save(p);

      final first = await repo.watch('uid-1').first;
      expect(first?.personal.age, 35);
    });

    test('watch emits new values when save is called', () async {
      final emissions = <UserProfile?>[];
      final sub = repo.watch('uid-1').listen(emissions.add);
      // Wait for the replay to happen
      await Future<void>.delayed(Duration.zero);

      await repo.save(UserProfile.empty('uid-1'));
      await repo.save(UserProfile.empty('uid-1').copyWith(
        completedAt: DateTime(2026, 1, 1),
      ));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(emissions.length, greaterThanOrEqualTo(3)); // null replay + 2 saves
      expect(emissions.last?.hasCompletedOnboarding, isTrue);
    });

    test('delete removes the profile and emits null', () async {
      await repo.save(UserProfile.empty('uid-1'));
      expect(repo.cached('uid-1'), isNotNull);

      final emissions = <UserProfile?>[];
      final sub = repo.watch('uid-1').listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repo.delete('uid-1');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(repo.cached('uid-1'), isNull);
      expect(emissions.last, isNull);
    });
  });
}
