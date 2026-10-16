// S02 test epic 14a: remediation H-A consent binding. Oracles:
// docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md heading H-A (items 1 to 15),
// S02_DESIGN.md 17 items 23 and 24 and the promise "my GPS data is never
// uploaded under another account's consent", not the code under test.
//
// Interleavings are deterministic: a `Completer` gates the exact await
// (the first read of the shared-preferences platform store, a settings
// callable, a store read or write, a commit).
import 'dart:async';

import 'package:fitness_app/core/wiring/activity_wiring.dart'
    show AccountScopedConsentStore;
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/gated_prefs.dart';
import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

const _keyA = consentKeyA;
const _keyB = consentKeyB;

/// A consent store scripted by the test: values per uid, a gate on read and on
/// write, and a uid that the test moves.
class _ScriptedStore implements CloudStreamsConsentStore {
  _ScriptedStore(this.boundUid);
  @override
  String? boundUid;
  final Map<String?, CloudStreamsConsent> values = {};
  Completer<void>? readGate;
  Completer<void>? writeGate;
  Object? writeError;
  final List<String> writes = [];

  @override
  Future<CloudStreamsConsent> read() async {
    final uid = boundUid;
    final g = readGate;
    if (g != null) {
      readGate = null;
      await g.future;
    }
    return values[uid] ?? CloudStreamsConsent.unknown;
  }

  @override
  Future<void> write(CloudStreamsConsent value) async {
    final uid = boundUid;
    final g = writeGate;
    if (g != null) {
      writeGate = null;
      await g.future;
    }
    if (writeError != null) throw writeError!;
    writes.add('$uid=${value.name}');
    values[uid] = value;
  }
}

/// A journal that is both a journal and account scoped, over a real journal.
class _FlipJournal extends Fake implements ActivityJournal, AccountScopedJournal {
  _FlipJournal(this.inner, this.uid);
  final ActivityJournal inner;
  String? uid;
  int marks = 0;
  int syncStateWrites = 0;

  @override
  String? get boundUid => uid;
  @override
  bool get isBound => uid != null;
  @override
  Future<List<JournalEntry>> list() => inner.list();
  @override
  Future<JournalEntry?> read(String id) => inner.read(id);
  @override
  Future<bool> markStreamUploaded(String id, {int? expectedGeneration}) {
    marks++;
    return inner.markStreamUploaded(id, expectedGeneration: expectedGeneration);
  }

  @override
  Future<bool> updateSyncState(String id, JournalSyncState state,
      {int? expectedGeneration,
      int? baseRev,
      Map<String, Object?>? baseSummary}) {
    syncStateWrites++;
    return inner.updateSyncState(id, state,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }
}

class _NoJournal extends Fake implements ActivityJournal {}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('AccountScopedConsentStore (H-A items 1 to 4)', () {
    test('1 stale signIn(A) finishing after signOut + signIn(B) changes nothing',
        () async {
      final prefs = installPrefs();
      prefs.gateOnCall[1] = Completer<void>();
      final store = AccountScopedConsentStore();
      final a = store.signIn('A'); // blocked in its first platform read
      await pumpEventQueue();
      store.signOut();
      forgetPrefs(); // B opens independently and finishes first
      await store.signIn('B');
      expect(store.boundUid, 'B');
      prefs.gateOnCall[1]!.complete();
      await a;
      expect(store.boundUid, 'B', reason: 'the obsolete A must not rebind');
      await store.write(CloudStreamsConsent.granted);
      final raw = await prefs.getAll();
      expect(raw[_keyB], 'granted');
      expect(raw.containsKey(_keyA), isFalse, reason: 'A\'s key never written');
      expect(await store.read(), CloudStreamsConsent.granted);
    });

    test('2 stale completion after signOut: unbound, unknown, write throws',
        () async {
      final prefs = installPrefs({_keyA: 'granted'});
      prefs.gateOnCall[1] = Completer<void>();
      final store = AccountScopedConsentStore();
      final a = store.signIn('A');
      await pumpEventQueue();
      store.signOut();
      prefs.gateOnCall[1]!.complete();
      await a;
      expect(store.boundUid, isNull);
      expect(await store.read(), CloudStreamsConsent.unknown,
          reason: 'A\'s stored granted must not be served after sign-out');
      await expectLater(
          store.write(CloudStreamsConsent.granted), throwsStateError);
      expect((await prefs.getAll())[_keyA], 'granted',
          reason: 'the stored consent of A survives');
    });

    test('3 signOut deletes no key; signIn(A) reads granted again', () async {
      final prefs = installPrefs();
      final store = AccountScopedConsentStore();
      await store.signIn('A');
      await store.write(CloudStreamsConsent.granted);
      store.signOut();
      expect((await prefs.getAll())[_keyA], 'granted');
      expect(await store.read(), CloudStreamsConsent.unknown);
      await store.signIn('A');
      expect(await store.read(), CloudStreamsConsent.granted);
    });

    test('4 write with no account throws; a write during the open lands under '
        'the account', () async {
      final prefs = installPrefs();
      final store = AccountScopedConsentStore();
      await expectLater(
          store.write(CloudStreamsConsent.granted), throwsStateError);
      expect((await prefs.getAll()).keys.where((k) => k.contains('Consent')),
          isEmpty);
      prefs.gateOnCall[prefs.calls + 1] = Completer<void>();
      final gate = prefs.gateOnCall[prefs.calls + 1]!;
      final open = store.signIn('A');
      await pumpEventQueue();
      var written = false;
      final w =
          store.write(CloudStreamsConsent.withdrawn).then((_) => written = true);
      await pumpEventQueue();
      expect(written, isFalse, reason: 'the write waits for the open');
      gate.complete();
      await open;
      await w;
      expect((await prefs.getAll())[_keyA], 'withdrawn');
    });
  });

  group('ActivityCloudSettingsClient (H-A items 5 to 11)', () {
    late _ScriptedStore store;
    late FakeSettingsServer server;
    late ActivityCloudSettingsClient client;

    setUp(() {
      store = _ScriptedStore('A');
      server = FakeSettingsServer();
      client = ActivityCloudSettingsClient(call: server.call, store: store);
    });

    test('5 delayed load of A finishing after B is current cannot overwrite B',
        () async {
      store.values['A'] = CloudStreamsConsent.granted;
      store.values['B'] = CloudStreamsConsent.withdrawn;
      store.readGate = Completer<void>();
      final gate = store.readGate!;
      final loadA = client.load();
      await pumpEventQueue();
      store.boundUid = 'B';
      await client.load();
      expect(client.state, CloudStreamsConsent.withdrawn);
      gate.complete();
      await loadA;
      expect(client.consentUid, 'B');
      expect(client.state, CloudStreamsConsent.withdrawn,
          reason: 'A\'s granted must not overwrite B\'s withdrawn');
      expect(client.isGranted, isFalse);
    });

    test('5b control: the same load with no switch applies', () async {
      store.values['A'] = CloudStreamsConsent.granted;
      await client.load();
      expect(client.isGranted, isTrue);
      expect(client.consentUid, 'A');
    });

    test('6 isGranted is false unless the state uid equals the store uid',
        () async {
      store.values['A'] = CloudStreamsConsent.granted;
      await client.load();
      expect(client.isGranted, isTrue);
      store.boundUid = 'B'; // switched, B not loaded
      expect(client.isGranted, isFalse);
      expect(client.consentUid, 'A');
      store.boundUid = 'A';
      expect(client.isGranted, isTrue);
      client.reset();
      expect(client.state, CloudStreamsConsent.unknown);
      expect(client.consentUid, isNull);
      expect(client.isGranted, isFalse);
    });

    test('7 grant started under A, completing after the switch to B, writes '
        'nothing for B', () async {
      final gate = Completer<void>();
      final slow = ActivityCloudSettingsClient(
        call: (r) async {
          await gate.future;
          return const {'ok': true};
        },
        store: store,
      );
      final g = slow.grant();
      final thrown = expectLater(g, throwsA(isA<ConsentAccountChangedException>()));
      await pumpEventQueue();
      store.boundUid = 'B';
      gate.complete();
      await thrown;
      expect(store.writes, isEmpty, reason: 'nothing written for A or B');
      expect(store.values.containsKey('B'), isFalse);
      expect(slow.state, CloudStreamsConsent.unknown);
      expect(slow.isGranted, isFalse);
    });

    test('7b a store write failure in grant leaves the state unchanged',
        () async {
      store.writeError = StateError('disk');
      await expectLater(client.grant(), throwsStateError);
      expect(client.state, CloudStreamsConsent.unknown);
      expect(client.isGranted, isFalse);
    });

    test('8 withdraw persists before it returns and a later load stays '
        'withdrawn', () async {
      store.values['A'] = CloudStreamsConsent.granted;
      await client.load();
      await client.withdraw();
      expect(await store.read(), CloudStreamsConsent.withdrawn);
      client.reset();
      await client.load();
      expect(client.state, CloudStreamsConsent.withdrawn);
      expect(client.isGranted, isFalse);
      expect(server.requests, hasLength(1));
    });

    test('8b store write throws: the callable is still sent, the error is '
        'rethrown and a later load does not resurrect granted', () async {
      store.values['A'] = CloudStreamsConsent.granted;
      await client.load();
      store.writeError = StateError('disk full');
      await expectLater(client.withdraw(), throwsStateError);
      expect(server.requests, hasLength(1),
          reason: 'the server must still learn about the withdrawal');
      expect(client.isGranted, isFalse);
      await client.load(); // the store still holds granted
      expect(store.values['A'], CloudStreamsConsent.granted);
      expect(client.state, CloudStreamsConsent.withdrawn,
          reason: 'stale stored granted must not come back');
      expect(client.isGranted, isFalse);
    });

    test('9 withdraw before signIn completes is stored as withdrawn',
        () async {
      final prefs = installPrefs({_keyA: 'granted'});
      prefs.gateOnCall[1] = Completer<void>();
      final real = AccountScopedConsentStore();
      final c = ActivityCloudSettingsClient(call: server.call, store: real);
      final open = real.signIn('A');
      await pumpEventQueue();
      final w = c.withdraw();
      await pumpEventQueue();
      prefs.gateOnCall[1]!.complete();
      await open;
      await w;
      await c.load();
      expect((await prefs.getAll())[_keyA], 'withdrawn');
      expect(c.state, CloudStreamsConsent.withdrawn);
    });

    test('10 withdraw whose store write is gated: switch to B sends no request',
        () async {
      store.writeGate = Completer<void>();
      final gate = store.writeGate!;
      final f = client.withdraw();
      final thrown =
          expectLater(f, throwsA(isA<ConsentAccountChangedException>()));
      await pumpEventQueue();
      store.boundUid = 'B';
      gate.complete();
      await thrown;
      expect(server.requests, isEmpty,
          reason: 'a request now would hit account B');
    });

    test('11 deleteCloudStreamsNow is once per account, retried after a '
        'failure', () async {
      final uploader = ActivityStreamUploader(
        journal: _NoJournal(),
        callables: FakeStreamCloudStub(),
        consent: FakeConsent(true),
        put: (u, h, b) async => 200,
      );
      final wd = ActivityConsentWithdrawal(settings: client, uploader: uploader);
      await wd.deleteCloudStreamsNow();
      await wd.deleteCloudStreamsNow(); // same account: no-op
      expect(server.deleteRequests, hasLength(1));
      store.boundUid = 'B';
      await wd.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(2),
          reason: 'B\'s request must reach the callable after A\'s');
      store.boundUid = 'C';
      server.fault = (n) => n == server.requests.length ? StateError('x') : null;
      await expectLater(wd.deleteCloudStreamsNow(), throwsStateError);
      server.fault = null;
      await wd.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(4),
          reason: 'a failed request allows a retry for that account');
    });

    test('18b reset and signOut keep the stored consent of every account',
        () async {
      final prefs = installPrefs();
      final real = AccountScopedConsentStore();
      final c = ActivityCloudSettingsClient(call: server.call, store: real);
      await real.signIn('A');
      await c.grant();
      real.signOut();
      c.reset();
      await real.signIn('B');
      await c.grant();
      real.signOut();
      c.reset();
      final raw = await prefs.getAll();
      expect(raw[_keyA], 'granted');
      expect(raw[_keyB], 'granted');
      expect(c.isGranted, isFalse);
    });
  });

  group('uploader requires consentUid == its uid (H-A items 12 to 15)', () {
    late StreamUploadWorld w;
    final id = idFor(1);

    setUp(() async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(journalSession(id, seed: 0));
      await w.summarySync();
    });
    tearDown(() => w.dispose());

    test('12 consent of A or of nobody gives zero calls for B; control uploads',
        () async {
      for (final owner in <String?>['A', null]) {
        final consent = FakeConsent(true, fixedConsentUid: owner);
        final u = w.makeUploader(consentView: consent, currentUid: () => 'B');
        await u.runPending();
        expect(await u.uploadEntry(id), StreamUploadOutcome.skipped);
        expect(w.cloud.log, isEmpty, reason: 'consentUid=$owner, uploader B');
      }
      final ok = FakeConsent(true, fixedConsentUid: 'B');
      await w
          .makeUploader(consentView: ok, currentUid: () => 'B')
          .runPending();
      expect(w.cloud.log, ['create', 'put', 'commit']);
    });

    test('13 A granted then B signs in (unknown / withdrawn / stale sign-out): '
        'zero create, PUT, commit for B', () async {
      for (final bValue in <String>['none', 'withdrawn', 'signedOut']) {
        final prefs = installPrefs({
          _keyA: 'granted',
          if (bValue == 'withdrawn') _keyB: 'withdrawn',
        });
        final store = AccountScopedConsentStore();
        final client = ActivityCloudSettingsClient(
            call: FakeSettingsServer().call, store: store);
        var uid = 'A';
        final u = w.makeUploader(consentView: client, currentUid: () => uid);
        await store.signIn('A');
        await client.load();
        expect(client.isGranted, isTrue, reason: 'A is granted (control)');
        // Account switch WITHOUT the wiring's reset: the guards alone.
        uid = 'B';
        if (bValue == 'signedOut') {
          store.signOut();
          uid = 'B';
        } else {
          prefs.gateOnCall[prefs.calls + 1] = Completer<void>();
          forgetPrefs();
          final open = store.signIn('B');
          await pumpEventQueue();
          expect(client.isGranted, isFalse,
              reason: 'B opening, A\'s state must not count for B');
          await u.runPending();
          expect(w.cloud.log, isEmpty, reason: 'B init delayed: $bValue');
          prefs.gateOnCall.values.last.complete();
          await open;
        }
        expect(client.isGranted, isFalse,
            reason: 'B not loaded yet ($bValue)');
        await u.runPending();
        expect(w.cloud.log, isEmpty, reason: 'unloaded B ($bValue)');
        if (bValue != 'signedOut') {
          await client.load();
          expect(client.isGranted, isFalse, reason: 'B loaded: $bValue');
          await u.runPending();
          expect(w.cloud.log, isEmpty, reason: 'loaded B ($bValue)');
        }
        expect(await u.uploadEntry(id), isNot(StreamUploadOutcome.uploaded));
        expect(w.cloud.log, isEmpty);
      }
    });

    test('14a A -> B -> A within one upload: the epoch change blocks the mark',
        () async {
      final j = _FlipJournal(w.h.journal, 'A');
      final gate = Completer<void>();
      w.cloud.duringCommit = (n, _) => gate.future;
      final u = ActivityStreamUploader(
        journal: j,
        callables: w.cloud,
        consent: FakeConsent(true, fixedConsentUid: 'A'),
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        delay: (d) async => w.h.clock.advance(d),
        currentUid: () => 'A',
      );
      final run = u.uploadEntry(id);
      for (var i = 0; i < 200 && w.cloud.commits.isEmpty; i++) {
        await pumpEventQueue();
      }
      j.uid = 'B';
      u.cancelQueued(); // the wiring's reaction to the switch
      j.uid = 'A';
      u.resume();
      gate.complete();
      expect(await run, StreamUploadOutcome.cancelled);
      expect(j.marks, 0);
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
    });

    test('14b the journal bound uid changed between check and mark (no '
        'cancelQueued): no mark', () async {
      final j = _FlipJournal(w.h.journal, 'A');
      final gate = Completer<void>();
      w.cloud.duringCommit = (n, _) => gate.future;
      final u = ActivityStreamUploader(
        journal: j,
        callables: w.cloud,
        consent: FakeConsent(true, fixedConsentUid: 'A'),
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        delay: (d) async => w.h.clock.advance(d),
        currentUid: () => 'A',
      );
      final run = u.uploadEntry(id);
      for (var i = 0; i < 200 && w.cloud.commits.isEmpty; i++) {
        await pumpEventQueue();
      }
      j.uid = 'B';
      gate.complete();
      expect(await run, StreamUploadOutcome.cancelled);
      expect(j.marks, 0);
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
    });

    test('14c control: the journal stays bound to A and the mark happens',
        () async {
      final j = _FlipJournal(w.h.journal, 'A');
      final u = ActivityStreamUploader(
        journal: j,
        callables: w.cloud,
        consent: FakeConsent(true, fixedConsentUid: 'A'),
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        currentUid: () => 'A',
      );
      expect(await u.uploadEntry(id), StreamUploadOutcome.uploaded);
      expect(j.marks, 1);
    });

    test('14d the upload_failed update is not written for another journal '
        'scope', () async {
      final j = _FlipJournal(w.h.journal, 'A');
      w.cloud.duringCommit = (n, _) async {
        if (n == kStreamUploadMaxAttempts) j.uid = 'B';
      };
      w.cloud.commitFault = (n) => const StreamUploadTransient();
      final u = ActivityStreamUploader(
        journal: j,
        callables: w.cloud,
        consent: FakeConsent(true, fixedConsentUid: 'A'),
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        delay: (d) async => w.h.clock.advance(d),
        currentUid: () => 'A',
      );
      expect(await u.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(j.syncStateWrites, 0);
      expect((await w.stateOf(id)).syncState, JournalSyncState.synced);
    });

    ActivityStreamUploader deleting(String? Function() flag) =>
        ActivityStreamUploader(
          journal: w.h.journal,
          callables: w.cloud,
          consent: FakeConsent(true, fixedConsentUid: 'A'),
          put: w.cloud.put,
          flags: w.flags,
          now: w.h.clock.call,
          currentUid: () => 'A',
          accountBeingDeleted: flag,
        );

    test('15a deletion flagged before the run: no create', () async {
      await deleting(() => 'A').runPending();
      expect(w.cloud.log, isEmpty);
    });

    test('15b deletion flagged after create: no PUT, no commit', () async {
      String? flag;
      w.cloud.duringCreate = (n, _) async => flag = 'A';
      expect(await deleting(() => flag).uploadEntry(id),
          StreamUploadOutcome.cancelled);
      expect(w.cloud.log, ['create']);
    });

    test('15c deletion flagged after the PUT: no commit', () async {
      String? flag;
      w.cloud.duringPut = (n, _) async => flag = 'A';
      expect(await deleting(() => flag).uploadEntry(id),
          StreamUploadOutcome.cancelled);
      expect(w.cloud.log, ['create', 'put']);
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
    });

    test('15d another uid being deleted does not stop A (control)', () async {
      await deleting(() => 'Z').runPending();
      expect(w.cloud.log, ['create', 'put', 'commit']);
    });
  });
}

/// A callable client that is never used (the withdrawal tests only cancel).
class FakeStreamCloudStub implements ActivityStreamCallableClient {
  @override
  Future<CreateUploadResult> create(
          {required String activityId,
          required int bytes,
          required String contentSha256}) =>
      throw StateError('unused');
  @override
  Future<void> commit({required String activityId, required String uploadId}) =>
      throw StateError('unused');
}
