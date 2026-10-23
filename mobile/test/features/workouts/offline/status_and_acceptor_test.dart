// Honest pending vs synced status after every transition, plus the
// CompleteSet acceptor's behaviour as seen through the real queue.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:fitness_app/features/workouts/offline/status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

void main() {
  for (final kind in <String>['in-memory', 'file']) {
    group('status [$kind]', () {
      late TestClock clock;
      Directory? dir;
      late StoreFactory factory;
      late CommandQueueStore store;
      late CompleteSetAcceptor acceptor;
      late FakeServer server;
      late CommandSender sender;
      late StoreSyncStatusSource source;

      setUp(() async {
        clock = TestClock();
        server = FakeServer();
        if (kind == 'file') {
          dir = await makeTempRoot();
          factory = StoreFactory.file(clock, dir!);
        } else {
          dir = null;
          factory = StoreFactory.memory(clock);
        }
        store = await factory.open();
        acceptor = acceptorFor(store, clock);
        sender = senderFor(store, server, clock,
            sendTimeout: const Duration(milliseconds: 50));
        source = StoreSyncStatusSource(store);
      });

      tearDown(() async {
        await store.dispose();
        if (dir != null) await removeTempRoot(dir!);
      });

      test('empty queue: nothing pending, nothing synced', () async {
        final s = await source.snapshot();
        expect(s.pending, 0);
        expect(s.synced, 0);
        expect(s.hasPending, isFalse);
        expect(s.sessions, isEmpty);
        expect(s.forSession('sess-1').pending, 0);
      });

      test('pending is not synced at every step until the server acknowledges',
          () async {
        await acceptor.accept(intentOf('tap-1'));
        var s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced, s.couldNotSync), (1, 0, 0));
        expect(s.hasPending, isTrue);
        expect(s.isFullySynced, isFalse);

        // Lost ack: the server applied it but the client does not know.
        server.faults.add(Fault.applyThenThrow);
        await sender.sendNext();
        expect(server.effects.length, 1);
        s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced), (1, 0),
            reason: 'unknown effect must still read as pending');
        expect(s.isFullySynced, isFalse);

        sender.resetBackoff();
        await sender.sendNext();
        s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced, s.couldNotSync), (0, 1, 0));
        expect(s.isFullySynced, isTrue);
      });

      test('SENDING counts as pending (record being sent is not synced yet)',
          () async {
        final r = (await acceptor.accept(intentOf('tap-1'))).record;
        await store.markSending(r.operationId);
        final s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced), (1, 0));
      });

      test('a hold answer or unknown code leaves the record pending, never synced',
          () async {
        await acceptor.accept(intentOf('t1', setIndex: 1));
        await acceptor.accept(intentOf('t2', setIndex: 2));
        server.scriptedCodes.add('MIGRATION_HOLD');
        await sender.sendNext();
        var s = (await source.snapshot());
        expect((s.pending, s.synced), (2, 0));
        sender.resetBackoff();
        server.scriptedCodes.add('CODE_FROM_THE_FUTURE');
        await sender.sendNext();
        s = await source.snapshot();
        expect((s.pending, s.synced), (2, 0));
      });

      test('terminal refusal is "could not sync": not pending, not synced',
          () async {
        await acceptor.accept(intentOf('tap-1'));
        server.scriptedCodes.add('SESSION_CLOSED');
        await sender.sendNext();
        final s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced, s.couldNotSync), (0, 0, 1));
        expect(s.isFullySynced, isFalse);
        expect(s.hasPending, isFalse);
      });

      test('SUPERSEDED is counted apart and not as plain synced', () async {
        await acceptor.accept(intentOf('tap-1'));
        server.scriptedCodes.add('SUPERSEDED');
        await sender.sendNext();
        final s = (await source.snapshot()).forSession('sess-1');
        expect((s.pending, s.synced, s.superseded), (0, 0, 1));
        expect((await source.snapshot()).synced, 0);
      });

      test('counts are per session and totals add up', () async {
        await acceptor.accept(intentOf('a1', sessionId: 'A', setIndex: 1));
        await acceptor.accept(intentOf('a2', sessionId: 'A', setIndex: 2));
        await acceptor.accept(intentOf('b1', sessionId: 'B', setIndex: 1));
        clock.advance(const Duration(seconds: 1));
        await sender.sendNext(); // oldest first: A seq 1 -> synced
        final snap = await source.snapshot();
        expect(snap.forSession('A').pending, 1);
        expect(snap.forSession('A').synced, 1);
        expect(snap.forSession('B').pending, 1);
        expect(snap.forSession('B').synced, 0);
        expect(snap.pending, 2);
        expect(snap.synced, 1);
        expect(snap.hasPending, isTrue);
        await sender.sendAvailable();
        final done = await source.snapshot();
        expect((done.pending, done.synced), (0, 3));
      });

      test('watch() emits the current snapshot first and then each change',
          () async {
        final seen = <(int, int)>[];
        final sub = source.watch().listen((s) => seen.add((s.pending, s.synced)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await acceptor.accept(intentOf('tap-1'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sender.sendNext();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel().timeout(const Duration(seconds: 2),
            onTimeout: () => fail('cancel() of watch() hung'));
        expect(seen.first, (0, 0));
        expect(seen, contains((1, 0)));
        expect(seen.last, (0, 1));
        // The synced count never appears before the ack was committed.
        final firstSynced = seen.indexOf((0, 1));
        expect(seen.sublist(0, firstSynced).every((e) => e.$2 == 0), isTrue);
      });

      test('cancelling an idle watch() subscription returns promptly', () async {
        final sub = source.watch().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel().timeout(const Duration(seconds: 2),
            onTimeout: () => fail('cancel() of an idle watch() hung'));
        await acceptor.accept(intentOf('after-cancel'));
        expect((await source.snapshot()).pending, 1);
      });

      test('status stays honest after a restart (file store only)', () async {
        if (dir == null) return;
        final r = (await acceptor.accept(intentOf('tap-1'))).record;
        await store.markSending(r.operationId);
        final reopened = await factory.open();
        final s = (await StoreSyncStatusSource(reopened).snapshot())
            .forSession('sess-1');
        expect((s.pending, s.synced), (1, 0));
        await reopened.dispose();
      });
    });
  }

  group('summarizeRecords (pure)', () {
    CommandRecord rec(String id, String session, CommandState st,
            {AckSummary? ack}) =>
        CommandRecord(
          uid: kUid,
          operationId: id,
          sessionId: session,
          exerciseId: 'e',
          operation: 'CompleteSet',
          sessionGeneration: 1,
          acceptedEpoch: 0,
          seq: 1,
          dependsOn: const <String>[],
          logicalSetId: '$session:e:1',
          canonicalBytes: null,
          payloadHash: 'h',
          payloadFields: null,
          protocolVersion: 2,
          hashVersion: 2,
          limitsVersion: 1,
          state: st,
          originDeviceInstallId: kDevice,
          intentKey: id,
          ackSummary: ack,
          acceptedAtLocalWallMs: 0,
          acceptedAtMonotonic: 0,
        );

    test('every state maps to exactly one bucket; DISCARDED is invisible', () {
      final snap = summarizeRecords(<CommandRecord>[
        rec('1', 's', CommandState.accepted),
        rec('2', 's', CommandState.sending),
        rec('3', 's', CommandState.unknownEffect),
        rec('4', 's', CommandState.held),
        rec('5', 's', CommandState.synced,
            ack: const AckSummary(localAckMs: 1)),
        rec('6', 's', CommandState.synced,
            ack: const AckSummary(localAckMs: 1, superseded: true)),
        rec('7', 's', CommandState.conflicted),
        rec('8', 's', CommandState.discarded),
      ]);
      final s = snap.forSession('s');
      expect(s.pending, 4);
      expect(s.synced, 1);
      expect(s.superseded, 1);
      expect(s.couldNotSync, 1);
      expect(snap.sessions.length, 1);
    });

    test('only discarded records: the session does not appear at all', () {
      final snap = summarizeRecords(
          <CommandRecord>[rec('1', 's', CommandState.discarded)]);
      expect(snap.sessions, isEmpty);
    });

    test('a synced stub without ackSummary still counts as synced', () {
      final snap =
          summarizeRecords(<CommandRecord>[rec('1', 's', CommandState.synced)]);
      expect(snap.synced, 1);
    });
  });

  group('acceptor', () {
    late TestClock clock;
    late CommandQueueStore store;

    setUp(() async {
      clock = TestClock();
      store = await StoreFactory.memory(clock).open();
    });
    tearDown(() => store.dispose());

    test('a body that violates the closed field set is rejected and nothing is stored',
        () async {
      final acc = acceptorFor(store, clock);
      final bad = CompleteSetIntent(
        sessionId: 'sess-1',
        exerciseId: 'ex',
        setIndex: 1,
        intentKey: 'k',
        body: <String, Object?>{...setBody(1), 'reps': 5},
      );
      await expectLater(
          acc.accept(bad), throwsA(isA<CanonicalizationException>()));
      expect(await store.listAll(), isEmpty);
    });

    test('a double in the body is refused (integers only)', () async {
      final acc = acceptorFor(store, clock);
      final bad = CompleteSetIntent(
        sessionId: 'sess-1',
        exerciseId: 'ex',
        setIndex: 1,
        intentKey: 'k',
        body: <String, Object?>{...setBody(1), 'loadGrams': 60000.5},
      );
      await expectLater(
          acc.accept(bad), throwsA(isA<CanonicalizationException>()));
      expect(await store.listAll(), isEmpty);
    });

    test('stored bytes equal the canonical text of the stored fields and hash to payloadHash',
        () async {
      final acc = acceptorFor(store, clock);
      final r = (await acc.accept(CompleteSetIntent(
        sessionId: 'sess-1',
        exerciseId: 'ex-e',
        setIndex: 3,
        intentKey: 'k',
        body: setBody(3, loadGrams: null),
        sessionInit: const <String, Object?>{
          'titleKey': 'day:legs',
          'dayId': null,
          'startedAtClientMs': 1700000000000,
        },
      )))
          .record;
      expect(String.fromCharCodes(r.canonicalBytes!.where((b) => b < 0x80)),
          isNotEmpty);
      expect(canonicalBytes(r.payloadFields), r.canonicalBytes);
      expect(payloadHashHex(r.canonicalBytes!), r.payloadHash);
      expect(r.payloadFields!['sessionInit'], isNotNull);
      expect(r.payloadFields!['dependsOn'], isEmpty);
      expect(r.logicalSetId, 'sess-1:ex-e:3');
    });

    test('wall and monotonic clocks come from the injected sources', () async {
      clock.ms = 1234567;
      final r =
          (await acceptorFor(store, clock).accept(intentOf('k'))).record;
      expect(r.acceptedAtLocalWallMs, 1234567);
      expect(r.acceptedAtMonotonic, 1234567);
    });

    test('device id is stamped into the record and the hashed payload', () async {
      final r = (await acceptorFor(store, clock, device: 'dev-X')
              .accept(intentOf('k')))
          .record;
      expect(r.originDeviceInstallId, 'dev-X');
      expect(r.payloadFields!['originDeviceInstallId'], 'dev-X');
    });

    test('two devices of the same uid and session keep independent seq counters',
        () async {
      final a = (await acceptorFor(store, clock, device: 'dev-A')
              .accept(intentOf('k1', setIndex: 1)))
          .record;
      final b = (await acceptorFor(store, clock, device: 'dev-B')
              .accept(intentOf('k2', setIndex: 2)))
          .record;
      expect((a.seq, b.seq), (1, 1));
    });

    test('a CONFLICTED first APPEND still blocks a second APPEND for the same set',
        () async {
      final acc = acceptorFor(store, clock);
      final r = (await acc.accept(intentOf('k1'))).record;
      await store.markSending(r.operationId);
      await store.markResult(
          r.operationId,
          const CommandResult(
              to: CommandState.conflicted,
              resultCode: 'SESSION_CLOSED',
              conflictTerminal: true));
      await expectLater(acc.accept(intentOf('k2')),
          throwsA(isA<DuplicateLogicalSetException>()));
    });
  });

  group('regression: logical-set guard survives stub pruning', () {
    for (final kind in <String>['in-memory', 'file']) {
      test('[$kind] after the SYNCED stub is pruned a new tap on the same set is refused',
          () async {
        final clock = TestClock();
        final dir = kind == 'file' ? await makeTempRoot() : null;
        final factory =
            dir == null ? StoreFactory.memory(clock) : StoreFactory.file(clock, dir);
        final store = await factory.open();
        final minter = IdMinter();
        final acc = acceptorFor(store, clock, minter: minter);
        try {
          final first = (await acc.accept(intentOf('k1'))).record;
          await store.markSending(first.operationId);
          await store.markResult(first.operationId,
              const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
          clock.advance(const Duration(days: 8));
          expect(await store.prune(), 1);
          expect(await store.get(first.operationId), isNull); // stub is gone
          await expectLater(acc.accept(intentOf('k2-new-tap')),
              throwsA(isA<DuplicateLogicalSetException>()));
          expect(await store.listAll(), isEmpty);
          if (dir != null) {
            final again = await factory.open();
            await expectLater(
                acceptorFor(again, clock, minter: minter)
                    .accept(intentOf('k3-after-restart')),
                throwsA(isA<DuplicateLogicalSetException>()));
            await again.dispose();
          }
        } finally {
          await store.dispose();
          if (dir != null) await removeTempRoot(dir);
        }
      });
    }
  });
}
