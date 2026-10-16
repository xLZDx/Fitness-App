// S02 test epic 16b: remediation J2/J3b, the settings client binds every call to
// the initiating account. Oracles: S02_DESIGN.md 17 item 25 and
// S02_REMEDIATION_J_TEST_NOTES.md (CLIENT J2, CLIENT J3b B1 and B2), not the
// code under test.
//
// The live auth uid and the consent store uid are two separate sources. A
// supplier that answers A for the first N reads and B afterwards flips the live
// account at an exact point of the client: reads are counted by the contract
// (grant: start=1, before the call=2, after the call=3, after the write=4;
// withdraw: start=1, before the call=2; deleteCloudStreamsNow: presenter
// guard=1, settings start=2, before the call=3).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stream_upload_world.dart';

/// Answers [first] for the first [flipAfter] reads and [then] afterwards.
class _Live {
  _Live(this.first, this.then, this.flipAfter);
  final String? first;
  final String? then;
  int flipAfter;
  int reads = 0;

  String? call() {
    reads++;
    return reads <= flipAfter ? first : then;
  }
}

/// A store with a per-uid value map and a write log, bound to one uid.
class _Store implements CloudStreamsConsentStore {
  _Store(this.boundUid);
  @override
  String? boundUid;
  final Map<String, CloudStreamsConsent> values = {};
  final List<String> writes = [];

  @override
  Future<CloudStreamsConsent> read() async =>
      values[boundUid] ?? CloudStreamsConsent.unknown;

  @override
  Future<void> write(CloudStreamsConsent value) async {
    writes.add('$boundUid=${value.name}');
    values[boundUid!] = value;
  }
}

class _Uploader extends Fake implements ActivityStreamUploader {
  int cancels = 0;
  @override
  void cancelQueued() => cancels++;
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.owner);
  final _Fns owner;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    owner.sent.add(parameters as Map<String, Object?>);
    throw owner.error;
  }
}

class _Fns extends Fake implements FirebaseFunctions {
  _Fns(this.error);
  final Object error;
  final List<String> names = [];
  final List<Map<String, Object?>> sent = [];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    names.add(name);
    return _Callable(this);
  }
}

FirebaseFunctionsException _fnErr(String code, String message) =>
    FirebaseFunctionsException(code: code, message: message);

void main() {
  late FakeSettingsServer server;
  late _Store store;
  late _Uploader uploader;

  setUp(() {
    server = FakeSettingsServer();
    store = _Store('A');
    uploader = _Uploader();
  });

  ActivityCloudSettingsClient clientWith(String? Function() live) =>
      ActivityCloudSettingsClient(
          call: server.call, currentUid: live, store: store);

  final refused = throwsA(isA<ConsentAccountChangedException>());

  group('request carries expectedUid (J2 item b)', () {
    test('grant sends exactly the consent map with the initiating uid',
        () async {
      await clientWith(() => 'A').grant();
      expect(server.requests.single, {
        'expectedUid': 'A',
        'cloudStreams': {'granted': true, 'version': kCloudStreamsConsentVersion},
      });
    });

    test('withdraw and withdraw with deleteExisting carry it', () async {
      final c = clientWith(() => 'A');
      await c.withdraw();
      await c.withdraw(deleteExisting: true);
      expect(server.requests, hasLength(2));
      expect(server.requests.map((r) => r['expectedUid']), ['A', 'A']);
      expect(server.deleteRequests, hasLength(1));
    });

    test('deleteCloudStreamsNow carries it; the uid is the bound account',
        () async {
      store.boundUid = 'Z';
      final c = clientWith(() => 'Z');
      await ActivityConsentWithdrawal(settings: c, uploader: uploader)
          .deleteCloudStreamsNow();
      expect(server.deleteRequests.single['expectedUid'], 'Z');
    });
  });

  group('start refusals: store bound to A, live account is not A (item c)', () {
    for (final live in <String?>['B', null]) {
      test('live=$live: grant, withdraw, delete refuse with no state change, '
          'no write and no call', () async {
        store.values['A'] = CloudStreamsConsent.granted;
        final c = clientWith(() => live);
        await c.load();
        expect(c.isGranted, isTrue, reason: 'precondition: A granted');
        final w = ActivityConsentWithdrawal(settings: c, uploader: uploader);

        await expectLater(c.grant(), refused);
        await expectLater(c.withdraw(), refused);
        await expectLater(c.withdraw(deleteExisting: true), refused);
        await expectLater(w.deleteCloudStreamsNow(), refused);
        await expectLater(w.withdraw(), refused);

        expect(server.requests, isEmpty);
        expect(store.writes, isEmpty);
        expect(store.values, {'A': CloudStreamsConsent.granted});
        expect(c.state, CloudStreamsConsent.granted,
            reason: 'a refused withdraw must not flip the cache');
        expect(c.consentUid, 'A');
        expect(uploader.cancels, 0, reason: 'guard runs before cancelQueued');
      });
    }

    test('authMatchesAccount truth table', () {
      expect(clientWith(() => 'A').authMatchesAccount, isTrue);
      expect(clientWith(() => 'B').authMatchesAccount, isFalse);
      expect(clientWith(() => null).authMatchesAccount, isFalse);
      store.boundUid = null;
      expect(clientWith(() => null).authMatchesAccount, isFalse,
          reason: 'null == null must not count as a match');
      expect(clientWith(() => 'A').authMatchesAccount, isFalse);
    });
  });

  // A prior consent of B that is identical to A's and one that differs.
  for (final bPrior in [CloudStreamsConsent.granted, CloudStreamsConsent.withdrawn]) {
    final label = 'B prior=${bPrior.name}';

    group('grant: the live account flips A to B ($label)', () {
      setUp(() {
        store.values['A'] = CloudStreamsConsent.withdrawn;
        store.values['B'] = bPrior;
      });

      void noEffectForB(ActivityCloudSettingsClient c) {
        expect(store.values['B'], bPrior, reason: 'B\'s stored value untouched');
        expect(store.writes.where((w) => w.startsWith('B')), isEmpty);
        expect(c.consentUid, isNot('B'));
        expect(c.isGranted, isFalse);
        expect(server.requests.where((r) => r['expectedUid'] != 'A'), isEmpty);
      }

      test('flip before the call (pre-call check): nothing sent, nothing '
          'written, state unknown', () async {
        final c = clientWith(_Live('A', 'B', 1).call);
        await expectLater(c.grant(), refused);
        expect(server.requests, isEmpty);
        expect(store.writes, isEmpty);
        expect(c.state, CloudStreamsConsent.unknown);
        noEffectForB(c);
      });

      test('flip while the call is in flight (post-call check): the request '
          'was A\'s, nothing is written or granted', () async {
        final c = clientWith(_Live('A', 'B', 2).call);
        await expectLater(c.grant(), refused);
        expect(server.requests, hasLength(1));
        expect(server.requests.single['expectedUid'], 'A');
        expect(store.writes, isEmpty);
        expect(c.state, CloudStreamsConsent.unknown);
        noEffectForB(c);
      });

      test('flip after the call, during the write: the cache never turns '
          'granted for B', () async {
        final c = clientWith(_Live('A', 'B', 3).call);
        await expectLater(c.grant(), refused);
        expect(store.writes.where((w) => w.startsWith('B')), isEmpty);
        expect(c.state, unknownOrGranted());
        noEffectForB(c);
      });
    });

    group('withdraw: the live account flips A to B ($label)', () {
      setUp(() {
        store.values['A'] = CloudStreamsConsent.granted;
        store.values['B'] = bPrior;
      });

      test('flip before the call: A is withdrawn locally, NOTHING is sent '
          'and nothing is written for B', () async {
        final c = clientWith(_Live('A', 'B', 1).call);
        await expectLater(c.withdraw(), refused);
        expect(server.requests, isEmpty);
        expect(store.writes, ['A=withdrawn']);
        expect(store.values['B'], bPrior);
        expect(c.state, CloudStreamsConsent.withdrawn);
        expect(c.consentUid, 'A');
        expect(c.isGranted, isFalse);
      });

      test('flip after the check: the one request is A\'s', () async {
        final c = clientWith(_Live('A', 'B', 2).call);
        await c.withdraw();
        expect(server.requests.single['expectedUid'], 'A');
        expect(store.values['B'], bPrior);
        expect(c.consentUid, 'A');
      });
    });

    group('deleteCloudStreamsNow: the live account flips ($label)', () {
      setUp(() {
        store.values['A'] = CloudStreamsConsent.granted;
        store.values['B'] = bPrior;
      });

      for (final n in [0, 1, 2]) {
        test('flip after $n reads: no request for B, no requested key, and a '
            'later call under A sends exactly one', () async {
          final live = _Live('A', 'B', n);
          final c = clientWith(live.call);
          final w = ActivityConsentWithdrawal(settings: c, uploader: uploader);
          await c.load();

          await expectLater(w.deleteCloudStreamsNow(), refused);
          expect(server.requests, isEmpty);
          expect(store.values['B'], bPrior);
          expect(store.writes.where((x) => x.startsWith('B')), isEmpty);

          live.flipAfter = 1 << 30; // the right account is back
          await w.deleteCloudStreamsNow();
          expect(server.deleteRequests, hasLength(1),
              reason: 'the refused call recorded no "already requested" key');
          expect(server.deleteRequests.single['expectedUid'], 'A');
          await w.deleteCloudStreamsNow();
          expect(server.deleteRequests, hasLength(1), reason: 'once per account');
        });
      }
    });
  }

  group('withdrawal presenter (J3b B2)', () {
    test('a successful withdraw cancels the uploader once and offers the '
        'delete', () async {
      final w = ActivityConsentWithdrawal(
          settings: clientWith(() => 'A'), uploader: uploader);
      final r = await w.withdraw();
      expect(r.offerDeleteCloudStreams, isTrue);
      expect(uploader.cancels, 1);
      expect(server.requests.single['expectedUid'], 'A');
    });

    test('unbound store: refused, uploader NOT cancelled, no call', () async {
      store.boundUid = null;
      final w = ActivityConsentWithdrawal(
          settings: clientWith(() => 'A'), uploader: uploader);
      await expectLater(w.withdraw(), refused);
      expect(uploader.cancels, 0);
      expect(server.requests, isEmpty);
    });

    test('the live account flips between the guard and the settings call: '
        'the call is not sent', () async {
      final w = ActivityConsentWithdrawal(
          settings: clientWith(_Live('A', 'B', 1).call), uploader: uploader);
      await expectLater(w.withdraw(), refused);
      expect(server.requests, isEmpty);
      expect(store.writes.where((x) => x.startsWith('B')), isEmpty);
    });

    test('re-arm: grant, withdraw, delete, re-grant, withdraw, delete sends '
        'TWO deleteExisting requests; a repeat inside one withdrawal sends one',
        () async {
      final c = clientWith(() => 'A');
      final w = ActivityConsentWithdrawal(settings: c, uploader: uploader);
      await c.grant();
      await w.withdraw();
      await w.deleteCloudStreamsNow();
      await w.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(1));
      await c.grant();
      await w.withdraw();
      await w.deleteCloudStreamsNow();
      await w.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(2));
    });

    test('a refused withdraw does not re-arm the offer', () async {
      final live = _Live('A', 'A', 1 << 30);
      final c = clientWith(live.call);
      final w = ActivityConsentWithdrawal(settings: c, uploader: uploader);
      await w.withdraw();
      await w.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(1));
      store.boundUid = null;
      await expectLater(w.withdraw(), refused);
      store.boundUid = 'A';
      await w.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(1),
          reason: 'only a successful withdrawal re-arms the delete offer');
    });
  });

  group('isGranted and load with an unbound store (J3b B1)', () {
    test('load on an unbound store ignores the stored granted value',
        () async {
      store.boundUid = null;
      store.values['A'] = CloudStreamsConsent.granted;
      // The scripted store would answer for a null uid with unknown; force a
      // granted answer to prove the client discards it.
      final unbound = _GrantedWhenUnbound();
      final c = ActivityCloudSettingsClient(
          call: server.call, currentUid: () => null, store: unbound);
      await c.load();
      expect(c.state, CloudStreamsConsent.unknown);
      expect(c.consentUid, isNull);
      expect(c.isGranted, isFalse);
    });

    test('granted for A, then the store is unbound: isGranted is false',
        () async {
      store.values['A'] = CloudStreamsConsent.granted;
      final c = clientWith(() => 'A');
      await c.load();
      expect(c.isGranted, isTrue);
      store.boundUid = null;
      expect(c.isGranted, isFalse);
      store.boundUid = 'A';
      expect(c.isGranted, isTrue, reason: 'control: rebound to A');
    });
  });

  group('cloudFunctionsSettingsCall maps the server refusal (J2 item d)', () {
    Future<Object?> run(Object error, {Map<String, Object?>? req}) async {
      final fns = _Fns(error);
      try {
        await cloudFunctionsSettingsCall(functions: fns)(req ?? {'k': 1});
      } catch (e) {
        expect(fns.names, ['setActivityCloudSettings']);
        expect(fns.sent, [req ?? {'k': 1}]);
        return e;
      }
      return null;
    }

    test('failed-precondition + account_changed -> ConsentAccountChanged',
        () async {
      expect(await run(_fnErr('failed-precondition', 'account_changed')),
          isA<ConsentAccountChangedException>());
    });

    test('failed-precondition + account_deleting is NOT mapped', () async {
      final e = await run(_fnErr('failed-precondition', 'account_deleting'));
      expect(e, isA<FirebaseFunctionsException>());
      expect((e as FirebaseFunctionsException).message, 'account_deleting');
    });

    test('other failed-precondition refusals and other codes are rethrown '
        'unchanged', () async {
      for (final pair in [
        ['failed-precondition', 'consent_required'],
        ['permission-denied', 'account_changed'],
        ['unavailable', 'x'],
        ['invalid-argument', 'invalid_request'],
      ]) {
        final e = await run(_fnErr(pair[0], pair[1]));
        expect(e, isA<FirebaseFunctionsException>(), reason: '$pair');
        expect((e as FirebaseFunctionsException).code, pair[0]);
        expect(e.message, pair[1]);
      }
      expect(await run(StateError('x')), isA<StateError>());
    });

    test('isAccountChangedRefusal compares code AND message', () {
      expect(isAccountChangedRefusal(_fnErr('failed-precondition', 'account_changed')),
          isTrue);
      expect(isAccountChangedRefusal(_fnErr('failed-precondition', 'account_deleting')),
          isFalse);
      expect(isAccountChangedRefusal(_fnErr('aborted', 'account_changed')),
          isFalse);
    });
  });
}

/// Helper that keeps the third grant test honest: after the flip during the
/// write the cache is either still unknown or granted for A, never for B.
Matcher unknownOrGranted() =>
    anyOf(CloudStreamsConsent.unknown, CloudStreamsConsent.granted);

/// An unbound store that nevertheless answers `granted`.
class _GrantedWhenUnbound implements CloudStreamsConsentStore {
  @override
  String? get boundUid => null;
  @override
  Future<CloudStreamsConsent> read() async => CloudStreamsConsent.granted;
  @override
  Future<void> write(CloudStreamsConsent value) async {}
}
