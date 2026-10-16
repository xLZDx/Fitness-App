/// App-root wiring of the unified-activity cloud path (S02 design 3.2, 6.2,
/// 12.1). The journal is behind [ActivityFlags.journalEnabled]
/// (`ACTIVITY_LOCAL_JOURNAL` or `ACTIVITY_CLOUD_STREAMS`, default OFF); every
/// network or Firestore object is behind [ActivityFlags.cloudSync] alone. With
/// both flags off no journal is opened, no provider is overridden, nothing
/// syncs and the app behaves as it did before S02.
library;

import 'dart:async' show Timer, unawaited;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account_deletion/data/local_data_wipe.dart';
import '../../features/account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../features/activity/repository/activity_aware_local_data_wipe.dart';
import '../../features/activity/repository/activity_journal.dart';
import '../../features/activity/repository/activity_cloud_settings_client.dart';
import '../../features/activity/repository/activity_stream_uploader.dart';
import '../../features/activity/repository/activity_sync_repository.dart';
import '../../features/activity/repository/cloud_functions_activity_tombstone_pusher.dart';
import '../../features/activity/repository/firestore_activity_summary_backend.dart';
import '../../features/activity/repository/uid_scoped_activity_journal.dart';
import '../../features/activity/state/sync_conflict_presenter.dart';
import '../../features/auth/data/auth_user.dart';
import '../../features/auth/state/auth_providers.dart';
import '../config/activity_flags.dart';

/// Returns the account-scoped journal (UNBOUND, no I/O, cannot fail the app
/// start) when a journal flag is on; null when both are off. The journal of an
/// account is opened and recovered by [activityJournalBindingProvider] when
/// that account signs in. [factory] is for tests (temp directories, in-memory
/// keys).
Future<ActivityJournal?> openActivityJournal({
  ActivityFlags flags = ActivityFlags.compileTime,
  ActivityJournalFactory? factory,
}) async {
  if (!flags.journalEnabled) return null;
  return UidScopedActivityJournal(factory: factory);
}

/// The account-deletion device wipe extended with the journal wipe (design 6.2,
/// 7). With no journal (both flags off) [inner] is returned unchanged, so the
/// behaviour is exactly the pre-S02 one.
LocalDataWipe activityAwareLocalDataWipe(
  LocalDataWipe inner,
  ActivityJournal? journal,
) {
  if (journal == null) return inner;
  return ActivityAwareLocalDataWipe(inner: inner, journal: journal);
}

/// Provider overrides for the root `ProviderScope`. Empty unless a journal flag
/// is on and a journal was opened. The sync repository (Firestore backend,
/// tombstone pusher) is only constructed with [ActivityFlags.cloudSync].
List<Override> activityRootOverrides({
  ActivityFlags flags = ActivityFlags.compileTime,
  ActivityJournal? journal,
}) {
  if (!flags.journalEnabled || journal == null) return const [];
  return [
    activityJournalProvider.overrideWithValue(journal),
    if (flags.cloudSync)
      activitySyncRepositoryProvider.overrideWith((ref) {
        final repo = ActivitySyncRepository(
          journal: journal,
          backend: FirestoreActivitySummaryBackend(),
          tombstonePusher: CloudFunctionsActivityTombstonePusher().push,
          authUid: () => FirebaseAuth.instance.currentUser?.uid,
        );
        ref.onDispose(repo.dispose);
        return repo;
      }),
  ];
}

/// The opened journal (only overridden when a journal flag is on).
final activityJournalProvider = Provider<ActivityJournal?>((_) => null);

/// Keep-alive binding of the account-scoped journal (S02 remediation E1):
/// watch it once from the app root widget. Active whenever a journal flag is on,
/// independent of `cloudSync`. The signed-in uid (anonymous users included)
/// binds that account's journal; signed out unbinds it WITHOUT deleting any
/// data. A loading or error auth state without a value changes nothing. Sign-out
/// itself never wipes (the sign-out export offer is S03).
final activityJournalBindingProvider = Provider<void>((ref) {
  if (!ref.watch(activityFlagsProvider).journalEnabled) return;
  final AccountScopedJournal scoped;
  switch (ref.watch(activityJournalProvider)) {
    case final AccountScopedJournal s:
      scoped = s;
    default:
      return;
  }
  final timerFactory = ref.read(activityBindRetryTimerFactoryProvider);
  // At most one pending retry; every new auth value (or disposal) bumps
  // [generation], which cancels the pending retry and invalidates running ones.
  Timer? pending;
  var generation = 0;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    generation++;
    pending?.cancel();
    pending = null;
  });

  // The uid this wiring may bind right now: null when no user, an empty uid or
  // the account whose deletion is in progress (never re-create its scope).
  String? bindableUid() {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return null;
    if (uid == ref.read(accountBeingDeletedUidProvider)) return null;
    return uid;
  }

  Future<void> attempt(String? uid, int myGeneration, int retryIndex) async {
    var bound = false;
    try {
      bound = await scoped.bindUid(uid);
    } catch (e) {
      debugPrint('activity: journal bind failed (${e.runtimeType})');
    }
    // Every completion (success, false, exception) changes what a live
    // subscriber must show: publish the binding change.
    if (!disposed) _publishBindingChange(ref);
    // Unbinding (null) and a successful bind are final. A failed bind of a uid
    // would otherwise leave the journal unbound for the whole session.
    if (bound || uid == null) return;
    if (myGeneration != generation) return;
    if (retryIndex >= kActivityBindRetryDelays.length) {
      debugPrint('activity: journal bind gave up after $retryIndex retries');
      return;
    }
    pending?.cancel();
    pending = timerFactory(kActivityBindRetryDelays[retryIndex], () {
      pending = null;
      if (myGeneration != generation) return;
      // Retry only while the same account is still the one to bind.
      if (bindableUid() != uid) return;
      unawaited(attempt(uid, myGeneration, retryIndex + 1));
    });
  }

  ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
    if (!next.hasValue) return;
    generation++;
    pending?.cancel();
    pending = null;
    final uid = next.value?.uid;
    final deleting = ref.read(accountBeingDeletedUidProvider);
    final target = (uid == null || uid.isEmpty || uid == deleting) ? null : uid;
    unawaited(attempt(target, generation, 0));
  }, fireImmediately: true);
});

/// Tells the sync repository that the journal binding changed so a live
/// conflict presenter republishes (remediation G2). Only with `cloudSync` (the
/// repository provider exists only then); never throws. Callers check that
/// their own provider has not been disposed.
void _publishBindingChange(Ref ref) {
  try {
    if (!ref.read(activityFlagsProvider).cloudSync) return;
    ref.read(activitySyncRepositoryProvider).onJournalBindingChanged();
  } catch (e) {
    debugPrint('activity: binding change not published (${e.runtimeType})');
  }
}

/// Delays before the 1st..5th retry of a failed journal bind (at most 5).
const List<Duration> kActivityBindRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 60),
  Duration(minutes: 5),
  Duration(minutes: 5),
];

/// Creates the timer of a bind retry; tests override it with a fake.
typedef ActivityBindRetryTimerFactory = Timer Function(
    Duration delay, void Function() callback);

final activityBindRetryTimerFactoryProvider =
    Provider<ActivityBindRetryTimerFactory>(
        (_) => (delay, callback) => Timer(delay, callback));

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
    // Every run is bound to the account it started with (design 5.2 item 4).
    currentUid: () => _syncUid(ref.read(authUserProvider).valueOrNull),
  );
});

/// The uid the cloud path works for: null for no user, an empty uid or a guest.
String? _syncUid(AuthUser? user) {
  if (user == null || user.uid.isEmpty) return null;
  if (user.provider == AuthProvider.anonymous) return null;
  return user.uid;
}

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
  var disposed = false;
  ref.onDispose(() => disposed = true);
  ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
    final user = next.valueOrNull;
    final previousUid = _syncUid(previous?.valueOrNull);
    final nextUid = _syncUid(user);
    // The signed-in account changed or went away: stop the previous account's
    // queued and in-flight uploads before anything else happens.
    if (previousUid != null && previousUid != nextUid) {
      ref.read(activitySyncRepositoryProvider).onAccountChanged();
      ref.read(activityStreamUploaderProvider)?.cancelQueued();
    }
    if (user == null || nextUid == null) return;
    if (previousUid == nextUid) return;
    final uploader = ref.read(activityStreamUploaderProvider);
    final settings = ref.read(activityCloudSettingsClientProvider);
    final consentStore = ref.read(activityConsentStoreProvider);
    final journal = ref.read(activityJournalProvider)!;
    unawaited(() async {
      try {
        // The journal of this uid must be bound first (account-scoped
        // journals: ownership is the location). Fail closed: no sync and no
        // upload unless the bind succeeded. Nothing is ever wiped here.
        if (journal case final AccountScopedJournal scoped) {
          var bound = false;
          try {
            bound = await scoped.bindUid(nextUid);
          } finally {
            // Success, false or exception: a live subscriber must republish.
            if (!disposed) _publishBindingChange(ref);
          }
          if (!bound) {
            debugPrint('activity: journal bind failed; sync not started');
            return;
          }
        }
        // The account may have changed while the bind ran: do nothing more.
        if (_syncUid(ref.read(authUserProvider).valueOrNull) != nextUid) return;
        // Uploads were cancelled when the previous account went away; they
        // resume only now that this account's journal is bound.
        uploader?.resume();
        try {
          await ref
              .read(activitySyncRepositoryProvider)
              .syncAll(retryConflicts: true);
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
      } catch (e) {
        // Defensive: this closure is unawaited, so nothing may escape it.
        debugPrint('activity: start wiring failed (${e.runtimeType})');
      }
    }());
  }, fireImmediately: true);
});
