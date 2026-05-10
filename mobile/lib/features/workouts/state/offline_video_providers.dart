import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
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
      for (final s in sessions) {
        if (s.scheduledFor.isBefore(now) || s.scheduledFor.isAfter(cutoff)) {
          continue;
        }
        // The default URL pull strategy: take the session's exerciseId and
        // ask the videoUrlsFor closure if provided. Production wires it
        // through the equipment repository; tests inject deterministically.
        final urls = videoUrlsFor?.call(s) ?? const <String?>[];
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
