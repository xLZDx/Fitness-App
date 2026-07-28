import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/state/subscription_providers.dart';
import '../data/offline_video_cache.dart';
import '../data/scheduled_session.dart';
import 'scheduled_session_providers.dart';

final offlineVideoCacheProvider = Provider<OfflineVideoCache>((ref) {
  // Default = in-memory mock; main.dart binds [FileOfflineVideoCache] in
  // production builds.
  return InMemoryOfflineVideoCache();
});

/// Builds the production video-URL resolver: maps a scheduled session's
/// [ScheduledSession.exerciseId] to its [ExerciseItem.videoUrl] via the
/// resolved equipment catalog. Shared by the explicit call-site wiring
/// (workouts_page) and this notifier's default path, so the lookup lives once.
Iterable<String?> Function(ScheduledSession) videoUrlResolverFor(
    List<ExerciseItem> catalog) {
  final byId = {for (final e in catalog) e.id: e};
  return (session) => [byId[session.exerciseId]?.videoUrl];
}

/// Pulls the [videoUrl] of every scheduled session in the next 7 days
/// into the offline cache. Premium-tier feature; throws if the caller
/// is on free.
class OfflinePrefetchAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> prefetchNext7Days({
    Iterable<ScheduledSession>? overrideSessions,
    Iterable<String?> Function(ScheduledSession)? videoUrlsFor,
  }) async {
    state = const AsyncValue.loading();
    try {
      final tier = ref.read(effectiveTierProvider);
      if (tier == SubscriptionTier.free) {
        throw StateError(
          'Offline downloads are a Supporter+ benefit.',
        );
      }
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Sign in first');
      }
      final sessions = overrideSessions ??
          ref.read(scheduledSessionsProvider).valueOrNull ??
          const [];
      final now = DateTime.now();
      final cutoff = now.add(const Duration(days: 7));
      final cache = ref.read(offlineVideoCacheProvider);
      // When no closure is injected (production default), resolve each
      // session's exercise videoUrl from the equipment catalog. Tests inject
      // [videoUrlsFor] deterministically; the `??` short-circuits so the
      // catalog is only read when no closure is supplied.
      final resolve = videoUrlsFor ??
          videoUrlResolverFor(await ref.read(allExercisesProvider.future));
      for (final s in sessions) {
        if (s.scheduledFor.isBefore(now) || s.scheduledFor.isAfter(cutoff)) {
          continue;
        }
        final urls = resolve(s);
        for (final u in urls) {
          if (u == null || u.isEmpty) continue;
          await cache.download(u);
        }
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final offlinePrefetchActionProvider =
    NotifierProvider<OfflinePrefetchAction, AsyncValue<void>>(
        OfflinePrefetchAction.new);
