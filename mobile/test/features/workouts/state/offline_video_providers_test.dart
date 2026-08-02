import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/clip_url_resolver.dart';
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
  ClipUrlResolver? resolver,
}) {
  return ProviderContainer(overrides: [
    effectiveTierProvider.overrideWithValue(tier),
    authUserProvider.overrideWith((_) => Stream.value(
          const AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'T'),
        )),
    offlineVideoCacheProvider.overrideWithValue(cache),
    clipUrlResolverProvider
        .overrideWithValue(resolver ?? PassthroughClipUrlResolver()),
    if (repo != null) equipmentRepositoryProvider.overrideWithValue(repo),
  ]);
}

/// A licensed clip: the catalog holds an object key, not a URL.
const _licensedRef = 'exercises/girl/Legs/Barbell Squat.mp4';

AssetEquipmentRepository _repoWithLicensedClip() {
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
          id: 'squat',
          title: 'Barbell Squat',
          equipmentId: 'rack',
          muscles: ['legs'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 25,
          summary: '',
          steps: [],
          video: {'girl': _licensedRef, 'men': _licensedRef},
        ),
      ],
    );
}

void main() {
  group('licensed clips survive the offline prefetch', () {
    // The paid offline-download feature broke the moment the catalog started
    // holding object keys: it handed `exercises/girl/Legs/Squat.mp4` straight
    // to Dio, which cannot fetch it. And the obvious repair -- resolve, then
    // download the signed URL -- would have been worse, because the cache
    // filename is sha1 of what it is given and a signed URL is different every
    // fifteen minutes. It would have re-downloaded the whole week, every week,
    // while reporting success.

    test('an object key is fetched from its signed url', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache, repo: _repoWithLicensedClip());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('squat')]);

      expect(cache.isCached(_licensedRef), isTrue,
          reason: 'a licensed clip must reach the offline library');
      expect(cache.fetchedFor(_licensedRef), startsWith('https://'),
          reason: 'Dio cannot fetch an object key');
    });

    test('it is filed under the reference, not the expiring url', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache, repo: _repoWithLicensedClip());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('squat')]);

      // The player looks the clip up by the reference. If the key were the
      // signed url, this lookup would miss for the rest of the app's life.
      expect(cache.isCached(_licensedRef), isTrue);
      expect(cache.fetchedFor(_licensedRef), isNot(_licensedRef));
      expect(cache.isCached(cache.fetchedFor(_licensedRef)!), isFalse,
          reason: 'the signed url must not itself be a cache key');
    });

    test('a clip that cannot be signed is skipped, not fatal', () async {
      // One dead object must not cost a premium user the other six days.
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(
        cache,
        repo: _repoWithLicensedClip(),
        resolver: PassthroughClipUrlResolver(fail: true),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('squat')]);

      expect(cache.isCached(_licensedRef), isFalse);
      expect(container.read(offlinePrefetchActionProvider).hasError, isFalse,
          reason: 'a signing failure is a skipped clip, not a failed prefetch');
    });

    test('a public url still goes straight through', () async {
      // The 268 exercises still served from the public bucket must not care
      // that any of this happened.
      final cache = InMemoryOfflineVideoCache();
      final container = _premiumContainer(cache, repo: _repoWithVideo());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_sessionInWindow('bench')]);

      expect(cache.isCached(_benchUrl), isTrue);
      expect(cache.fetchedFor(_benchUrl), _benchUrl);
    });
  });

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
