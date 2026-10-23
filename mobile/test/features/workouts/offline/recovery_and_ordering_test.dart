// Metadata redundancy (checksum + backup twin, fail closed) and the
// proof / NOT_WRITER ordering contract of the sender.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store_base.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/in_memory_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/queue_file_ops.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

/// Delegating store that counts the calls that matter to the proof contract.
class _SpyStore implements CommandQueueStore {
  _SpyStore(this.inner);
  final CommandQueueStore inner;
  int markSendingCalls = 0;
  @override
  String get uid => inner.uid;
  @override
  Stream<void> get changes => inner.changes;
  @override
  Future<AcceptResult> accept(AcceptRequest r) => inner.accept(r);
  @override
  Future<CommandRecord?> get(String id) => inner.get(id);
  @override
  Future<List<CommandRecord>> listAll() => inner.listAll();
  @override
  Future<List<CommandRecord>> listPending() => inner.listPending();
  @override
  Future<CommandRecord> markSending(String id) {
    markSendingCalls++;
    return inner.markSending(id);
  }

  @override
  Future<CommandRecord> markResult(String id, CommandResult r) =>
      inner.markResult(id, r);
  @override
  Future<int> prune() => inner.prune();
  @override
  Future<void> dispose() => inner.dispose();
}

/// Answers NOT_WRITER (applying nothing) unless the proof is the expected one.
class _ProofGate implements CommandTransport {
  _ProofGate(this.inner, this.expected);
  final FakeServer inner;
  String expected;
  final List<String> log = <String>[];
  @override
  Future<TransportAnswer> send(CommandEnvelope e) {
    log.add(e.operationId);
    if (e.writerProof != expected) {
      inner.received.add(e);
      return Future.value(const TransportAnswer(code: 'NOT_WRITER'));
    }
    return inner.send(e);
  }
}

void main() {
  late Directory dir;
  late TestClock clock;
  late IdMinter minter;
  late FakeServer server;
  FileCommandQueueStore? live;

  Future<FileCommandQueueStore> open({QueueFileOps ops = const IoQueueFileOps()}) async {
    await live?.dispose();
    live = await FileCommandQueueStore.open(
        uid: kUid, rootDir: rootPathOf(dir), ops: ops, nowMs: clock.nowMs);
    return live!;
  }

  String scope() => '${rootPathOf(dir)}/${queueScopeDirName(kUid)}';
  CompleteSetAcceptor accFor(CommandQueueStore s) =>
      acceptorFor(s, clock, minter: minter);

  setUp(() async {
    dir = await makeTempRoot();
    clock = TestClock();
    minter = IdMinter();
    server = FakeServer();
  });
  tearDown(() async {
    await live?.dispose();
    live = null;
    await removeTempRoot(dir);
  });

  group('M01 no proof, no send', () {
    test('the fake server itself refuses a command without a proof', () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      final rec = (await accFor(store).accept(intentOf('t'))).record;
      final a = await server.send(CommandEnvelope(
          operationId: rec.operationId,
          payloadBytes: rec.canonicalBytes!,
          payloadHash: rec.payloadHash,
          writerProof: null,
          writerEpochClaim: 0,
          deviceInstallId: kDevice,
          clientBuild: 'b'));
      expect(a.code, 'INVALID_PAYLOAD');
      expect(server.effects, isEmpty);
      await store.dispose();
    });

    for (final entry in <String, Future<String?> Function(String, String)>{
      'missing (null)': (u, s) async => null,
      'empty': (u, s) async => '',
      'unreadable (throws)': (u, s) async => throw StateError('keystore'),
    }.entries) {
      test('${entry.key} proof: markSending and the transport are never called',
          () async {
        final spy = _SpyStore(
            InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs));
        final rec = (await accFor(spy).accept(intentOf('t'))).record;
        final sender = senderFor(spy, server, clock, proof: entry.value);
        for (var i = 0; i < 3; i++) {
          sender.resetBackoff();
          final rep = await sender.sendNext();
          expect(rep.status, SendStatus.proofUnavailable);
        }
        expect(spy.markSendingCalls, 0);
        expect(server.received, isEmpty);
        final r = (await spy.get(rec.operationId))!;
        expect(r.state, CommandState.accepted);
        expect(r.maybeSent, isFalse);
        expect(r.attempts, 0);
        await spy.dispose();
      });
    }
  });

  group('M02 NOT_WRITER keeps the order', () {
    Future<(CommandRecord, CommandRecord)> twoSets(CommandQueueStore s) async {
      final a = (await accFor(s).accept(intentOf('s1', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      final b = (await accFor(s).accept(intentOf('s2', setIndex: 2))).record;
      return (a, b);
    }

    test('NOT_WRITER, restart, reset, corrected proof: set 1 is delivered before set 2 and set 2 never overtakes',
        () async {
      var s = await open();
      final (set1, set2) = await twoSets(s);
      final gate = _ProofGate(server, 'good');
      var token = 'stale';
      var sender = senderFor(s, gate, clock, proof: (u, sid) async => token);

      final first = await sender.sendNext();
      expect(first.status, SendStatus.conflicted);
      expect(first.code, 'NOT_WRITER');
      expect((await s.get(set1.operationId))!.state, CommandState.accepted);
      // Inside the backoff nothing is sent, in particular not set 2.
      expect((await sender.sendNext()).status, SendStatus.sessionOnHold);
      expect(gate.log, <String>[set1.operationId]);

      // Restart: holds are in memory and gone; set 1 must still go first.
      s = await open();
      sender = senderFor(s, gate, clock, proof: (u, sid) async => token);
      expect((await sender.sendNext()).code, 'NOT_WRITER');
      expect(gate.log, <String>[set1.operationId, set1.operationId]);
      expect((await s.listPending()).first.operationId, set1.operationId);

      // resetBackoff with the proof still wrong: still set 1 only.
      sender.resetBackoff();
      expect((await sender.sendNext()).code, 'NOT_WRITER');
      expect(gate.log.every((id) => id == set1.operationId), isTrue);

      token = 'good';
      sender.resetBackoff();
      final reports = await sender.sendAvailable();
      expect(reports.where((r) => r.status == SendStatus.synced).length, 2);
      expect(server.effects.map((e) => e.operationId).toList(),
          <String>[set1.operationId, set2.operationId]);
      expect(gate.log.indexOf(set2.operationId),
          greaterThan(gate.log.lastIndexOf(set1.operationId)));
    });

    test('SESSION_COMMAND_LIMIT behaves the same way and other sessions are unaffected',
        () async {
      final s = await open();
      final a = (await accFor(s).accept(intentOf('a1', sessionId: 'A', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      await accFor(s).accept(intentOf('a2', sessionId: 'A', setIndex: 2));
      clock.advance(const Duration(seconds: 1));
      final b = (await accFor(s).accept(intentOf('b1', sessionId: 'B'))).record;
      server.scriptedCodes.add('SESSION_COMMAND_LIMIT');
      final sender = senderFor(s, server, clock);
      expect((await sender.sendNext()).operationId, a.operationId);
      final next = await sender.sendNext();
      expect(next.status, SendStatus.synced);
      expect(next.operationId, b.operationId);
      expect((await sender.sendNext()).status, SendStatus.sessionOnHold);
      expect(server.effects.map((e) => e.operationId).toList(), <String>[b.operationId]);
    });

    test('an old-build non-terminal CONFLICTED record is a session barrier, also after restart',
        () async {
      var s = await open();
      final a = (await accFor(s).accept(intentOf('a1', sessionId: 'A', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      final a2 = (await accFor(s).accept(intentOf('a2', sessionId: 'A', setIndex: 2))).record;
      clock.advance(const Duration(seconds: 1));
      final b = (await accFor(s).accept(intentOf('b1', sessionId: 'B'))).record;
      await s.markSending(a.operationId);
      await s.markResult(
          a.operationId,
          const CommandResult(
              to: CommandState.conflicted,
              resultCode: 'NOT_WRITER',
              conflictTerminal: false));
      s = await open(); // restart
      expect((await s.get(a.operationId))!.conflictTerminal, isFalse);
      final sender = senderFor(s, server, clock);
      final reports = await sender.sendAvailable();
      expect(reports.first.operationId, b.operationId);
      expect(server.effects.map((e) => e.operationId).toList(), <String>[b.operationId]);
      expect(server.received.any((e) => e.operationId == a2.operationId), isFalse,
          reason: 'seq 2 must not overtake the barrier');
      expect((await s.get(a2.operationId))!.state, CommandState.accepted);
    });

    test('a terminal conflict does not block later sets of the session', () async {
      final s = await open();
      final (set1, set2) = await twoSets(s);
      server.scriptedCodes.add('SESSION_CLOSED');
      final sender = senderFor(s, server, clock);
      expect((await sender.sendNext()).status, SendStatus.conflicted);
      expect((await s.get(set1.operationId))!.conflictTerminal, isTrue);
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.synced);
      expect(rep.operationId, set2.operationId);
    });
  });

  group('M03 two-slot metadata document', () {
    String key() => BaseCommandQueueStore.seqKey('sess-1', kDevice);

    /// A slot file exactly as the store frames it (valid checksum).
    String framed(int gen, Map<String, int> seq, {bool checksum = true}) {
      final body = jsonEncode(<String, Object?>{
        'format': 2,
        'gen': gen,
        'seq': seq,
        'logicalSets': <String, Object?>{},
      });
      return checksum
          ? '$body\n#sha256:${payloadHashHex(utf8.encode(body))}\n'
          : '$body\n';
    }

    /// Accepts [n] sets, syncs them all, ages them and prunes every stub.
    Future<void> pruneAllStubs(FileCommandQueueStore s, int n) async {
      for (var i = 1; i <= n; i++) {
        final r = (await accFor(s).accept(intentOf('p$i', setIndex: i))).record;
        await s.markSending(r.operationId);
        await s.markResult(r.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      }
      clock.advance(const Duration(days: 8));
      expect(await s.prune(), n);
      expect(await s.listAll(), isEmpty);
    }

    test('layout: store.init, one framed document, writes alternate slots with gen+1',
        () async {
      final s = await open();
      await accFor(s).accept(intentOf('t1', setIndex: 1));
      expect(File('${scope()}/store.init').existsSync(), isTrue);
      final n1 = newestSlot(scope());
      final g1 = slotDoc(scope(), n1)!['gen'] as int;
      await accFor(s).accept(intentOf('t2', setIndex: 2));
      final n2 = newestSlot(scope());
      expect(n2, isNot(n1));
      expect(slotDoc(scope(), n2)!['gen'], g1 + 1);
      final doc = slotDoc(scope(), n2)!;
      expect(doc['format'], 2);
      expect(doc.keys.toSet(), <String>{'format', 'gen', 'seq', 'logicalSets'});
      expect((doc['logicalSets']! as Map).keys.toSet(),
          <String>{'sess-1:ex-squat:1', 'sess-1:ex-squat:2'});
      final text = File('${scope()}/meta.$n2.json').readAsStringSync();
      expect(text.trimRight().split('\n').last, startsWith('#sha256:'));
      expect(Directory(scope()).listSync().any((e) => e.path.endsWith('.tmp')),
          isFalse);
    });

    test('a) after pruning every stub, deleting both slots (store.init stays) fails closed; no sequence reuse, no duplicate APPEND',
        () async {
      var s = await open();
      await pruneAllStubs(s, 2);
      await s.dispose();
      File('${scope()}/meta.a.json').deleteSync();
      File('${scope()}/meta.b.json').deleteSync();
      expect(File('${scope()}/store.init').existsSync(), isTrue);
      final before = treeSnapshot(scope());

      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      expect(s.openReport.recoveryRequiredReason, isNotNull);
      // Sequence reuse (a NEW set would get seq 1 again) is refused ...
      await expectLater(accFor(s).accept(intentOf('new', setIndex: 7)),
          throwsA(isA<QueueRecoveryRequiredException>()));
      // ... and so is a duplicate APPEND for a set that was already synced.
      await expectLater(accFor(s).accept(intentOf('dup', setIndex: 1)),
          throwsA(isA<QueueRecoveryRequiredException>()));
      try {
        expect(await s.prune(), 0);
      } on QueueRecoveryRequiredException {
        // refusing loudly is fine too
      }
      await s.dispose();
      live = null;
      expect(treeSnapshot(scope()), before, reason: 'originals must stay untouched');
      expect(File('${scope()}/meta.a.json').existsSync(), isFalse);
      expect(File('${scope()}/meta.b.json').existsSync(), isFalse);
    });

    test('a) both slots garbage: fail closed, bytes untouched, no .corrupt copies',
        () async {
      var s = await open();
      await pruneAllStubs(s, 1);
      await s.dispose();
      File('${scope()}/meta.a.json').writeAsStringSync('garbage-a');
      File('${scope()}/meta.b.json').writeAsStringSync('garbage-b');
      final before = treeSnapshot(scope());
      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      await expectLater(accFor(s).accept(intentOf('dup', setIndex: 1)),
          throwsA(isA<QueueRecoveryRequiredException>()));
      await s.dispose();
      live = null;
      expect(treeSnapshot(scope()), before);
      expect(Directory(scope()).listSync().any((e) => e.path.contains('.corrupt-')),
          isFalse);
    });

    test('a) one slot is never enough when it is not valid: unchecksummed only -> fail closed, with or without store.init',
        () async {
      var s = await open();
      await s.dispose();
      for (final withInit in <bool>[true, false]) {
        File('${scope()}/meta.a.json')
            .writeAsStringSync(framed(1, <String, int>{key(): 5}, checksum: false));
        if (File('${scope()}/meta.b.json').existsSync()) {
          File('${scope()}/meta.b.json').deleteSync();
        }
        final init = File('${scope()}/store.init');
        if (withInit && !init.existsSync()) init.writeAsStringSync('x\n');
        if (!withInit && init.existsSync()) init.deleteSync();
        s = await open();
        expect(s.openReport.recoveryRequired, isTrue, reason: 'withInit=$withInit');
        await expectLater(accFor(s).accept(intentOf('t1')),
            throwsA(isA<QueueRecoveryRequiredException>()));
        await s.dispose();
      }
    });

    test('b) the valid slot with the highest gen wins over a valid older one', () async {
      var s = await open();
      await s.dispose();
      File('${scope()}/meta.a.json').writeAsStringSync(framed(5, <String, int>{key(): 10}));
      File('${scope()}/meta.b.json').writeAsStringSync(framed(3, <String, int>{key(): 2}));
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await accFor(s).accept(intentOf('t1'))).record.seq, 10);
      // The next write goes to the slot that does NOT hold the highest gen.
      expect(slotDoc(scope(), 'b')!['gen'], 6);
      expect(slotDoc(scope(), 'a')!['gen'], 5);
    });

    test('b) an unchecksummed slot with a HIGHER gen is never selected; the valid older slot wins',
        () async {
      var s = await open();
      await s.dispose();
      File('${scope()}/meta.a.json').writeAsStringSync(framed(2, <String, int>{key(): 3}));
      final bad = framed(99, <String, int>{key(): 5000}, checksum: false);
      File('${scope()}/meta.b.json').writeAsStringSync(bad);
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect(s.openReport.seqFileRepaired, isTrue);
      expect((await accFor(s).accept(intentOf('t1'))).record.seq, 3);
      expect(File('${scope()}/meta.b.json.corrupt-1').readAsStringSync(), bad);
    });

    test('b) a higher-gen slot with a wrong checksum or garbage is never selected',
        () async {
      for (final badText in <String>[
        '${framed(50, <String, int>{key(): 9000}).replaceFirst('9000', '9001')}',
        'not json at all',
        '',
      ]) {
        var s = await open();
        await s.dispose();
        File('${scope()}/meta.a.json').writeAsStringSync(framed(2, <String, int>{key(): 4}));
        File('${scope()}/meta.b.json').writeAsStringSync(badText);
        s = await open();
        expect(s.openReport.recoveryRequired, isFalse, reason: badText);
        expect((await accFor(s).accept(intentOf('t1'))).record.seq, 4, reason: badText);
        await s.dispose();
        // reset for the next iteration
        for (final f in Directory(scope()).listSync().whereType<File>().toList()) {
          if (f.path.contains('meta.')) f.deleteSync();
        }
        for (final f in Directory('${scope()}/records').listSync().whereType<File>().toList()) {
          f.deleteSync();
        }
      }
    });

    test('b) corrupt NEWEST slot after real use: the older slot wins, surviving records raise the counter, nothing is reused',
        () async {
      var s = await open();
      await accFor(s).accept(intentOf('t1', setIndex: 1));
      await accFor(s).accept(intentOf('t2', setIndex: 2));
      await s.dispose();
      File('${scope()}/meta.${newestSlot(scope())}.json').writeAsStringSync('rot');
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      await expectLater(accFor(s).accept(intentOf('dup', setIndex: 2)),
          throwsA(isA<DuplicateLogicalSetException>()));
      expect((await accFor(s).accept(intentOf('t3', setIndex: 3))).record.seq, 3);
    });

    test('c) metadata write fault, then a second fault on cleanup, then restart and an identical retry: same sequence, no duplicate',
        () async {
      final ops = DeleteFaultOps();
      var s = await open(ops: ops);
      await accFor(s).accept(intentOf('t1', setIndex: 1));
      final slotsBefore = <String, String>{
        for (final e in treeSnapshot(scope()).entries)
          if (isMetaPath(e.key)) e.key: e.value,
      };
      ops.armFor(isMetaPath); // temp written, rename "crashes"
      ops.failRecordDeletes = true; // and the rollback cannot delete the record
      await expectLater(accFor(s).accept(intentOf('t2', setIndex: 2)), throwsA(anything));
      expect(ops.failures, 1);
      expect(ops.deleteFailures, greaterThanOrEqualTo(1));
      // A failed write changes nothing: both slots are byte-identical.
      final slotsAfter = <String, String>{
        for (final e in treeSnapshot(scope()).entries)
          if (isMetaPath(e.key)) e.key: e.value,
      };
      expect(slotsAfter, slotsBefore);

      // Restart (ops without faults): temp removed, the residual record of
      // set 2 is re-adopted together with its marker and sequence.
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect(s.openReport.removedTempFiles, greaterThanOrEqualTo(1));
      expect((await s.listAll()).length, 2);
      final retry = await accFor(s).accept(intentOf('t2', setIndex: 2));
      expect(retry.record.seq, 2, reason: 'same sequence as without the faults');
      final sameSet = (await s.listAll())
          .where((r) => r.logicalSetId == 'sess-1:ex-squat:2')
          .toList();
      expect(sameSet.length, 1, reason: 'no duplicate APPEND for the set');
      expect((await accFor(s).accept(intentOf('t3', setIndex: 3))).record.seq, 3);
    });

    test('c) the same double fault, retried in the SAME process: after the next restart the set still has exactly one record',
        () async {
      final ops = DeleteFaultOps();
      var s = await open(ops: ops);
      await accFor(s).accept(intentOf('t1', setIndex: 1));
      ops.armFor(isMetaPath);
      ops.failRecordDeletes = true;
      await expectLater(accFor(s).accept(intentOf('t2', setIndex: 2)), throwsA(anything));
      ops.disarm();
      ops.failRecordDeletes = false;
      final retry = await accFor(s).accept(intentOf('t2', setIndex: 2));
      expect(retry.record.seq, 2);

      s = await open();
      final sameSet = (await s.listAll())
          .where((r) => r.logicalSetId == 'sess-1:ex-squat:2')
          .toList();
      expect(sameSet.length, 1,
          reason: 'a residual record file of the failed attempt must not '
              'survive next to the retried record');
    });

    test('c) a metadata fault during prune keeps the stub; prune works after a restart',
        () async {
      final ops = FaultyFileOps();
      var s = await open(ops: ops);
      final r = (await accFor(s).accept(intentOf('t1'))).record;
      await s.markSending(r.operationId);
      await s.markResult(r.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      ops.armFor(isMetaPath);
      await expectLater(s.prune(), throwsA(anything));
      expect(await s.get(r.operationId), isNotNull);
      ops.disarm();
      s = await open();
      expect(await s.get(r.operationId), isNotNull);
      expect(await s.prune(), 1);
      await expectLater(accFor(s).accept(intentOf('again')),
          throwsA(isA<DuplicateLogicalSetException>()));
    });

    test('a fail-closed store can still send what it already holds', () async {
      var s = await open();
      final rec = (await accFor(s).accept(intentOf('t1'))).record;
      await s.dispose();
      File('${scope()}/meta.a.json').writeAsStringSync('x');
      File('${scope()}/meta.b.json').writeAsStringSync('y');
      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      final rep = await senderFor(s, server, clock).sendNext();
      expect(rep.status, SendStatus.synced);
      expect(server.effects.single.operationId, rec.operationId);
    });

    test('V0-R3-M01: double fault, NO retry, L2 synced, retention passes, prune, restart: a different-intent APPEND of L2 is refused and seq is not reused',
        () async {
      final ops = DeleteFaultOps();
      var s = await open(ops: ops);
      final l1 = (await accFor(s).accept(intentOf('l1', setIndex: 1))).record;
      ops.armFor(isMetaPath);
      ops.failRecordDeletes = true;
      await expectLater(accFor(s).accept(intentOf('l2', setIndex: 2)), throwsA(anything));
      ops.disarm();
      ops.failRecordDeletes = false;

      // The surviving record is visible and gets sent and acknowledged.
      final sender = senderFor(s, server, clock);
      final reports = await sender.sendAvailable();
      expect(reports.where((r) => r.status == SendStatus.synced).length, 2);
      expect(server.effects.length, 2);
      final l2 = (await s.listAll())
          .singleWhere((r) => r.logicalSetId == 'sess-1:ex-squat:2');
      expect(l2.state, CommandState.synced);
      expect(l2.seq, 2);

      clock.advance(const Duration(days: 8));
      expect(await s.prune(), 2);
      expect(await s.listAll(), isEmpty);

      s = await open(); // restart
      expect(s.openReport.recoveryRequired, isFalse);
      expect(await s.listAll(), isEmpty);
      await expectLater(accFor(s).accept(intentOf('l2-other-intent', setIndex: 2)),
          throwsA(isA<DuplicateLogicalSetException>()));
      await expectLater(accFor(s).accept(intentOf('l1-other-intent', setIndex: 1)),
          throwsA(isA<DuplicateLogicalSetException>()));
      final l3 = (await accFor(s).accept(intentOf('l3', setIndex: 3))).record;
      expect(l3.seq, 3, reason: 'sequence numbers of L1 and L2 must not be reused');
      expect(l1.seq, 1);
    });

    test('V0-R3-M01 crash variant: restart before any further metadata write; seed recreates the marker from the loaded record',
        () async {
      final ops = DeleteFaultOps();
      var s = await open(ops: ops);
      await accFor(s).accept(intentOf('l1', setIndex: 1));
      ops.armFor(isMetaPath);
      ops.failRecordDeletes = true;
      await expectLater(accFor(s).accept(intentOf('l2', setIndex: 2)), throwsA(anything));
      // The slot on disk does not know L2 yet.
      expect(((slotDoc(scope(), newestSlot(scope()))!['logicalSets']) as Map).keys,
          isNot(contains('sess-1:ex-squat:2')));

      s = await open(); // process died here
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await s.listAll()).length, 2);
      await expectLater(accFor(s).accept(intentOf('l2-other-intent', setIndex: 2)),
          throwsA(isA<DuplicateLogicalSetException>()));
      expect((await accFor(s).accept(intentOf('l3', setIndex: 3))).record.seq, 3);
      // The recreated marker reached disk with that write.
      expect(((slotDoc(scope(), newestSlot(scope()))!['logicalSets']) as Map).keys,
          contains('sess-1:ex-squat:2'));
    });
  });
}
