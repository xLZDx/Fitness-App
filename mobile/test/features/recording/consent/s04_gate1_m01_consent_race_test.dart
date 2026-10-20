// S04 gate 1, finding M-01: a withdrawal must win over a grant whose prefs
// write is still in flight. Before the fix the withdrawal waited in the write
// queue behind the grant, the grant then published `granted`, and Start was
// allowed after the user had withdrawn. Now withdraw() applies in memory
// synchronously, and a grant called before a later withdrawal of the same
// purpose is stale: it returns false and never publishes `granted`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recording/consent/location_consent.dart';
import 'package:fitness_app/features/recording/consent/location_consent_providers.dart';
import 'package:fitness_app/features/recording/l10n/recording_log.dart';
import 'package:fitness_app/features/recording/state/recorder_controller.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';

const _userA = AuthUser(uid: 'uidA', displayName: 'A');
const _userB = AuthUser(uid: 'uidB', displayName: 'B');

/// Auth stream whose latest value is replayed to every new subscriber, so a
/// provider rebuild after an account switch sees the current user.
class _Auth {
  AuthUser? current;
  final _ctrl = StreamController<AuthUser?>.broadcast();
  Stream<AuthUser?> stream() async* {
    yield current;
    yield* _ctrl.stream;
  }

  void set(AuthUser? u) {
    current = u;
    _ctrl.add(u);
  }
}

/// SharedPreferences stand-in that records every write, can hold a write open
/// and can fail.
class _Prefs implements SharedPreferences {
  _Prefs(this._real);
  final SharedPreferences _real;
  final List<String> writes = [];
  bool failWrites = false;
  Completer<void>? hold;

  @override
  String? getString(String key) => _real.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    if (hold != null) await hold!.future;
    if (failWrites) return false;
    writes.add(value);
    return _real.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingPrefs extends _Prefs {
  _ThrowingPrefs(super.real);
  @override
  Future<bool> setString(String key, String value) async =>
      throw StateError('disk lat=12.3456789 lon=-98.7654321');
}

/// Controller stub: reports a scripted phase and records automatic stops.
class _StubController extends RecorderController {
  _StubController(this.phase, {this.throwOnStop = false});
  final RecorderPhase phase;
  final bool throwOnStop;
  final List<StopReason> stops = [];

  @override
  RecorderState build() => RecorderState(phase: phase);

  @override
  Future<void> stopAutomatically(StopReason reason) async {
    stops.add(reason);
    if (throwOnStop) throw StateError('stop failed 12.3456789');
  }
}

void main() {
  late _Auth auth;
  late _Prefs prefs;
  late DateTime now;
  late _StubController stub;

  Future<ProviderContainer> make({
    RecorderPhase phase = RecorderPhase.idle,
    Map<String, Object> initial = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initial);
    final real = await SharedPreferences.getInstance();
    prefs = _Prefs(real);
    auth = _Auth()..current = _userA;
    now = DateTime.utc(2026, 10, 1, 12);
    stub = _StubController(phase);
    final c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => auth.stream()),
      locationConsentPrefsProvider.overrideWith((ref) async => prefs),
      locationConsentClockProvider.overrideWith((ref) => () => now),
      recorderControllerProvider.overrideWith(() => stub),
    ]);
    addTearDown(c.dispose);
    c.listen(locationConsentProvider, (_, __) {});
    await c.read(locationConsentProvider.future);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ConsentState? stateOf(ProviderContainer c,
          [LocationConsentPurpose p = LocationConsentPurpose.locationWhileRecording]) =>
      c.read(locationConsentProvider).value!.recordOf(p)?.state;

  LocationConsent stored() =>
      LocationConsent.decode(prefs.getString(locationConsentKeyFor('uidA')));

  test('M-01 grant write in flight, then withdraw: denied at once, stays '
      'denied after the grant completes, the grant returns false', () async {
    final c = await make();
    final n = c.read(locationConsentProvider.notifier);
    prefs.hold = Completer<void>();

    final grant = n.grant();
    await settle(); // the grant's write is now blocked inside setString
    final withdraw = n.withdraw();

    // Immediately, without waiting for any write:
    expect(c.read(locationConsentGrantedProvider), isFalse);
    expect(stateOf(c), ConsentState.withdrawn);

    prefs.hold!.complete();
    expect(await grant, isFalse, reason: 'a stale grant fails closed');
    await withdraw;
    await settle();

    expect(c.read(locationConsentGrantedProvider), isFalse,
        reason: 'the late grant must not re-grant');
    expect(stateOf(c), ConsentState.withdrawn);
    expect(stored().recordingGranted, isFalse,
        reason: 'the last write on disk is the withdrawal');
  });

  test('M-01 a grant called AFTER the withdrawal succeeds', () async {
    final c = await make();
    final n = c.read(locationConsentProvider.notifier);
    prefs.hold = Completer<void>();
    final stale = n.grant();
    await settle();
    final w = n.withdraw();
    final fresh = n.grant(); // called after the withdraw: a new decision
    prefs.hold!.complete();

    expect(await stale, isFalse);
    await w;
    expect(await fresh, isTrue);
    await settle();
    expect(c.read(locationConsentGrantedProvider), isTrue);
    expect(stateOf(c), ConsentState.granted);
    expect(stored().recordingGranted, isTrue);
  });

  test('M-01 the stale grant for the recording purpose does not block a grant '
      'of the other purpose', () async {
    final c = await make();
    final n = c.read(locationConsentProvider.notifier);
    prefs.hold = Completer<void>();
    final stale = n.grant();
    await settle();
    final w = n.withdraw();
    final other = n.grant(purpose: LocationConsentPurpose.backgroundLocation);
    prefs.hold!.complete();
    expect(await stale, isFalse);
    await w;
    expect(await other, isTrue);
    expect(stateOf(c, LocationConsentPurpose.backgroundLocation),
        ConsentState.granted);
    expect(stateOf(c), ConsentState.withdrawn);
  });

  test('M-01 withdraw during an active collection (grant write in flight) '
      'stops the recording with the consent reason', () async {
    final c = await make(phase: RecorderPhase.recording);
    final n = c.read(locationConsentProvider.notifier);
    prefs.hold = Completer<void>();
    final grant = n.grant();
    await settle();
    final w = n.withdraw();
    expect(c.read(locationConsentGrantedProvider), isFalse);
    prefs.hold!.complete();
    expect(await grant, isFalse);
    await w;
    expect(stub.stops, [StopReason.consentWithdrawn]);
    expect(c.read(locationConsentGrantedProvider), isFalse);
  });

  test('M-01 withdraw with no grant in flight still behaves as before '
      '(persisted, stop on collecting)', () async {
    final c = await make(phase: RecorderPhase.pausedAuto);
    final n = c.read(locationConsentProvider.notifier);
    expect(await n.grant(), isTrue);
    expect(await n.withdraw(), isTrue);
    expect(stub.stops, [StopReason.consentWithdrawn]);
    expect(stored().recordingGranted, isFalse);
  });
}
