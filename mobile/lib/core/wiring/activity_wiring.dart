/// App-root wiring of the unified-activity cloud path (S02 design 3.2, 6.2,
/// 12.1). The journal is behind [ActivityFlags.journalEnabled]
/// (`ACTIVITY_LOCAL_JOURNAL`, default ON since S03, or `ACTIVITY_CLOUD_STREAMS`,
/// default OFF); every network or Firestore object is behind
/// [ActivityFlags.cloudSync] alone. With both flags off no journal is opened, no
/// provider is overridden and nothing syncs.
library;

import 'dart:async' show Timer, scheduleMicrotask, unawaited;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart' show debugPrint, immutable;
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
          accountBeingDeleted: _accountBeingDeletedSupplier(ref),
        );
        ref.onDispose(repo.dispose);
        return repo;
      }),
  ];
}

/// Supplies the uid whose account deletion is in progress (null = none), read
/// from [accountBeingDeletedUidProvider] through the provider that owns [ref].
/// The provider layer is the seam: [activityRootOverrides] has no `ref`, but the
/// override body it creates does. After the owning provider is disposed the
/// supplier answers null (a disposed repository or uploader is dead anyway).
String? Function() _accountBeingDeletedSupplier(Ref ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return () => disposed ? null : ref.read(accountBeingDeletedUidProvider);
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
  // The status Notifier is only WRITTEN to; reading it builds a default state,
  // so the provider needs no override to build.
  final status = ref.read(activityBindStatusProvider.notifier);
  final controller = _ActivityBindController(
    scoped: scoped,
    timerFactory: timerFactory,
    // The uid this wiring may bind right now: null when no user, an empty uid
    // or the account whose deletion is in progress (never re-create its scope).
    bindableUid: () =>
        _bindableUid(ref, ref.read(authUserProvider).valueOrNull?.uid),
    publishBindingChange: () => _publishBindingChange(ref),
    sink: status._publish,
  );
  status._attach(controller);
  ref.onDispose(() {
    status._detach(controller);
    controller.dispose();
  });

  // While this provider builds, status writes are deferred to a microtask (a
  // provider must not modify another provider during its initialisation).
  controller.building = true;
  ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
    if (!next.hasValue) return;
    controller.onAuthValue(_bindableUid(ref, next.value?.uid));
  }, fireImmediately: true);
  controller.building = false;
});

/// Result of [ActivityBindStatusNotifier.retryNow] (design 2.1 item 3, D2).
enum RetryResult {
  /// An attempt began.
  started,

  /// An attempt was already in flight; no new attempt.
  busy,

  /// Bound, no journal wiring (`failedToOpen`) or no bindable uid.
  notApplicable,
}

/// Phase of the journal bind of the current account.
enum BindPhase {
  /// No bindable uid (signed out, empty uid, account being deleted).
  none,

  /// First attempt or an armed automatic retry.
  binding,

  /// The journal of [ActivityBindStatus.uid] is bound.
  bound,

  /// The automatic retry schedule is exhausted.
  gaveUp,
}

/// The published outcome of the journal bind (additive companion of
/// [activityJournalBindingProvider]). [generation] counts auth values; a
/// consumer compares [uid] and [generation] with its own to reject stale data.
@immutable
class ActivityBindStatus {
  const ActivityBindStatus({
    this.phase = BindPhase.none,
    this.uid,
    this.generation = 0,
    this.bindBusy = false,
    this.recoveredAbsentCount = 0,
    this.streamLostCount = 0,
  });

  final BindPhase phase;

  /// The uid the phase belongs to; null for [BindPhase.none].
  final String? uid;
  final int generation;

  /// True while a bind attempt is in flight. It is NOT part of availability.
  final bool bindBusy;

  /// Activities dropped at the last successful recovery (no valid COMMIT).
  final int recoveredAbsentCount;

  /// Activities found `streamLost` at the last successful recovery.
  final int streamLostCount;

  @override
  bool operator ==(Object other) =>
      other is ActivityBindStatus &&
      other.phase == phase &&
      other.uid == uid &&
      other.generation == generation &&
      other.bindBusy == bindBusy &&
      other.recoveredAbsentCount == recoveredAbsentCount &&
      other.streamLostCount == streamLostCount;

  @override
  int get hashCode => Object.hash(phase, uid, generation, bindBusy,
      recoveredAbsentCount, streamLostCount);
}

/// Publishes [ActivityBindStatus] and exposes [retryNow] ("Try again"). The
/// retry state machine itself lives in the controller of
/// [activityJournalBindingProvider]; without it (no journal wiring) [retryNow]
/// is [RetryResult.notApplicable].
class ActivityBindStatusNotifier extends Notifier<ActivityBindStatus> {
  _ActivityBindController? _controller;

  @override
  ActivityBindStatus build() => const ActivityBindStatus();

  void _attach(_ActivityBindController c) => _controller = c;

  void _detach(_ActivityBindController c) {
    if (identical(_controller, c)) _controller = null;
  }

  void _publish(ActivityBindStatus s) {
    if (state != s) state = s;
  }

  /// One manual attempt through the same state machine as the automatic
  /// retries. Returns at once; the outcome arrives through [state].
  Future<RetryResult> retryNow() async =>
      _controller?.retryNow() ?? RetryResult.notApplicable;
}

final activityBindStatusProvider =
    NotifierProvider<ActivityBindStatusNotifier, ActivityBindStatus>(
        ActivityBindStatusNotifier.new);

enum _AttemptSource { automatic, manual }

enum _BindState { none, firstAttempt, waiting, gaveUp, bound }

/// The bind retry state machine (design 2.1 item 3): Idle/Bound, Attempting,
/// WaitingRetry and GaveUp. One machine serves automatic and manual attempts;
/// at most one `bindUid` is in flight per generation (a generation is one auth
/// value). The automatic schedule is [kActivityBindRetryDelays].
class _ActivityBindController {
  _ActivityBindController({
    required this.scoped,
    required this.timerFactory,
    required this.bindableUid,
    required this.publishBindingChange,
    required this.sink,
  });

  final AccountScopedJournal scoped;
  final ActivityBindRetryTimerFactory timerFactory;
  final String? Function() bindableUid;
  final void Function() publishBindingChange;
  final void Function(ActivityBindStatus) sink;

  /// True only while the owning provider builds: status writes are deferred.
  bool building = false;

  Timer? _pending;
  int _generation = 0;
  bool _disposed = false;
  bool _flushScheduled = false;
  bool _inFlight = false;
  String? _uid;
  _BindState _state = _BindState.none;

  /// Index of the armed (or last fired) automatic delay; -1 before the first.
  int _armedIndex = -1;
  int _absent = 0;
  int _lost = 0;

  /// A new auth value: new generation, everything resets, the attempt for
  /// [target] (null = unbind) starts at once.
  void onAuthValue(String? target) {
    _generation++;
    _cancelTimer();
    _inFlight = false;
    _armedIndex = -1;
    _absent = 0;
    _lost = 0;
    _uid = target;
    _state = target == null ? _BindState.none : _BindState.firstAttempt;
    unawaited(_run(target, _generation, _AttemptSource.automatic));
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _cancelTimer();
    _inFlight = false;
  }

  RetryResult retryNow() {
    if (_disposed) return RetryResult.notApplicable;
    final uid = _uid;
    if (uid == null || bindableUid() != uid) return RetryResult.notApplicable;
    if (_inFlight) return RetryResult.busy;
    if (_state != _BindState.waiting && _state != _BindState.gaveUp) {
      return RetryResult.notApplicable;
    }
    unawaited(_run(uid, _generation, _AttemptSource.manual));
    return RetryResult.started;
  }

  void _cancelTimer() {
    _pending?.cancel();
    _pending = null;
  }

  void _arm(int index, int myGeneration) {
    _pending?.cancel();
    _armedIndex = index;
    _pending = timerFactory(kActivityBindRetryDelays[index], () {
      _pending = null;
      if (myGeneration != _generation) return;
      final uid = _uid;
      // Retry only while the same account is still the one to bind.
      if (bindableUid() != uid) return;
      // A bind is in flight (a manual attempt): do nothing and re-arm with the
      // SAME index, so the retry is neither lost nor consumed twice.
      if (_inFlight) {
        _arm(index, myGeneration);
        return;
      }
      unawaited(_run(uid, myGeneration, _AttemptSource.automatic));
    });
  }

  Future<void> _run(
      String? uid, int myGeneration, _AttemptSource source) async {
    _inFlight = true;
    _emit();
    var bound = false;
    try {
      bound = await scoped.bindUid(uid);
    } catch (e) {
      debugPrint('activity: journal bind failed (${e.runtimeType})');
    }
    // Every completion (success, false, exception) changes what a live
    // subscriber must show: publish the binding change.
    if (!_disposed) publishBindingChange();
    // A stale completion touches nothing else.
    if (myGeneration != _generation) return;
    _inFlight = false;
    if (uid == null) {
      // Unbinding is final, whatever the result.
      _state = _BindState.none;
      _emit();
      return;
    }
    if (bound) {
      _cancelTimer();
      _armedIndex = -1;
      _state = _BindState.bound;
      _readRecoveryCounts();
      _emit();
      return;
    }
    if (source == _AttemptSource.manual) {
      // A failed manual attempt keeps the state, the timer and the index.
      _emit();
      return;
    }
    final next = _armedIndex + 1;
    if (next >= kActivityBindRetryDelays.length) {
      debugPrint('activity: journal bind gave up after $next retries');
      _cancelTimer();
      _state = _BindState.gaveUp;
      _emit();
      return;
    }
    _arm(next, myGeneration);
    _state = _BindState.waiting;
    _emit();
  }

  /// Counts of the last recovery, read AFTER a successful bind. A journal
  /// without [RecoveryReportSource] yields zeros.
  void _readRecoveryCounts() {
    _absent = 0;
    _lost = 0;
    final source = scoped;
    if (source is! RecoveryReportSource) return;
    try {
      final report = source.lastRecoveryReport;
      _absent = report?.absent.length ?? 0;
      _lost = report?.streamLost.length ?? 0;
    } catch (e) {
      debugPrint('activity: recovery report unreadable (${e.runtimeType})');
    }
  }

  ActivityBindStatus _snapshot() => ActivityBindStatus(
        phase: switch (_state) {
          _BindState.none => BindPhase.none,
          _BindState.firstAttempt || _BindState.waiting => BindPhase.binding,
          _BindState.gaveUp => BindPhase.gaveUp,
          _BindState.bound => BindPhase.bound,
        },
        uid: _state == _BindState.none ? null : _uid,
        generation: _generation,
        bindBusy: _inFlight,
        recoveredAbsentCount: _absent,
        streamLostCount: _lost,
      );

  void _emit() {
    if (_disposed) return;
    if (building) {
      if (_flushScheduled) return;
      _flushScheduled = true;
      scheduleMicrotask(() {
        _flushScheduled = false;
        if (!_disposed) sink(_snapshot());
      });
      return;
    }
    sink(_snapshot());
  }
}

/// The uid a wiring may bind right now: null for no user, an empty uid or the
/// account whose deletion is in progress (its scope is never re-created). The
/// single place of this rule, shared by the binding provider and the cloud
/// sync wiring.
String? _bindableUid(Ref ref, String? uid) {
  if (uid == null || uid.isEmpty) return null;
  if (uid == ref.read(accountBeingDeletedUidProvider)) return null;
  return uid;
}

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
/// until [signIn] has run. It holds ONE account at a time; [boundUid] is the
/// uid its cached consent belongs to. Every [signIn] and [signOut] starts a new
/// generation: a [signIn] that finishes after a newer [signIn] or [signOut]
/// does nothing. No stored consent key is ever deleted here.
class AccountScopedConsentStore implements CloudStreamsConsentStore {
  CloudStreamsConsentStore? _inner;
  String? _boundUid;
  int _generation = 0;

  /// Completes (never with an error) when the current generation's store is
  /// open, so a read or write issued meanwhile waits instead of being dropped.
  Future<void> _ready = Future<void>.value();

  @override
  String? get boundUid => _boundUid;

  /// Binds the store to [uid]. [boundUid] is [uid] at once; reads and writes
  /// wait for the preferences to open. Completes without effect when a newer
  /// [signIn] or [signOut] happened meanwhile.
  Future<void> signIn(String uid) {
    final myGeneration = ++_generation;
    _inner = null;
    _boundUid = uid;
    final opening = _open(uid, myGeneration);
    _ready = opening.then<void>((_) {}, onError: (Object _) {});
    return opening;
  }

  Future<void> _open(String uid, int myGeneration) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (myGeneration != _generation) return;
      _inner = SharedPrefsCloudStreamsConsentStore(prefs, uid);
    } catch (_) {
      if (myGeneration == _generation) _boundUid = null;
      rethrow;
    }
  }

  /// Unbinds the store (account change or sign-out) and invalidates any
  /// in-flight [signIn]. Stored consent of every account stays untouched.
  void signOut() {
    _generation++;
    _inner = null;
    _boundUid = null;
    _ready = Future<void>.value();
  }

  @override
  Future<CloudStreamsConsent> read() async {
    final myGeneration = _generation;
    await _ready;
    if (myGeneration != _generation) return CloudStreamsConsent.unknown;
    return await _inner?.read() ?? CloudStreamsConsent.unknown;
  }

  /// Persists [value] for the bound account. Throws [StateError] when no
  /// account is bound (or it changed while waiting): a write is never dropped
  /// silently.
  @override
  Future<void> write(CloudStreamsConsent value) async {
    final myGeneration = _generation;
    await _ready;
    final inner = _inner;
    if (myGeneration != _generation || inner == null) {
      throw StateError('consent store is not bound to an account');
    }
    await inner.write(value);
  }
}

final activityConsentStoreProvider =
    Provider<AccountScopedConsentStore>((_) => AccountScopedConsentStore());

/// Consent cache plus the `setActivityCloudSettings` call.
final activityCloudSettingsClientProvider =
    Provider<ActivityCloudSettingsClient>((ref) => ActivityCloudSettingsClient(
          call: cloudFunctionsSettingsCall(),
          // Remediation J2: the live account the callable will run as.
          currentUid: () => FirebaseAuth.instance.currentUser?.uid,
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
    // Deletion in progress stops uploads (stored data is untouched).
    accountBeingDeleted: _accountBeingDeletedSupplier(ref),
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
  // Start generation: incremented on every auth value with a real change, on an
  // account deletion that starts for the signed-in uid and on disposal. Every
  // asynchronous start continuation re-verifies it (and the uid) after each
  // await, so an obsolete account's continuation does nothing.
  var startGeneration = 0;
  ref.onDispose(() {
    disposed = true;
    startGeneration++;
  });
  ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
    final user = next.valueOrNull;
    final previousUid = _syncUid(previous?.valueOrNull);
    final nextUid = _syncUid(user);
    final previousRaw = previous?.valueOrNull?.uid;
    if (previousRaw != user?.uid || previousUid != nextUid) startGeneration++;
    final settings = ref.read(activityCloudSettingsClientProvider);
    final consentStore = ref.read(activityConsentStoreProvider);
    // The signed-in account changed or went away: stop the previous account's
    // queued and in-flight uploads before anything else happens.
    // Decided on the RAW uid (anonymous users included): an anonymous user X
    // replaced by a real user B must also drop X's caches and queued uploads.
    if (previousRaw != null &&
        previousRaw.isNotEmpty &&
        previousRaw != user?.uid) {
      // Remediation I2: the consent cache and state belonged to the previous
      // account: unbind them FIRST, each step isolated, so an exception in
      // [onAccountChanged] can never leave the previous account's consent
      // bound. Stored consent of any account is NOT deleted.
      try {
        consentStore.signOut();
      } catch (e) {
        debugPrint('activity: consent unbind failed (${e.runtimeType})');
      }
      try {
        settings.reset();
      } catch (e) {
        debugPrint('activity: consent reset failed (${e.runtimeType})');
      }
      ref.read(activitySyncRepositoryProvider).onAccountChanged();
      ref.read(activityStreamUploaderProvider)?.cancelQueued();
    }
    if (user == null || nextUid == null) return;
    if (previousUid == nextUid) return;
    final uploader = ref.read(activityStreamUploaderProvider);
    final journal = ref.read(activityJournalProvider)!;
    final myUid = nextUid;
    final myGeneration = startGeneration;
    // True only while this start is still the current one: not disposed, no
    // newer auth change, the same signed-in account, and that account is not
    // being deleted.
    bool current() =>
        !disposed &&
        myGeneration == startGeneration &&
        _syncUid(ref.read(authUserProvider).valueOrNull) == myUid &&
        ref.read(accountBeingDeletedUidProvider) != myUid;
    unawaited(() async {
      try {
        if (!current()) {
          // Keep the observable skip log of the deletion-in-progress case (the
          // check below used to be the only place that logged it).
          if (ref.read(accountBeingDeletedUidProvider) == myUid) {
            debugPrint('activity: account is being deleted; sync not started');
          }
          return;
        }
        // Remediation I2: the consent of this account depends neither on the
        // journal nor on the sync, so it is bound and loaded first. A failing
        // journal bind or a long syncAll no longer leaves the store unbound.
        try {
          await consentStore.signIn(myUid);
          if (!current()) return;
          await settings.load();
        } catch (e) {
          debugPrint('activity: consent load failed (${e.runtimeType})');
        }
        if (!current()) return;
        // The journal of this uid must be bound first (account-scoped
        // journals: ownership is the location). Fail closed: no sync and no
        // upload unless the bind succeeded. Nothing is ever wiped here.
        if (journal case final AccountScopedJournal scoped) {
          // The account whose deletion is in progress is never re-bound (same
          // rule as the binding provider).
          if (_bindableUid(ref, nextUid) == null) {
            debugPrint('activity: account is being deleted; sync not started');
            return;
          }
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
        if (!current()) return;
        try {
          await ref
              .read(activitySyncRepositoryProvider)
              .syncAll(retryConflicts: true);
        } catch (e) {
          debugPrint('activity: start sync failed (${e.runtimeType})');
        }
        if (!current()) return;
        // Stream upload: one run per app start, only with consent known granted.
        // The consent was loaded at the start of this closure; `current()` was
        // just re-verified, directly before the resume.
        try {
          // Uploads were cancelled when the previous account went away; they
          // resume only now that THIS account's consent is loaded and verified.
          uploader?.resume();
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

  // An account deletion that starts for the signed-in account stops sync and
  // uploads at once and invalidates a pending start. Stored data (journal,
  // consent) is untouched.
  ref.listen<String?>(accountBeingDeletedUidProvider, (previous, next) {
    if (next == null || next.isEmpty) return;
    if (ref.read(authUserProvider).valueOrNull?.uid != next) return;
    startGeneration++;
    ref.read(activitySyncRepositoryProvider).onAccountChanged();
    ref.read(activityStreamUploaderProvider)?.cancelQueued();
  });
});
