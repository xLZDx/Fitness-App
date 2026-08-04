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
  return (session) {
    final item = byId[session.exerciseId];
    if (item == null) return const [null];
    // Both bodies, not the user's one. Prefetch runs ahead of the session, and
    // the point of caching is that the clip is there whichever demonstration
    // the page ends up choosing — a profile edited between the prefetch and
    // the workout must not turn a cached session back into a streaming one.
    // `playableVideoFor` filters each one, so nothing is queued while the
    // library's host is still unchosen.
    //
    // A set, because 33 of the 343 exercises were filmed on one body only and
    // both lookups then answer with the same url. The prefetch loop downloads
    // whatever it is handed, so a duplicate would be a second download of a
    // file already on disk.
    return <String?>{
      item.videoUrl,
      item.playableVideoFor('girl'),
      item.playableVideoFor('men'),
    };
  };
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
      // The screened catalog, so a week of downloads never contains footage
      // for an exercise the user is not shown. A named behaviour change: an
      // injured user's prefetch is now smaller, and the clips it skips are
      // exactly the ones they could not have opened anyway.
      final resolve = videoUrlsFor ??
          videoUrlResolverFor(await ref.read(safeCatalogProvider.future));
      // Collect first, resolve once, then download.
      //
      // A licensed clip's catalog entry is an object key, not a URL, and Dio
      // cannot fetch `exercises/girl/Legs/Squat.mp4`. Resolving them one at a
      // time would also mean one round trip per clip; `resolveAll` batches,
      // chunks at the backend's cap of sixty, and drops only the clips whose
      // chunk failed rather than the whole week.
      final references = <String>{};
      for (final s in sessions) {
        if (s.scheduledFor.isBefore(now) || s.scheduledFor.isAfter(cutoff)) {
          continue;
        }
        for (final u in resolve(s)) {
          if (u != null && u.isNotEmpty) references.add(u);
        }
      }
      if (references.isEmpty) {
        state = const AsyncValue.data(null);
        return;
      }
      final playable = await ref.read(clipUrlResolverProvider)
          .resolveAll(references);
      for (final reference in references) {
        final url = playable[reference];
        // Absent means signing failed. Skipped rather than aborted: a week's
        // prefetch should deliver what it can, and the clip still streams.
        if (url == null) continue;
        // Cached under the REFERENCE, fetched from the signed URL. Keying on
        // the URL would put a fifteen-minute expiry in the filename and the
        // cache would never hit again.
        await cache.download(reference, from: url);
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
