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
import 'activity_stream_uploader.dart';

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
    final res = await fns
        .httpsCallable('setActivityCloudSettings')
        .call<Map<Object?, Object?>>(request);
    return {for (final e in res.data.entries) '${e.key}': e.value};
  };
}

/// Thrown when the signed-in account changed while a consent operation was
/// running: nothing was recorded for the new account.
class ConsentAccountChangedException implements Exception {
  const ConsentAccountChangedException();
  @override
  String toString() => 'ConsentAccountChangedException';
}

class ActivityCloudSettingsClient implements CloudStreamsConsentView {
  ActivityCloudSettingsClient({
    required ActivityCloudSettingsCall call,
    CloudStreamsConsentStore? store,
  })  : _call = call,
        _store = store ?? InMemoryCloudStreamsConsentStore();

  final ActivityCloudSettingsCall _call;
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

  /// Granted only when the state belongs to the store's current account.
  @override
  bool get isGranted =>
      _state == CloudStreamsConsent.granted && _consentUid == _store.boundUid;

  /// Forgets the in-memory state (account change): consent is unknown and
  /// belongs to no uid. Stored consent of any account is NOT deleted.
  void reset() {
    _version++;
    _state = CloudStreamsConsent.unknown;
    _consentUid = null;
  }

  void _requireUid(String? uid) {
    if (_store.boundUid != uid) throw const ConsentAccountChangedException();
  }

  /// Loads the cached state of the store's current account (call after the
  /// store is bound). The result is applied only when no newer state change
  /// happened and the store is still bound to the same uid.
  Future<void> load() async {
    final uid = _store.boundUid;
    final myVersion = ++_version;
    var value = await _store.read();
    if (myVersion != _version || _store.boundUid != uid) return;
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
  Future<void> grant() async {
    final uid = _store.boundUid;
    await _call({
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
  Future<void> withdraw({bool deleteExisting = false}) async {
    final uid = _store.boundUid;
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
    _requireUid(uid);
    await _call({
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

  /// Stops queued uploads immediately, records the withdrawal and returns the
  /// offer. Local journal data and summaries are not touched.
  Future<ConsentWithdrawalResult> withdraw() async {
    _uploader.cancelQueued();
    await _settings.withdraw();
    return const ConsentWithdrawalResult(offerDeleteCloudStreams: true);
  }

  /// The user chose "delete my cloud streams now". Calls
  /// `setActivityCloudSettings` with `deleteExisting` exactly once per account;
  /// further calls for the same account are no-ops. The account is captured at
  /// the start; the settings client refuses (throws) when it changed meanwhile.
  /// Summaries and local data stay.
  Future<void> deleteCloudStreamsNow() async {
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
