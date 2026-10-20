// S04-21 (DT-21-1..5, DT-21-7, DT-21-8, DT-21-10 provider half): the consent
// notifier. Grant fails closed, withdrawal fails safe and deletes nothing,
// writes are ordered and uid guarded.
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
    Map<String, Object> initial = const {},
    AuthUser? user = _userA,
    RecorderPhase phase = RecorderPhase.idle,
    bool throwingPrefs = false,
    bool throwOnStop = false,
  }) async {
    SharedPreferences.setMockInitialValues(initial);
    final real = await SharedPreferences.getInstance();
    prefs = throwingPrefs ? _ThrowingPrefs(real) : _Prefs(real);
    auth = _Auth()..current = user;
    now = DateTime.utc(2026, 10, 1, 12);
    stub = _StubController(phase, throwOnStop: throwOnStop);
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
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('initial state', () {
    test('no stored value: not granted', () async {
      final c = await make();
      expect(c.read(locationConsentProvider).value!.recordingGranted, isFalse);
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });

    test('signed out reads as no consent', () async {
      final c = await make(user: null);
      expect(c.read(locationConsentProvider).value, same(LocationConsent.none));
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });

    test('a stored grant loads for the signed-in uid', () async {
      final seed = LocationConsent.none.withRecord(ConsentRecord(
          purpose: LocationConsentPurpose.locationWhileRecording,
          state: ConsentState.granted,
          textVersion: kLocationConsentTextVersion,
          timestampUtcMs: 1,
          grantedAtUtcMs: 1));
      final c = await make(
          initial: {locationConsentKeyFor('uidA'): seed.encode()});
      expect(c.read(locationConsentGrantedProvider), isTrue);
    });

    test('another account\'s stored grant is not visible (isolation)',
        () async {
      final seed = LocationConsent.none.withRecord(ConsentRecord(
          purpose: LocationConsentPurpose.locationWhileRecording,
          state: ConsentState.granted,
          textVersion: 'draft-1',
          timestampUtcMs: 1));
      final c = await make(
          initial: {locationConsentKeyFor('uidB'): seed.encode()});
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });

    test('corrupt stored value fails closed and is not overwritten (DT-21-8)',
        () async {
      final c = await make(initial: {locationConsentKeyFor('uidA'): '{{{garbage'});
      expect(c.read(locationConsentGrantedProvider), isFalse);
      expect(prefs.writes, isEmpty, reason: 'no write without an explicit action');
      expect(prefs.getString(locationConsentKeyFor('uidA')), '{{{garbage');
    });

    test('unknown-version-like envelope with no records is no consent',
        () async {
      final c = await make(
          initial: {locationConsentKeyFor('uidA'): '{"v":99,"records":"x"}'});
      expect(c.read(locationConsentGrantedProvider), isFalse);
      expect(prefs.writes, isEmpty);
    });
  });

  group('grant (DT-21-1, DT-21-10)', () {
    test('persists one record with the four fields and updates state',
        () async {
      final c = await make();
      final ok = await c.read(locationConsentProvider.notifier).grant();
      expect(ok, isTrue);
      expect(c.read(locationConsentGrantedProvider), isTrue);
      final rec = c
          .read(locationConsentProvider)
          .value!
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.state, ConsentState.granted);
      expect(rec.textVersion, kLocationConsentTextVersion);
      expect(rec.timestampUtcMs, now.millisecondsSinceEpoch);
      expect(rec.grantedAtUtcMs, now.millisecondsSinceEpoch);
      final back = LocationConsent.decode(
          prefs.getString(locationConsentKeyFor('uidA')));
      expect(back.recordingGranted, isTrue);
      expect(prefs.writes.length, 1);
    });

    test('the background row is not written by a recording grant', () async {
      final c = await make();
      await c.read(locationConsentProvider.notifier).grant();
      final consent = c.read(locationConsentProvider).value!;
      expect(consent.recordOf(LocationConsentPurpose.backgroundLocation), isNull);
      expect(consent.records.length, 1);
    });

    test('an explicit text version is stored as given', () async {
      final c = await make();
      await c
          .read(locationConsentProvider.notifier)
          .grant(textVersion: 'draft-2');
      expect(
          c
              .read(locationConsentProvider)
              .value!
              .recordOf(LocationConsentPurpose.locationWhileRecording)!
              .textVersion,
          'draft-2');
    });

    test('write failure fails closed: false, state unchanged (DT-21-3)',
        () async {
      final c = await make();
      prefs.failWrites = true;
      final ok = await c.read(locationConsentProvider.notifier).grant();
      expect(ok, isFalse);
      expect(c.read(locationConsentGrantedProvider), isFalse);
      expect(prefs.getString(locationConsentKeyFor('uidA')), isNull);
    });

    test('a throwing store fails closed and logs a content-free line',
        () async {
      final lines = <String>[];
      recorderLogSink = lines.add;
      addTearDown(() => recorderLogSink = null);
      final c = await make(throwingPrefs: true);
      final ok = await c.read(locationConsentProvider.notifier).grant();
      expect(ok, isFalse);
      expect(c.read(locationConsentGrantedProvider), isFalse);
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l.contains('12.3456789'), isFalse);
        expect(l.contains('98.7654321'), isFalse);
        expect(l.contains('disk'), isFalse);
      }
    });

    test('signed out: grant is refused and nothing is written', () async {
      final c = await make(user: null);
      expect(await c.read(locationConsentProvider.notifier).grant(), isFalse);
      expect(prefs.writes, isEmpty);
    });

    test('a second grant overwrites the first with a newer timestamp',
        () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      await n.grant();
      now = now.add(const Duration(minutes: 5));
      await n.grant();
      final rec = c
          .read(locationConsentProvider)
          .value!
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.timestampUtcMs, now.millisecondsSinceEpoch);
    });
  });

  group('withdraw (DT-21-2)', () {
    test('withdraw after grant: Start consent gone, grantedAt and version kept, '
        'record persisted', () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      await n.grant(textVersion: 'draft-1');
      final grantedAt = now.millisecondsSinceEpoch;
      now = now.add(const Duration(hours: 1));
      final ok = await n.withdraw(textVersion: 'draft-9');
      expect(ok, isTrue);
      expect(c.read(locationConsentGrantedProvider), isFalse);
      final rec = c
          .read(locationConsentProvider)
          .value!
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.state, ConsentState.withdrawn);
      expect(rec.grantedAtUtcMs, grantedAt);
      expect(rec.textVersion, 'draft-1',
          reason: 'withdrawal keeps the version the user consented to');
      expect(rec.timestampUtcMs, now.millisecondsSinceEpoch);
      expect(
          LocationConsent.decode(prefs.getString(locationConsentKeyFor('uidA')))
              .recordingState,
          ConsentState.withdrawn);
    });

    test('withdraw with no prior record uses the supplied version', () async {
      final c = await make();
      await c.read(locationConsentProvider.notifier).withdraw();
      final rec = c
          .read(locationConsentProvider)
          .value!
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.state, ConsentState.withdrawn);
      expect(rec.textVersion, kLocationConsentTextVersion);
      expect(rec.grantedAtUtcMs, isNull);
    });

    test('write failure: in-memory withdrawal still stands, returns false',
        () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      await n.grant();
      prefs.failWrites = true;
      expect(await n.withdraw(), isFalse);
      expect(c.read(locationConsentGrantedProvider), isFalse,
          reason: 'fail safe: Start stays refused');
    });

    test('withdrawing the background row leaves the recording consent alone',
        () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      await n.grant();
      await n.withdraw(purpose: LocationConsentPurpose.backgroundLocation);
      expect(c.read(locationConsentGrantedProvider), isTrue);
      expect(stub.stops, isEmpty,
          reason: 'only the recording purpose stops a recording');
    });

    test('while collecting, a withdrawal stops the recording with the consent '
        'reason', () async {
      for (final phase in [
        RecorderPhase.acquiring,
        RecorderPhase.recording,
        RecorderPhase.pausedManual,
        RecorderPhase.pausedAuto,
      ]) {
        final c = await make(phase: phase);
        await c.read(locationConsentProvider.notifier).grant();
        await c.read(locationConsentProvider.notifier).withdraw();
        expect(stub.stops, [StopReason.consentWithdrawn], reason: phase.name);
        expect(c.read(locationConsentGrantedProvider), isFalse);
      }
    });

    test('when not collecting, no stop is issued', () async {
      for (final phase in [
        RecorderPhase.idle,
        RecorderPhase.stopping,
        RecorderPhase.permissionRevoked,
      ]) {
        final c = await make(phase: phase);
        await c.read(locationConsentProvider.notifier).withdraw();
        expect(stub.stops, isEmpty, reason: phase.name);
      }
    });

    test('a failing stop is contained: record still persisted, log has no '
        'message text', () async {
      final lines = <String>[];
      recorderLogSink = lines.add;
      addTearDown(() => recorderLogSink = null);
      final c = await make(phase: RecorderPhase.recording, throwOnStop: true);
      final ok = await c.read(locationConsentProvider.notifier).withdraw();
      expect(ok, isTrue);
      expect(
          LocationConsent.decode(prefs.getString(locationConsentKeyFor('uidA')))
              .recordingState,
          ConsentState.withdrawn);
      expect(lines.where((l) => l.contains('consent.withdraw.stop')), isNotEmpty);
      expect(lines.any((l) => l.contains('12.3456789')), isFalse);
    });

    test('withdrawal deletes nothing: other rows survive', () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      await n.grant();
      await n.grant(purpose: LocationConsentPurpose.backgroundLocation);
      await n.withdraw();
      final consent = c.read(locationConsentProvider).value!;
      expect(consent.records.length, 2);
      expect(consent.stateOf(LocationConsentPurpose.backgroundLocation),
          ConsentState.granted);
    });

    test('signed out: withdraw is refused and writes nothing', () async {
      final c = await make(user: null);
      expect(await c.read(locationConsentProvider.notifier).withdraw(), isFalse);
      expect(prefs.writes, isEmpty);
    });
  });

  group('2x2 table: consent x permission (DT-21-7, consent half)', () {
    // The provider owns the consent axis; the permission axis lives in the
    // controller. Here: consent granted/withdrawn/none drive the gate bool.
    for (final e in {
      'granted': true,
      'withdrawn': false,
      'none': false,
    }.entries) {
      test('consent ${e.key} -> Start gate ${e.value}', () async {
        final c = await make();
        final n = c.read(locationConsentProvider.notifier);
        if (e.key == 'granted') await n.grant();
        if (e.key == 'withdrawn') await n.withdraw();
        expect(c.read(locationConsentGrantedProvider), e.value);
      });
    }
  });

  group('ordered writes (DT-21-4 /ordered-writes)', () {
    test('a slow older write cannot land after a newer one', () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      prefs.hold = Completer<void>();
      final g = n.grant();
      final w = n.withdraw();
      await settle();
      expect(prefs.writes, isEmpty, reason: 'first write is held open');
      now = now.add(const Duration(seconds: 1));
      prefs.hold!.complete();
      prefs.hold = null;
      expect(await g, isTrue);
      expect(await w, isTrue);
      expect(prefs.writes.length, 2);
      final first = LocationConsent.decode(prefs.writes.first);
      final last = LocationConsent.decode(prefs.writes.last);
      expect(first.recordingState, ConsentState.granted);
      expect(last.recordingState, ConsentState.withdrawn);
      expect(
          LocationConsent.decode(prefs.getString(locationConsentKeyFor('uidA')))
              .recordingState,
          ConsentState.withdrawn,
          reason: 'the final stored value is the newest decision');
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });

    test('one failing write does not poison the queue', () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      prefs.failWrites = true;
      expect(await n.grant(), isFalse);
      prefs.failWrites = false;
      expect(await n.grant(), isTrue);
      expect(c.read(locationConsentGrantedProvider), isTrue);
    });
  });

  group('uid guard (DT-21-4 /uid-guard, /wiped-uid-guard)', () {
    test('sign-out after load: a later grant is refused', () async {
      final c = await make();
      auth.set(null);
      await settle();
      expect(await c.read(locationConsentProvider.notifier).grant(), isFalse);
      expect(prefs.writes, isEmpty);
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });

    test('account switch: state reloads for the new uid and never writes '
        'under the old one', () async {
      final seed = LocationConsent.none.withRecord(ConsentRecord(
          purpose: LocationConsentPurpose.locationWhileRecording,
          state: ConsentState.granted,
          textVersion: 'draft-1',
          timestampUtcMs: 1));
      final c = await make(
          initial: {locationConsentKeyFor('uidA'): seed.encode()});
      expect(c.read(locationConsentGrantedProvider), isTrue);
      auth.set(_userB);
      await settle();
      await c.read(locationConsentProvider.future);
      expect(c.read(locationConsentGrantedProvider), isFalse,
          reason: 'B has no consent, A\'s grant does not carry over');
      await c.read(locationConsentProvider.notifier).grant();
      expect(prefs.getString(locationConsentKeyFor('uidB')), isNotNull);
      expect(
          LocationConsent.decode(prefs.getString(locationConsentKeyFor('uidA')))
              .recordingGranted,
          isTrue,
          reason: 'A\'s record is untouched');
    });

    test('a write in flight when the account switches does not change state',
        () async {
      final c = await make();
      final n = c.read(locationConsentProvider.notifier);
      prefs.hold = Completer<void>();
      final g = n.grant();
      await settle();
      auth.set(_userB);
      await settle();
      prefs.hold!.complete();
      prefs.hold = null;
      final ok = await g;
      expect(ok, isFalse, reason: 'ownership lost before the state commit');
      await c.read(locationConsentProvider.future);
      expect(c.read(locationConsentGrantedProvider), isFalse,
          reason: 'B must not inherit a grant requested under A');
    });

    test('the Start gate is false while an account switch is loading',
        () async {
      final c = await make();
      await c.read(locationConsentProvider.notifier).grant();
      expect(c.read(locationConsentGrantedProvider), isTrue);
      auth.set(_userB);
      // Right after the switch the notifier is rebuilding.
      await Future<void>.delayed(Duration.zero);
      final s = c.read(locationConsentProvider);
      if (s.isLoading || s.isRefreshing) {
        expect(c.read(locationConsentGrantedProvider), isFalse);
      }
      await settle();
      await c.read(locationConsentProvider.future);
      expect(c.read(locationConsentGrantedProvider), isFalse);
    });
  });
}
