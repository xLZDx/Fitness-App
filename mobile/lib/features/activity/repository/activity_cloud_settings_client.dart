/// Client side of the cloud-stream consent (S02 design 5.3, 9, 9.1; test plan
/// I17, I28).
///
/// [ActivityCloudSettingsClient] calls `setActivityCloudSettings` and caches the
/// consent state the client knows; the cache is the only thing the uploader
/// consults ([CloudStreamsConsentView]). An unknown state is "not granted", so
/// nothing is uploaded before consent is known.
///
/// [ActivityConsentWithdrawal] is the withdrawal flow as a presenter:
/// [withdraw] stops queued uploads at once (before any network call) and
/// records the withdrawal; it then OFFERS "delete my cloud streams now", which
/// is the separate method [deleteCloudStreamsNow] (calls
/// `setActivityCloudSettings` with `deleteExisting` once). Not calling it leaves
/// cloud streams in place. Neither path touches local data or summaries.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/functions_region.dart';
import 'account_changed.dart';
import 'activity_stream_uploader.dart';

// Existing importers keep reaching the exception through this library.
export 'account_changed.dart' show ConsentAccountChangedException, isAccountChangedRefusal;

/// Must equal `CLOUD_STREAMS_CONSENT_VERSION` of the server (`settings.ts`).
const int kCloudStreamsConsentVersion = 1;

enum CloudStreamsConsent { unknown, granted, withdrawn }

/// Persistence of the cached consent (per account is the caller's job: pass a
/// store scoped to the signed-in uid).
abstract class CloudStreamsConsentStore {
  /// The uid the cached consent of this store belongs to; null when the store
  /// is not (yet) bound to an account.
  String? get boundUid;

  Future<CloudStreamsConsent> read();
  Future<void> write(CloudStreamsConsent value);
}

class InMemoryCloudStreamsConsentStore implements CloudStreamsConsentStore {
  InMemoryCloudStreamsConsentStore({this.boundUid});

  @override
  String? boundUid;

  CloudStreamsConsent _value = CloudStreamsConsent.unknown;
  @override
  Future<CloudStreamsConsent> read() async => _value;
  @override
  Future<void> write(CloudStreamsConsent value) async => _value = value;
}

/// Keeps the cached consent in `SharedPreferences`, one key per account.
class SharedPrefsCloudStreamsConsentStore implements CloudStreamsConsentStore {
  SharedPrefsCloudStreamsConsentStore(this._prefs, String uid)
      : boundUid = uid,
        _key = 'activity.cloudStreamsConsent.$uid';

  final SharedPreferences _prefs;
  final String _key;

  @override
  final String? boundUid;

  @override
  Future<CloudStreamsConsent> read() async {
    final raw = _prefs.getString(_key);
    for (final v in CloudStreamsConsent.values) {
      if (v.name == raw) return v;
    }
    return CloudStreamsConsent.unknown;
  }

  @override
  Future<void> write(CloudStreamsConsent value) async {
    await _prefs.setString(_key, value.name);
  }
}

/// Callable seam: sends the request map, returns the response map.
typedef ActivityCloudSettingsCall = Future<Map<String, Object?>> Function(
    Map<String, Object?> request);

/// Default seam over the Firebase callable.
ActivityCloudSettingsCall cloudFunctionsSettingsCall({FirebaseFunctions? functions}) {
  return (request) async {
    final fns = functions ?? functionsForRegion;
    try {
      final res = await fns
          .httpsCallable('setActivityCloudSettings')
          .call<Map<Object?, Object?>>(request);
      return {for (final e in res.data.entries) '${e.key}': e.value};
    } on FirebaseFunctionsException catch (e) {
      // Remediation J2: the server saw another account than `expectedUid`.
      if (isAccountChangedRefusal(e)) {
        throw const ConsentAccountChangedException();
      }
      rethrow;
    }
  };
}

class ActivityCloudSettingsClient implements CloudStreamsConsentView {
  ActivityCloudSettingsClient({
    required ActivityCloudSettingsCall call,
    required String? Function() currentUid,
    CloudStreamsConsentStore? store,
  })  : _call = call,
        _currentUid = currentUid,
        _store = store ?? InMemoryCloudStreamsConsentStore();

  final ActivityCloudSettingsCall _call;

  /// The live authenticated uid (the account the Firebase callable will run as).
  final String? Function() _currentUid;
  final CloudStreamsConsentStore _store;
  CloudStreamsConsent _state = CloudStreamsConsent.unknown;
  String? _consentUid;

  /// Bumped by every state change, [reset] and [load]; a [load] whose version
  /// is no longer current discards its result (it must never overwrite a newer
  /// grant or withdraw, nor another account's state).
  int _version = 0;

  /// Uids whose withdrawal is applied in memory but could not be persisted: a
  /// later [load] must not resurrect the stale stored `granted` for them.
  final Set<String?> _unpersistedWithdrawals = {};

  CloudStreamsConsent get state => _state;

  /// The uid the in-memory state belongs to; null while unknown.
  @override
  String? get consentUid => _consentUid;

  /// The uid of the account the consent store is bound to right now.
  String? get accountUid => _store.boundUid;

  /// Granted only when the state belongs to the store's current account. An
  /// unbound store (null bound uid) never counts as granted, even when a
  /// `granted` value is held (remediation J3 B1).
  @override
  bool get isGranted =>
      _state == CloudStreamsConsent.granted &&
      _consentUid != null &&
      _consentUid == _store.boundUid;

  /// Forgets the in-memory state (account change): consent is unknown and
  /// belongs to no uid. Stored consent of any account is NOT deleted.
  void reset() {
    _version++;
    _state = CloudStreamsConsent.unknown;
    _consentUid = null;
  }

  /// True when the store is bound and the live authenticated uid is the bound
  /// uid: the only state in which a consent-changing callable may be sent.
  bool get authMatchesAccount {
    final bound = _store.boundUid;
    return bound != null && _currentUid() == bound;
  }

  /// Throws unless the store is still bound to [uid] AND the live authenticated
  /// uid is [uid] (both are read synchronously, no await inside).
  void _requireUid(String? uid) {
    if (uid == null || _store.boundUid != uid || _currentUid() != uid) {
      throw const ConsentAccountChangedException();
    }
  }

  /// The uid an operation may start for; throws when the store is unbound or
  /// the live authenticated uid differs from the bound one.
  String _startUid() {
    final uid = _store.boundUid;
    _requireUid(uid);
    return uid!;
  }

  /// Loads the cached state of the store's current account (call after the
  /// store is bound). The result is applied only when no newer state change
  /// happened and the store is still bound to the same uid.
  Future<void> load() async {
    final uid = _store.boundUid;
    final myVersion = ++_version;
    var value = await _store.read();
    if (myVersion != _version || _store.boundUid != uid) return;
    // Remediation J3 B1: an unbound store belongs to no account; whatever it
    // returned is ignored (the state stays unknown, no uid).
    if (uid == null) return;
    if (_unpersistedWithdrawals.contains(uid) &&
        value != CloudStreamsConsent.withdrawn) {
      value = CloudStreamsConsent.withdrawn;
    }
    _state = value;
    _consentUid = uid;
  }

  /// Records consent. The cache flips to granted only after the server accepted
  /// and the value was persisted, and only while the account is the one the
  /// call started for; otherwise [ConsentAccountChangedException] is thrown and
  /// nothing is written for the other account.
  ///
  /// Remediation J2: the request carries `expectedUid` (the initiating account)
  /// and the server refuses it when the authenticated account differs. The
  /// start check and the pre-call check both require the store uid AND the live
  /// authenticated uid to equal the initiating uid.
  Future<void> grant() async {
    // Remediation I2/J2: an unbound store, or an authenticated account other
    // than the bound one, cannot be served: nothing may reach the server.
    final uid = _startUid();
    // Synchronously before the call expression (no await in between).
    _requireUid(uid);
    await _call({
      'expectedUid': uid,
      'cloudStreams': {'granted': true, 'version': kCloudStreamsConsentVersion},
    });
    _requireUid(uid);
    await _store.write(CloudStreamsConsent.granted);
    _requireUid(uid);
    _version++;
    _state = CloudStreamsConsent.granted;
    _consentUid = uid;
    _unpersistedWithdrawals.remove(uid);
  }

  /// Withdraws consent. The local cache flips FIRST, so uploads stop even when
  /// the call fails (a failed call is rethrown; calling again is idempotent).
  /// The withdrawal is persisted before this returns. When the account changed
  /// meanwhile the server call is NOT sent (it would hit the other account) and
  /// [ConsentAccountChangedException] is thrown. [deleteExisting] asks the
  /// server to start the bulk stream deletion.
  ///
  /// Remediation J2: refused before any state change when the store is unbound
  /// or the live authenticated uid is not the bound uid. The request carries
  /// `expectedUid`. When the account changes after the local flip, the call is
  /// not sent; the local withdrawn state of the initiating account stays (the
  /// privacy-conservative outcome: uploads for it stay stopped).
  Future<void> withdraw({bool deleteExisting = false}) async {
    // Remediation I2/J2: refuse before any state change, set insertion or call.
    final uid = _startUid();
    _version++;
    _state = CloudStreamsConsent.withdrawn;
    _consentUid = uid;
    _unpersistedWithdrawals.add(uid);
    Object? persistError;
    StackTrace? persistStack;
    try {
      await _store.write(CloudStreamsConsent.withdrawn);
      _unpersistedWithdrawals.remove(uid);
    } catch (e, s) {
      persistError = e;
      persistStack = s;
    }
    // Synchronously before the call expression (no await in between).
    _requireUid(uid);
    await _call({
      'expectedUid': uid,
      'cloudStreams': {
        'granted': false,
        'version': kCloudStreamsConsentVersion,
        if (deleteExisting) 'deleteExisting': true,
      },
    });
    if (persistError != null) {
      Error.throwWithStackTrace(persistError, persistStack!);
    }
  }
}

class ConsentWithdrawalResult {
  const ConsentWithdrawalResult({required this.offerDeleteCloudStreams});

  /// True: the UI must offer "delete my cloud streams now" (design 9.1).
  final bool offerDeleteCloudStreams;
}

class ActivityConsentWithdrawal {
  ActivityConsentWithdrawal({
    required ActivityCloudSettingsClient settings,
    required ActivityStreamUploader uploader,
  })  : _settings = settings,
        _uploader = uploader;

  final ActivityCloudSettingsClient _settings;
  final ActivityStreamUploader _uploader;

  /// Accounts for which the bulk deletion was requested (once per account: a
  /// request of account A never swallows the request of account B).
  final Set<String?> _deleteRequested = {};

  /// Records the withdrawal, stops queued uploads and returns the offer. Local
  /// journal data and summaries are not touched.
  ///
  /// Remediation J3 B2: the account guard comes FIRST. A refused withdrawal
  /// (no bound account, or the live account is not the bound one) throws
  /// [ConsentAccountChangedException] and leaves the uploader untouched
  /// (`cancelQueued` is not called). After the withdrawal succeeded the delete
  /// offer is re-armed for that account: a later withdrawal after a re-grant may
  /// request the deletion again.
  Future<ConsentWithdrawalResult> withdraw() async {
    final uid = _settings.accountUid;
    if (uid == null || !_settings.authMatchesAccount) {
      throw const ConsentAccountChangedException();
    }
    _uploader.cancelQueued();
    await _settings.withdraw();
    _deleteRequested.remove(uid);
    return const ConsentWithdrawalResult(offerDeleteCloudStreams: true);
  }

  /// The user chose "delete my cloud streams now". Calls
  /// `setActivityCloudSettings` with `deleteExisting` exactly once per account
  /// and per withdrawal (a new [withdraw] re-arms it); further calls within the
  /// same withdrawal are no-ops. The account is captured at
  /// the start; the settings client refuses (throws) when it changed meanwhile.
  /// Summaries and local data stay.
  Future<void> deleteCloudStreamsNow() async {
    // Remediation I2/J2: an unbound store, or a live authenticated uid other
    // than the bound one, never records a "requested" key.
    if (_settings.accountUid == null || !_settings.authMatchesAccount) {
      throw const ConsentAccountChangedException();
    }
    final uid = _settings.accountUid;
    if (_deleteRequested.contains(uid)) return;
    _deleteRequested.add(uid);
    try {
      await _settings.withdraw(deleteExisting: true);
    } catch (_) {
      // Let the user try again after a failure: only a call the server may
      // have seen counts as "once".
      _deleteRequested.remove(uid);
      rethrow;
    }
  }
}
