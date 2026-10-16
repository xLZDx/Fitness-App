/// App-root wiring of the unified-activity cloud path (S02 design 3.2, 6.2,
/// 12.1). Everything here is behind [ActivityFlags.cloudSync]
/// (`ACTIVITY_CLOUD_STREAMS`, default OFF): with the flag off no journal is
/// opened, no provider is overridden, nothing syncs and the app behaves as it
/// did before S02.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account_deletion/data/local_data_wipe.dart';
import '../../features/activity/repository/activity_aware_local_data_wipe.dart';
import '../../features/activity/repository/activity_journal.dart';
import '../../features/activity/repository/activity_journal_owner.dart';
import '../../features/activity/repository/activity_cloud_settings_client.dart';
import '../../features/activity/repository/activity_stream_uploader.dart';
import '../../features/activity/repository/activity_sync_repository.dart';
import '../../features/activity/repository/cloud_functions_activity_tombstone_pusher.dart';
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

/// The account-deletion device wipe extended with the journal wipe (design 6.2,
/// 7). With no journal open (flag off) [inner] is returned unchanged, so the
/// behaviour is exactly the pre-S02 one.
LocalDataWipe activityAwareLocalDataWipe(
  LocalDataWipe inner,
  ActivityJournal? journal, {
  ActivityJournalOwnerStore? ownerStore,
}) {
  if (journal == null) return inner;
  return ActivityAwareLocalDataWipe(
    inner: inner,
    journal: journal,
    ownerStore: ownerStore ?? PrefsActivityJournalOwnerStore(),
  );
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
        tombstonePusher: CloudFunctionsActivityTombstonePusher().push,
      );
      ref.onDispose(repo.dispose);
      return repo;
    }),
  ];
}

/// The opened journal (only overridden when the flag is on).
final activityJournalProvider = Provider<ActivityJournal?>((_) => null);

/// Owner uid record of the device-wide journal (cross-account guard).
final activityJournalOwnerStoreProvider = Provider<ActivityJournalOwnerStore>(
    (_) => PrefsActivityJournalOwnerStore());

/// Consent cache scoped to the signed-in account. Unknown (so: no upload)
/// until [signIn] has run.
class AccountScopedConsentStore implements CloudStreamsConsentStore {
  CloudStreamsConsentStore? _inner;

  Future<void> signIn(String uid) async {
    _inner = SharedPrefsCloudStreamsConsentStore(
        await SharedPreferences.getInstance(), uid);
  }

  @override
  Future<CloudStreamsConsent> read() async =>
      await _inner?.read() ?? CloudStreamsConsent.unknown;

  @override
  Future<void> write(CloudStreamsConsent value) async =>
      _inner?.write(value);
}

final activityConsentStoreProvider =
    Provider<AccountScopedConsentStore>((_) => AccountScopedConsentStore());

/// Consent cache plus the `setActivityCloudSettings` call.
final activityCloudSettingsClientProvider =
    Provider<ActivityCloudSettingsClient>((ref) => ActivityCloudSettingsClient(
          call: cloudFunctionsSettingsCall(),
          store: ref.watch(activityConsentStoreProvider),
        ));

/// The stream uploader; null unless the flag is on and a journal is open
/// (default OFF = no uploader exists).
final activityStreamUploaderProvider = Provider<ActivityStreamUploader?>((ref) {
  if (!ref.watch(activityFlagsProvider).cloudSync) return null;
  final journal = ref.watch(activityJournalProvider);
  if (journal == null) return null;
  return ActivityStreamUploader(
    journal: journal,
    callables: CloudFunctionsActivityStreamClient(),
    consent: ref.watch(activityCloudSettingsClientProvider),
    put: httpClientPutSender,
    flags: ref.watch(activityFlagsProvider),
  );
});

/// Consent-withdrawal presenter for the settings screen; null when off.
final activityConsentWithdrawalProvider =
    Provider<ActivityConsentWithdrawal?>((ref) {
  final uploader = ref.watch(activityStreamUploaderProvider);
  if (uploader == null) return null;
  return ActivityConsentWithdrawal(
    settings: ref.watch(activityCloudSettingsClientProvider),
    uploader: uploader,
  );
});

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
    final uploader = ref.read(activityStreamUploaderProvider);
    final settings = ref.read(activityCloudSettingsClientProvider);
    final consentStore = ref.read(activityConsentStoreProvider);
    final journal = ref.read(activityJournalProvider)!;
    final ownerStore = ref.read(activityJournalOwnerStoreProvider);
    unawaited(() async {
      // The journal is device-wide: when it belongs to another account it is
      // wiped first (design 17: the sign-out export offer is S03). Fail closed:
      // no sync and no upload unless this uid owns the journal.
      if (!await claimActivityJournal(
          journal: journal, store: ownerStore, uid: user.uid)) {
        debugPrint('activity: journal owner check failed; sync not started');
        return;
      }
      try {
        await ref.read(activitySyncRepositoryProvider).syncAll(retryConflicts: true);
      } catch (e) {
        debugPrint('activity: start sync failed (${e.runtimeType})');
      }
      // Stream upload: one run per app start, only with consent known granted.
      try {
        await consentStore.signIn(user.uid);
        await settings.load();
        await uploader?.runPending();
      } catch (e) {
        debugPrint('activity: start stream upload failed (${e.runtimeType})');
      }
    }());
  }, fireImmediately: true);
});
