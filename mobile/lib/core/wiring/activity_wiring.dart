/// App-root wiring of the unified-activity cloud path (S02 design 3.2, 6.2,
/// 12.1). Everything here is behind [ActivityFlags.cloudSync]
/// (`ACTIVITY_CLOUD_STREAMS`, default OFF): with the flag off no journal is
/// opened, no provider is overridden, nothing syncs and the app behaves as it
/// did before S02.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activity/repository/activity_journal.dart';
import '../../features/activity/repository/activity_sync_repository.dart';
import '../../features/activity/repository/file_activity_journal.dart';
import '../../features/activity/repository/firestore_activity_summary_backend.dart';
import '../../features/activity/state/sync_conflict_presenter.dart';
import '../../features/auth/data/auth_user.dart';
import '../../features/auth/state/auth_providers.dart';
import '../config/activity_flags.dart';

/// Opens and recovers the local journal when the flag is on; null when off or
/// when opening fails (the app must still start; the cloud path then stays
/// inactive).
Future<ActivityJournal?> openActivityJournal({
  ActivityFlags flags = ActivityFlags.compileTime,
}) async {
  if (!flags.cloudSync) return null;
  try {
    final journal = await FileActivityJournal.openDefault();
    await journal.start();
    return journal;
  } catch (e) {
    debugPrint('activity: journal not opened (${e.runtimeType})');
    return null;
  }
}

/// Provider overrides for the root `ProviderScope`. Empty unless the flag is on
/// and a journal was opened.
List<Override> activityRootOverrides({
  ActivityFlags flags = ActivityFlags.compileTime,
  ActivityJournal? journal,
}) {
  if (!flags.cloudSync || journal == null) return const [];
  return [
    activityJournalProvider.overrideWithValue(journal),
    activitySyncRepositoryProvider.overrideWith((ref) {
      final repo = ActivitySyncRepository(
        journal: journal,
        backend: FirestoreActivitySummaryBackend(),
      );
      ref.onDispose(repo.dispose);
      return repo;
    }),
  ];
}

/// The opened journal (only overridden when the flag is on).
final activityJournalProvider = Provider<ActivityJournal?>((_) => null);

/// Keep-alive wiring: watch it once from the app root widget. Runs one sync
/// pass (`syncAll(retryConflicts: true)`) per signed-in non-guest account at
/// app start. Never throws and never blocks the UI.
final activityCloudSyncWiringProvider = Provider<void>((ref) {
  if (!ref.watch(activityFlagsProvider).cloudSync) return;
  if (ref.watch(activityJournalProvider) == null) return;
  ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
    final user = next.valueOrNull;
    if (user == null || user.uid.isEmpty) return;
    if (user.provider == AuthProvider.anonymous) return;
    if (previous?.valueOrNull?.uid == user.uid) return;
    unawaited(ref
        .read(activitySyncRepositoryProvider)
        .syncAll(retryConflicts: true)
        .then<void>((_) {}, onError: (Object e) {
      debugPrint('activity: start sync failed (${e.runtimeType})');
    }));
  }, fireImmediately: true);
});
