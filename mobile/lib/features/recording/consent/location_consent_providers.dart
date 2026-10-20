/// Riverpod side of the location consent (S04 design 6.2, S04-21, S04-33).
///
/// Pattern: `TrainingContextNotifier`. Writes are queued so an older write can
/// never land after a newer one, and a write is refused while the signed-in uid
/// differs from the uid the state was loaded for. A grant fails closed: the
/// state changes only after the write succeeded. A withdrawal fails safe: it
/// takes effect in memory first (Start and Resume are refused at once) and a
/// running recording is stopped and kept before the withdrawal completes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/recording_defaults.dart';
import '../../auth/state/auth_providers.dart';
import '../l10n/recording_log.dart';
import '../state/recorder_phase.dart';
import '../state/recorder_providers.dart';
import 'location_consent.dart';

/// Optional injection point for tests; production reads the platform store.
final locationConsentPrefsProvider = Provider<Future<SharedPreferences>>(
    (ref) => SharedPreferences.getInstance());

/// UTC clock of the consent timestamps; a test overrides it.
final locationConsentClockProvider =
    Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());

/// The signed-in account's consent rows. Loading until the uid and the stored
/// value are both known; signed out reads as no consent.
final locationConsentProvider =
    AsyncNotifierProvider<LocationConsentNotifier, LocationConsent>(
        LocationConsentNotifier.new);

/// What `RecorderEnvironment.locationConsentGranted` reads. False while
/// loading or refreshing (an account switch), so nothing starts on a
/// half-known answer.
final locationConsentGrantedProvider = Provider<bool>((ref) {
  final c = ref.watch(locationConsentProvider);
  if (c.isLoading || c.isRefreshing) return false;
  return c.valueOrNull?.recordingGranted ?? false;
});

class LocationConsentNotifier extends AsyncNotifier<LocationConsent> {
  /// The uid the current state was loaded for; cleared at the start of every
  /// reload so an account switch in flight cannot write under the old uid.
  String? _uid;

  /// Tail of the write queue (retro rule 2: ordered writes).
  Future<void> _tail = Future<void>.value();

  /// Monotonic call number, taken synchronously when [grant] or [withdraw] is
  /// called (before the call is queued), so call order is known even while an
  /// older write is still in flight.
  int _callSeq = 0;

  /// The call number of the latest [withdraw] per purpose. A grant whose call
  /// number is lower is stale and must never publish `granted`.
  final Map<LocationConsentPurpose, int> _latestWithdrawSeq =
      <LocationConsentPurpose, int>{};

  @override
  Future<LocationConsent> build() async {
    _uid = null;
    final user = await ref.watch(authUserProvider.future);
    if (user == null) return LocationConsent.none;
    final prefs = await ref.watch(locationConsentPrefsProvider);
    final consent =
        LocationConsent.decode(prefs.getString(locationConsentKeyFor(user.uid)));
    _uid = user.uid;
    return consent;
  }

  /// Records a grant after the pre-prompt Continue (and "Allow again"). Returns
  /// true only when the record was persisted; on false the state is unchanged
  /// and the caller must not make the system permission request (fail closed).
  /// [textVersion] is the version of the wording the user saw; it defaults to
  /// [kLocationConsentTextVersion]. A grant that was called before a later
  /// [withdraw] of the same purpose is stale: it neither persists nor publishes
  /// `granted` and returns false.
  Future<bool> grant({
    LocationConsentPurpose purpose = LocationConsentPurpose.locationWhileRecording,
    String textVersion = kLocationConsentTextVersion,
  }) {
    final seq = ++_callSeq;
    bool superseded() => (_latestWithdrawSeq[purpose] ?? 0) > seq;
    return _enqueue(() async {
      final uid = _ownedUid();
      if (uid == null || superseded()) return false;
      final now = _nowMs();
      final next = _current().withRecord(ConsentRecord(
        purpose: purpose,
        state: ConsentState.granted,
        textVersion: textVersion,
        timestampUtcMs: now,
        grantedAtUtcMs: now,
      ));
      if (!await _persist(uid, next)) return false;
      if (_ownedUid() != uid || superseded()) return false;
      state = AsyncData(next);
      return true;
    });
  }

  /// Withdraws the consent of [purpose]. Nothing is deleted. The withdrawal is
  /// applied in memory synchronously when this is called, before the call joins
  /// the write queue, so a pending grant write cannot delay it (Start and
  /// Resume read the in-memory state). A running recording is then stopped and
  /// kept (reason `consentWithdrawn`), and the record is persisted last, in
  /// call order. A queued grant that was called earlier does not re-grant.
  /// Returns true when the record was persisted; the in-memory withdrawal
  /// stands either way.
  Future<bool> withdraw({
    LocationConsentPurpose purpose = LocationConsentPurpose.locationWhileRecording,
    String textVersion = kLocationConsentTextVersion,
  }) {
    _latestWithdrawSeq[purpose] = ++_callSeq;
    final syncUid = _ownedUid();
    final previous = syncUid == null ? null : _current().recordOf(purpose);
    final ConsentRecord? withdrawn = syncUid == null
        ? null
        : ConsentRecord(
            purpose: purpose,
            state: ConsentState.withdrawn,
            textVersion: previous?.textVersion ?? textVersion,
            timestampUtcMs: _nowMs(),
            grantedAtUtcMs: previous?.grantedAtUtcMs,
          );
    if (withdrawn != null) {
      state = AsyncData(_current().withRecord(withdrawn));
    }
    return _enqueue(() async {
      final uid = _ownedUid();
      if (uid == null || withdrawn == null || uid != syncUid) return false;
      if (purpose == LocationConsentPurpose.locationWhileRecording) {
        await _stopRunningRecording();
      }
      if (_ownedUid() != uid) return false;
      return _persist(uid, _current().withRecord(withdrawn));
    });
  }

  Future<void> _stopRunningRecording() async {
    try {
      final controller = ref.read(recorderControllerProvider.notifier);
      if (ref.read(recorderControllerProvider).phase.isCollecting) {
        await controller.stopAutomatically(StopReason.consentWithdrawn);
      }
    } catch (e) {
      logRecorderError('consent.withdraw.stop', e);
    }
  }

  LocationConsent _current() => state.valueOrNull ?? LocationConsent.none;

  int _nowMs() => ref.read(locationConsentClockProvider)().millisecondsSinceEpoch;

  /// The uid the state belongs to, or null while an account switch is loading.
  String? _ownedUid() {
    final uid = _uid;
    final current = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || current == null || current != uid) return null;
    return uid;
  }

  Future<bool> _persist(String uid, LocationConsent consent) async {
    try {
      final prefs = await ref.read(locationConsentPrefsProvider);
      return await prefs.setString(locationConsentKeyFor(uid), consent.encode());
    } catch (e) {
      logRecorderError('consent.persist', e);
      return false;
    }
  }

  Future<bool> _enqueue(Future<bool> Function() op) {
    final done = _tail.then((_) => op());
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }
}
