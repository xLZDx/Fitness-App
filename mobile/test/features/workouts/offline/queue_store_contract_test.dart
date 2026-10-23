// One contract suite, run unchanged over the in-memory and the file store.
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

void main() {
  for (final kind in <String>['in-memory', 'file']) {
    group('store contract [$kind]', () {
      late TestClock clock;
      late Directory? dir;
      late StoreFactory factory;
      late CommandQueueStore store;
      late IdMinter minter;
      late CompleteSetAcceptorHolder acc;

      setUp(() async {
        clock = TestClock();
        minter = IdMinter();
        if (kind == 'file') {
          dir = await makeTempRoot();
          factory = StoreFactory.file(clock, dir!);
        } else {
          dir = null;
          factory = StoreFactory.memory(clock);
        }
        store = await factory.open();
        acc = CompleteSetAcceptorHolder(store, clock, minter);
      });

      tearDown(() async {
        await store.dispose();
        if (dir != null) await removeTempRoot(dir!);
      });

      test('accept commits an ACCEPTED record with allocated seq, hash and bytes',
          () async {
        final r = await acc.acceptor.accept(intentOf('tap-1'));
        expect(r.created, isTrue);
        final rec = r.record;
        expect(rec.state, CommandState.accepted);
        expect(rec.uid, kUid);
        expect(rec.seq, 1);
        expect(rec.maybeSent, isFalse);
        expect(rec.attempts, 0);
        expect(rec.dependsOn, isEmpty);
        expect(rec.logicalSetId, 'sess-1:ex-squat:1');
        expect(payloadHashHex(rec.canonicalBytes!), rec.payloadHash);
        // The seq inside the hashed payload is the allocated one.
        expect(rec.payloadFields!['seq'], 1);
        expect(rec.payloadFields!['operationId'], rec.operationId);
        expect(canonicalBytes(rec.payloadFields), rec.canonicalBytes);
        expect((await store.get(rec.operationId))!.payloadHash, rec.payloadHash);
        expect((await store.listPending()).map((e) => e.operationId),
            <String>[rec.operationId]);
      });

      test('second identical submission (same intentKey) creates no second record',
          () async {
        final a = await acc.acceptor.accept(intentOf('tap-1'));
        final b = await acc.acceptor.accept(intentOf('tap-1'));
        expect(b.created, isFalse);
        expect(b.record.operationId, a.record.operationId);
        expect(b.record.canonicalBytes, a.record.canonicalBytes);
        expect(b.record.seq, 1);
        expect((await store.listAll()).length, 1);
        // A fresh id was minted for the duplicate and thrown away.
        expect(minter.mintedCount, 2);
      });

      test('same intentKey with different values still returns the ORIGINAL record',
          () async {
        final a = await acc.acceptor.accept(intentOf('tap-1', reps: 8));
        final b = await acc.acceptor.accept(intentOf('tap-1', reps: 12));
        expect(b.created, isFalse);
        expect(b.record.canonicalBytes, a.record.canonicalBytes);
        expect((b.record.payloadFields!['body']! as Map)['actualReps'], 8);
        expect((await store.listAll()).length, 1);
      });

      test('same operationId with an altered payload never overwrites the stored one',
          () async {
        final a = await acc.acceptor.accept(intentOf('tap-1', reps: 8));
        final original = a.record;
        // Hand-built request that reuses the operationId with different bytes.
        final forged = await store.accept(AcceptRequest(
          operationId: original.operationId,
          intentKey: 'other-intent',
          sessionId: 'sess-1',
          originDeviceInstallId: kDevice,
          logicalSetId: 'sess-1:ex-squat:1',
          build: (seq) => throw StateError('build must not run for a known id'),
        ));
        expect(forged.created, isFalse);
        final stored = (await store.get(original.operationId))!;
        expect(stored.canonicalBytes, original.canonicalBytes);
        expect(stored.payloadHash, original.payloadHash);
        expect((await store.listAll()).length, 1);
      });

      test('a built record whose bytes do not match its hash is refused and not stored',
          () async {
        final good = (await acc.acceptor.accept(intentOf('seed'))).record;
        final badBytes = canonicalBytes(<String, Object?>{'x': 1});
        await expectLater(
          store.accept(AcceptRequest(
            operationId: fixedOpId('op_bad'),
            intentKey: 'bad-intent',
            sessionId: 'sess-1',
            originDeviceInstallId: kDevice,
            logicalSetId: 'sess-1:ex-bad:1',
            build: (seq) => CommandRecord(
              uid: kUid,
              operationId: fixedOpId('op_bad'),
              sessionId: 'sess-1',
              exerciseId: 'ex-bad',
              operation: 'CompleteSet',
              sessionGeneration: 1,
              acceptedEpoch: 0,
              seq: seq,
              dependsOn: const <String>[],
              logicalSetId: 'sess-1:ex-bad:1',
              canonicalBytes: badBytes,
              payloadHash: good.payloadHash, // wrong hash on purpose
              payloadFields: const <String, Object?>{},
              protocolVersion: kProtocolVersion,
              hashVersion: kHashVersion,
              limitsVersion: kLimitsVersion,
              state: CommandState.accepted,
              originDeviceInstallId: kDevice,
              intentKey: 'bad-intent',
              acceptedAtLocalWallMs: 1,
              acceptedAtMonotonic: 1,
            ),
          )),
          throwsA(isA<QueueException>()),
        );
        expect(await store.get(fixedOpId('op_bad')), isNull);
        expect((await store.listAll()).length, 1);
      });

      test('non-empty dependsOn is refused in V0 and nothing is stored', () async {
        final seed = (await acc.acceptor.accept(intentOf('seed'))).record;
        await expectLater(
          store.accept(AcceptRequest(
            operationId: fixedOpId('op_dep'),
            intentKey: 'dep-intent',
            sessionId: 'sess-1',
            originDeviceInstallId: kDevice,
            logicalSetId: 'sess-1:ex-dep:1',
            build: (seq) {
              final p = buildCompleteSetPayload(
                operationId: fixedOpId('op_dep'),
                uid: kUid,
                sessionId: 'sess-1',
                originDeviceInstallId: kDevice,
                sessionGeneration: 1,
                acceptedEpoch: 0,
                seq: seq,
                dependsOn: <String>[seed.operationId],
                exerciseId: 'ex-dep',
                setIndex: 1,
                body: setBody(1),
              );
              final bytes = canonicalBytes(p);
              return CommandRecord(
                uid: kUid,
                operationId: fixedOpId('op_dep'),
                sessionId: 'sess-1',
                exerciseId: 'ex-dep',
                operation: 'CompleteSet',
                sessionGeneration: 1,
                acceptedEpoch: 0,
                seq: seq,
                dependsOn: <String>[seed.operationId],
                logicalSetId: 'sess-1:ex-dep:1',
                canonicalBytes: bytes,
                payloadHash: payloadHashHex(bytes),
                payloadFields: p,
                protocolVersion: kProtocolVersion,
                hashVersion: kHashVersion,
                limitsVersion: kLimitsVersion,
                state: CommandState.accepted,
                originDeviceInstallId: kDevice,
                intentKey: 'dep-intent',
                acceptedAtLocalWallMs: 1,
                acceptedAtMonotonic: 1,
              );
            },
          )),
          throwsA(isA<QueueException>()),
        );
        expect(await store.get(fixedOpId('op_dep')), isNull);
        expect((await store.listAll()).length, 1);
      });

      test('a second APPEND for the same logical set (new intent) is refused',
          () async {
        final a = await acc.acceptor.accept(intentOf('tap-1', reps: 8));
        await expectLater(
            acc.acceptor.accept(intentOf('tap-2', reps: 9)),
            throwsA(isA<DuplicateLogicalSetException>()));
        final all = await store.listAll();
        expect(all.length, 1);
        expect(all.single.operationId, a.record.operationId);
        expect((all.single.payloadFields!['body']! as Map)['actualReps'], 8);
      });

      test('the logical-set guard also holds after the first APPEND is SYNCED',
          () async {
        final a = await acc.acceptor.accept(intentOf('tap-1'));
        await store.markSending(a.record.operationId);
        await store.markResult(a.record.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
        await expectLater(acc.acceptor.accept(intentOf('tap-2')),
            throwsA(isA<DuplicateLogicalSetException>()));
        expect((await store.listAll()).length, 1);
      });

      test('seq is per (session, device), starts at 1 and only grows', () async {
        final a = await acc.acceptor.accept(intentOf('t1', setIndex: 1));
        final b = await acc.acceptor.accept(intentOf('t2', setIndex: 2));
        final c = await acc.acceptor
            .accept(intentOf('t3', sessionId: 'sess-2', setIndex: 1));
        final d = await acc.acceptor.accept(intentOf('t4', setIndex: 3));
        expect(<int>[a.record.seq, b.record.seq, c.record.seq, d.record.seq],
            <int>[1, 2, 1, 3]);
        expect(<String>{
          a.record.operationId, b.record.operationId, c.record.operationId,
          d.record.operationId
        }.length, 4);
      });

      test('concurrent identical submissions yield exactly one record', () async {
        final results = await Future.wait(<Future<AcceptResult>>[
          for (var i = 0; i < 8; i++) acc.acceptor.accept(intentOf('same-tap')),
        ]);
        expect(results.where((r) => r.created).length, 1);
        expect(results.map((r) => r.record.operationId).toSet().length, 1);
        expect((await store.listAll()).length, 1);
      });

      test('concurrent distinct submissions get distinct dense seqs', () async {
        final results = await Future.wait(<Future<AcceptResult>>[
          for (var i = 1; i <= 6; i++)
            acc.acceptor.accept(intentOf('tap-$i', setIndex: i)),
        ]);
        expect(results.map((r) => r.record.seq).toList()..sort(),
            <int>[1, 2, 3, 4, 5, 6]);
      });

      test('uid mismatch: a record built for another uid is refused', () async {
        await expectLater(
          store.accept(AcceptRequest(
            operationId: fixedOpId('op_x'),
            intentKey: 'x',
            sessionId: 'sess-1',
            originDeviceInstallId: kDevice,
            logicalSetId: 'sess-1:ex-x:1',
            build: (seq) {
              final p = buildCompleteSetPayload(
                operationId: fixedOpId('op_x'),
                uid: kOtherUid,
                sessionId: 'sess-1',
                originDeviceInstallId: kDevice,
                sessionGeneration: 1,
                acceptedEpoch: 0,
                seq: seq,
                dependsOn: const <String>[],
                exerciseId: 'ex-x',
                setIndex: 1,
                body: setBody(1),
              );
              final bytes = canonicalBytes(p);
              return CommandRecord(
                uid: kOtherUid,
                operationId: fixedOpId('op_x'),
                sessionId: 'sess-1',
                exerciseId: 'ex-x',
                operation: 'CompleteSet',
                sessionGeneration: 1,
                acceptedEpoch: 0,
                seq: seq,
                dependsOn: const <String>[],
                logicalSetId: 'sess-1:ex-x:1',
                canonicalBytes: bytes,
                payloadHash: payloadHashHex(bytes),
                payloadFields: p,
                protocolVersion: kProtocolVersion,
                hashVersion: kHashVersion,
                limitsVersion: kLimitsVersion,
                state: CommandState.accepted,
                originDeviceInstallId: kDevice,
                intentKey: 'x',
                acceptedAtLocalWallMs: 1,
                acceptedAtMonotonic: 1,
              );
            },
          )),
          throwsA(isA<UidMismatchException>()),
        );
        expect(await store.listAll(), isEmpty);
      });

      test('another uid never sees these records', () async {
        await acc.acceptor.accept(intentOf('tap-1'));
        final other = await factory.open(kOtherUid);
        try {
          expect(await other.listAll(), isEmpty);
          expect(await other.listPending(), isEmpty);
          final mine = (await store.listAll()).single;
          expect(await other.get(mine.operationId), isNull);
        } finally {
          await other.dispose();
        }
      });

      test('the 500 record cap counts only unresolved records', () async {
        for (var i = 1; i <= kQueueRecordCap; i++) {
          await acc.acceptor
              .accept(intentOf('t$i', exerciseId: 'ex-$i', setIndex: 1));
        }
        await expectLater(
            acc.acceptor
                .accept(intentOf('overflow', exerciseId: 'ex-over', setIndex: 1)),
            throwsA(isA<QueueFullException>()));
        expect((await store.listAll()).length, kQueueRecordCap);
        // Resolving one record frees one slot.
        final first = (await store.listAll()).first;
        await store.markSending(first.operationId);
        await store.markResult(first.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
        final again = await acc.acceptor
            .accept(intentOf('overflow', exerciseId: 'ex-over', setIndex: 1));
        expect(again.created, isTrue);
      });

      test('markSending sets SENDING, maybeSent and attempts in one step', () async {
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        clock.advance(const Duration(seconds: 3));
        final s = await store.markSending(r.operationId);
        expect(s.state, CommandState.sending);
        expect(s.maybeSent, isTrue);
        expect(s.attempts, 1);
        expect(s.lastAttemptLocalMs, clock.ms);
        expect(s.canonicalBytes, r.canonicalBytes);
        expect(await store.listPending(), isEmpty); // SENDING is not pickable
        await expectLater(store.markSending(r.operationId),
            throwsA(isA<InvalidTransitionException>()));
      });

      test('maybeSent never resets and attempts count every send', () async {
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        await store.markSending(r.operationId);
        await store.markResult(r.operationId,
            const CommandResult(to: CommandState.accepted, resultCode: 'DEPENDENCY_PENDING'));
        final back = (await store.get(r.operationId))!;
        expect(back.state, CommandState.accepted);
        expect(back.maybeSent, isTrue);
        final s2 = await store.markSending(r.operationId);
        expect(s2.attempts, 2);
      });

      test('SYNCED erases payload, keeps the stub and is idempotent', () async {
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        await store.markSending(r.operationId);
        final done = await store.markResult(
            r.operationId,
            const CommandResult(
                to: CommandState.synced,
                resultCode: 'COMMITTED',
                revisionAfter: 5,
                serverTimeMs: 99));
        expect(done.state, CommandState.synced);
        expect(done.canonicalBytes, isNull);
        expect(done.payloadFields, isNull);
        expect(done.payloadHash, r.payloadHash);
        expect(done.seq, r.seq);
        expect(done.logicalSetId, r.logicalSetId);
        expect(done.ackSummary!.revisionAfter, 5);
        expect(done.ackSummary!.localAckMs, clock.ms);
        final again = await store.markResult(r.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'ALREADY_COMMITTED'));
        expect(again.lastResultCode, 'COMMITTED'); // untouched by the replay
        expect(await store.listPending(), isEmpty);
      });

      test('invalid transitions are refused and leave the record unchanged',
          () async {
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        // ACCEPTED -> SYNCED directly (no send) must not be possible.
        await expectLater(
            store.markResult(r.operationId,
                const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED')),
            throwsA(isA<InvalidTransitionException>()));
        await expectLater(
            store.markResult('nope',
                const CommandResult(to: CommandState.synced)),
            throwsA(isA<InvalidTransitionException>()));
        await expectLater(store.markSending('nope'),
            throwsA(isA<InvalidTransitionException>()));
        expect((await store.get(r.operationId))!.state, CommandState.accepted);
        // SENDING -> DISCARDED / HELD are not result states.
        await store.markSending(r.operationId);
        await expectLater(
            store.markResult(r.operationId,
                const CommandResult(to: CommandState.discarded)),
            throwsA(isA<InvalidTransitionException>()));
        await expectLater(
            store.markResult(r.operationId,
                const CommandResult(to: CommandState.held)),
            throwsA(isA<InvalidTransitionException>()));
        expect((await store.get(r.operationId))!.state, CommandState.sending);
      });

      test('UNKNOWN_EFFECT is pickable again and cannot jump straight to SYNCED',
          () async {
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        await store.markSending(r.operationId);
        await store.markResult(r.operationId,
            const CommandResult(to: CommandState.unknownEffect, resultCode: 'UNAVAILABLE'));
        expect((await store.listPending()).single.state, CommandState.unknownEffect);
        await expectLater(
            store.markResult(r.operationId,
                const CommandResult(to: CommandState.synced)),
            throwsA(isA<InvalidTransitionException>()));
        final s = await store.markSending(r.operationId);
        expect(s.attempts, 2);
      });

      test('listAll / listPending order: acceptance time, then seq', () async {
        final a = await acc.acceptor.accept(intentOf('a', setIndex: 1));
        clock.advance(const Duration(seconds: 1));
        final b = await acc.acceptor.accept(intentOf('b', setIndex: 2));
        clock.advance(const Duration(seconds: 1));
        final c = await acc.acceptor
            .accept(intentOf('c', sessionId: 'sess-2', setIndex: 1));
        expect((await store.listAll()).map((e) => e.operationId),
            <String>[a.record.operationId, b.record.operationId, c.record.operationId]);
      });

      test('prune removes only SYNCED stubs older than 7 days and keeps seq counters',
          () async {
        final a = (await acc.acceptor.accept(intentOf('a', setIndex: 1))).record;
        final b = (await acc.acceptor.accept(intentOf('b', setIndex: 2))).record;
        final c = (await acc.acceptor.accept(intentOf('c', setIndex: 3))).record;
        for (final r in <CommandRecord>[a, b]) {
          await store.markSending(r.operationId);
          await store.markResult(r.operationId,
              const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
          clock.advance(const Duration(days: 4)); // a acked day 0, b day 4
        }
        // now = day 8: a is 8 days old, b is 4 days old, c is unresolved.
        expect(await store.prune(), 1);
        expect(await store.get(a.operationId), isNull);
        expect(await store.get(b.operationId), isNotNull);
        expect((await store.get(c.operationId))!.state, CommandState.accepted);
        clock.advance(const Duration(days: 30));
        expect(await store.prune(), 1); // b goes, c (ACCEPTED) never
        expect((await store.get(c.operationId))!.state, CommandState.accepted);
        expect((await store.listAll()).length, 1);
        // seq counter survived the pruning: no seq is ever reused.
        final d = (await acc.acceptor.accept(intentOf('d', setIndex: 4))).record;
        expect(d.seq, 4);
      });

      test('prune boundary: kept until 7 days have fully elapsed', () async {
        final a = (await acc.acceptor.accept(intentOf('a'))).record;
        await store.markSending(a.operationId);
        await store.markResult(a.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
        clock.advance(kStubRetention - const Duration(milliseconds: 1));
        expect(await store.prune(), 0);
        clock.advance(const Duration(milliseconds: 1));
        expect(await store.prune(), 1);
      });

      test('changes stream fires once per committed change', () async {
        var n = 0;
        final sub = store.changes.listen((_) => n++);
        final r = (await acc.acceptor.accept(intentOf('t'))).record;
        await acc.acceptor.accept(intentOf('t')); // duplicate: no change
        await store.markSending(r.operationId);
        await store.markResult(r.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(n, 3);
      });
    });
  }
}

/// Keeps the acceptor construction in one place for the suite above.
class CompleteSetAcceptorHolder {
  CompleteSetAcceptorHolder(CommandQueueStore store, TestClock clock, IdMinter m)
      : acceptor = acceptorFor(store, clock, minter: m);
  final CompleteSetAcceptor acceptor;
}
