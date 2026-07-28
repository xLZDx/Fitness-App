import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';
import 'package:fitness_app/features/workouts/data/offline_video_cache.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/offline_video_providers.dart';

const _benchUrl = 'https://cdn.example.com/bench.mp4';

AssetEquipmentRepository _repoWithVideo() {
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
          id: 'bench',
          title: 'Bench press',
          equipmentId: 'rack',
          muscles: ['chest'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 25,
          summary: '',
          steps: [],
          videoUrl: _benchUrl,
        ),
      ],
    );
}

ScheduledSession _sessionInWindow(String exerciseId) => ScheduledSession(
      id: 's1',
      exerciseId: exerciseId,
      exerciseTitle: 'Bench press',
      scheduledFor: DateTime.now().add(const Duration(days: 1)),
      durationMinutes: 25,
    );

ProviderContainer _premiumContainer(
  InMemoryOfflineVideoCache cache, {
  AssetEquipmentRepository? repo,
  SubscriptionTier tier = SubscriptionTier.standard,
}) {
  return ProviderContainer(overrides: [
    effectiveTierProvider.overrideWithValue(tier),
    authUserProvider.overrideWith((_) => Stream.value(
          const AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'T'),
        )),
    offlineVideoCacheProvider.overrideWithValue(cache),
    if (repo != null) equipmentRepositoryProvider.overrideWithValue(repo),
  ]);
}

void main() {
  group('OfflinePrefetchAction.prefetchNext7Days', () {
    test('default path resolves videoUrls from the catalog and caches them',
        () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache, repo: _repoWithVideo());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      // No videoUrlsFor closure -> exercises the production DEFAULT (Design B):
      // exerciseId 'bench' -> equipment catalog -> videoUrl -> cache.
      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('bench')]);

      expect(cache.isCached(_benchUrl), isTrue,
          reason: 'default catalog resolution must actually cache the url');
      expect(await cache.sizeBytes(), greaterThan(0));
    });

    test('injected closure path caches the closure-supplied urls', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      // Exercises the seam Design A uses at the call site.
      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_sessionInWindow('bench')],
        videoUrlsFor: (s) => const ['https://cdn.example.com/injected.mp4'],
      );

      expect(cache.isCached('https://cdn.example.com/injected.mp4'), isTrue);
    });

    test('unknown exerciseId resolves to nothing and caches nothing', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache, repo: _repoWithVideo());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('missing')]);

      expect(await cache.sizeBytes(), 0);
    });

    test('free tier throws and caches nothing', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache,
          repo: _repoWithVideo(), tier: SubscriptionTier.free);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('bench')]);

      expect(
          container.read(offlinePrefetchActionProvider).hasError, isTrue);
      expect(await cache.sizeBytes(), 0);
    });
  });
}
