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
  Future<CloudStreamsConsent> read();
  Future<void> write(CloudStreamsConsent value);
}

class InMemoryCloudStreamsConsentStore implements CloudStreamsConsentStore {
  CloudStreamsConsent _value = CloudStreamsConsent.unknown;
  @override
  Future<CloudStreamsConsent> read() async => _value;
  @override
  Future<void> write(CloudStreamsConsent value) async => _value = value;
}

/// Keeps the cached consent in `SharedPreferences`, one key per account.
class SharedPrefsCloudStreamsConsentStore implements CloudStreamsConsentStore {
  SharedPrefsCloudStreamsConsentStore(this._prefs, String uid)
      : _key = 'activity.cloudStreamsConsent.$uid';

  final SharedPreferences _prefs;
  final String _key;

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
  final fns = functions ?? functionsForRegion;
  return (request) async {
    final res = await fns
        .httpsCallable('setActivityCloudSettings')
        .call<Map<Object?, Object?>>(request);
    return {for (final e in res.data.entries) '${e.key}': e.value};
  };
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

  CloudStreamsConsent get state => _state;

  @override
  bool get isGranted => _state == CloudStreamsConsent.granted;

  /// Loads the cached state (call once at start).
  Future<void> load() async => _state = await _store.read();

  /// Records consent. The cache flips to granted only after the server accepted.
  Future<void> grant() async {
    await _call({
      'cloudStreams': {'granted': true, 'version': kCloudStreamsConsentVersion},
    });
    await _setState(CloudStreamsConsent.granted);
  }

  /// Withdraws consent. The local cache flips FIRST, so uploads stop even when
  /// the call fails (a failed call is rethrown; calling again is idempotent).
  /// [deleteExisting] asks the server to start the bulk stream deletion.
  Future<void> withdraw({bool deleteExisting = false}) async {
    await _setState(CloudStreamsConsent.withdrawn);
    await _call({
      'cloudStreams': {
        'granted': false,
        'version': kCloudStreamsConsentVersion,
        if (deleteExisting) 'deleteExisting': true,
      },
    });
  }

  Future<void> _setState(CloudStreamsConsent v) async {
    _state = v;
    await _store.write(v);
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
  bool _deleteRequested = false;

  /// Stops queued uploads immediately, records the withdrawal and returns the
  /// offer. Local journal data and summaries are not touched.
  Future<ConsentWithdrawalResult> withdraw() async {
    _uploader.cancelQueued();
    await _settings.withdraw();
    return const ConsentWithdrawalResult(offerDeleteCloudStreams: true);
  }

  /// The user chose "delete my cloud streams now". Calls
  /// `setActivityCloudSettings` with `deleteExisting` exactly once per instance;
  /// further calls are no-ops. Summaries and local data stay.
  Future<void> deleteCloudStreamsNow() async {
    if (_deleteRequested) return;
    _deleteRequested = true;
    try {
      await _settings.withdraw(deleteExisting: true);
    } catch (_) {
      // Let the user try again after a failure: only a call the server may
      // have seen counts as "once".
      _deleteRequested = false;
      rethrow;
    }
  }
}
