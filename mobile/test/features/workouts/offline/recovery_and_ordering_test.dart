// Metadata redundancy (checksum + backup twin, fail closed) and the
// proof / NOT_WRITER ordering contract of the sender.
import 'dart:convert';
import 'dart:io';

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

  group('M03 checksummed metadata with a backup twin', () {
    Future<void> seedPrunedStub(FileCommandQueueStore s) async {
      final a = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
      await s.markSending(a.operationId);
      await s.markResult(a.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s.prune(), 1);
    }

    test('files are written with a checksum line and a backup twin', () async {
      final s = await open();
      await accFor(s).accept(intentOf('t'));
      for (final n in <String>['seq.json', 'logical_sets.json']) {
        final text = File('${scope()}/$n').readAsStringSync();
        expect(text.trimRight().split('\n').last, startsWith('#sha256:'));
        expect(File('${scope()}/$n.bak').readAsStringSync(), text);
      }
    });

    test('corruption AFTER pruning: the backup restores, no duplicate APPEND and no seq reuse',
        () async {
      var s = await open();
      await seedPrunedStub(s);
      await s.dispose();
      File('${scope()}/seq.json').writeAsStringSync('garbage');
      File('${scope()}/logical_sets.json').writeAsStringSync('');

      s = await open();
      expect(s.openReport.seqFileRepaired, isTrue);
      expect(s.openReport.markersFileRepaired, isTrue);
      expect(s.openReport.recoveryRequired, isFalse);
      // Evidence preserved.
      final names = Directory(scope()).listSync().map((e) => e.path).toList();
      expect(names.where((p) => p.contains('seq.json.corrupt-')).length, 1);
      expect(names.where((p) => p.contains('logical_sets.json.corrupt-')).length, 1);
      // The pruned set cannot get a second APPEND.
      await expectLater(accFor(s).accept(intentOf('again', setIndex: 1)),
          throwsA(isA<DuplicateLogicalSetException>()));
      // The next sequence is not 1 again.
      final next = (await accFor(s).accept(intentOf('t2', setIndex: 2))).record;
      expect(next.seq, 2);
    });

    test('a silent bit flip that keeps the JSON valid is caught by the checksum',
        () async {
      var s = await open();
      await seedPrunedStub(s);
      await s.dispose();
      final f = File('${scope()}/logical_sets.json');
      final text = f.readAsStringSync();
      expect(text.contains('t1') || text.contains('sess-1'), isTrue);
      f.writeAsStringSync(text.replaceFirst('sess-1', 'sess-9')); // still valid JSON
      s = await open();
      expect(s.openReport.markersFileRepaired, isTrue);
      await expectLater(accFor(s).accept(intentOf('again', setIndex: 1)),
          throwsA(isA<DuplicateLogicalSetException>()));
    });

    test('a format-1 file without a checksum still loads and gets its backup', () async {
      var s = await open();
      await accFor(s).accept(intentOf('t1', setIndex: 1));
      await s.dispose();
      final f = File('${scope()}/seq.json');
      final body = f.readAsStringSync().split('\n').first;
      f.writeAsStringSync(body); // legacy: plain JSON
      File('${scope()}/seq.json.bak').deleteSync();
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect(File('${scope()}/seq.json.bak').existsSync(), isTrue);
      expect((await accFor(s).accept(intentOf('t2', setIndex: 2))).record.seq, 2);
    });

    test('a failed primary write after the backup write never lets a seq be reused',
        () async {
      final ops = FaultyFileOps();
      var s = await open(ops: ops);
      ops.armFor((p) => p.endsWith('/seq.json'), m: FaultMode.beforeTempWrite);
      await expectLater(accFor(s).accept(intentOf('t1', setIndex: 1)), throwsA(anything));
      ops.disarm();
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      final r = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
      expect(r.seq, greaterThanOrEqualTo(1));
      final r2 = (await accFor(s).accept(intentOf('t2', setIndex: 2))).record;
      expect(r2.seq, greaterThan(r.seq));
    });

    test('seq.json twin: a failed primary write restores the previous backup, so the failed set can be saved after a restart',
        () async {
      final ops = FaultyFileOps();
      var s = await open(ops: ops);
      final first = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
      final before = File('${scope()}/seq.json').readAsStringSync();
      ops.armFor((p) => p.endsWith('/seq.json'), m: FaultMode.beforeTempWrite);
      await expectLater(accFor(s).accept(intentOf('t2', setIndex: 2)), throwsA(anything));
      ops.disarm();
      // Backup rolled back to the previous state: identical to the primary.
      expect(File('${scope()}/seq.json.bak').readAsStringSync(), before);
      expect(File('${scope()}/seq.json').readAsStringSync(), before);
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await s.listAll()).single.operationId, first.operationId);
      final second = (await accFor(s).accept(intentOf('t2', setIndex: 2))).record;
      expect(second.seq, 2); // no phantom advance, no reuse of seq 1
    });

    test('seq.json twin on the very first write: no backup is left behind', () async {
      final ops = FaultyFileOps();
      var s = await open(ops: ops);
      ops.armFor((p) => p.endsWith('/seq.json'), m: FaultMode.beforeTempWrite);
      await expectLater(accFor(s).accept(intentOf('t1')), throwsA(anything));
      ops.disarm();
      expect(File('${scope()}/seq.json.bak').existsSync(), isFalse);
      s = await open();
      expect((await accFor(s).accept(intentOf('t1'))).record.seq, 1);
    });

    for (final name in <String>['seq.json', 'logical_sets.json']) {
      test('$name and its backup both corrupt: fail closed, originals untouched',
          () async {
        var s = await open();
        final live1 = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
        await s.dispose();
        File('${scope()}/$name').writeAsStringSync('corrupt-primary');
        File('${scope()}/$name.bak').writeAsStringSync('corrupt-backup');
        final before = _snapshot(scope());

        s = await open();
        expect(s.openReport.recoveryRequired, isTrue);
        expect(s.openReport.recoveryRequiredReason, contains(name));
        await expectLater(accFor(s).accept(intentOf('new', setIndex: 5)),
            throwsA(isA<QueueRecoveryRequiredException>()));
        clock.advance(const Duration(days: 30));
        // Pruning is refused as well: nothing is removed.
        try {
          expect(await s.prune(), 0);
        } on QueueRecoveryRequiredException {
          // also acceptable: refused loudly
        }
        // Existing records stay readable.
        expect((await s.get(live1.operationId)), isNotNull);
        // Nothing was rewritten or removed, no .corrupt copy was made.
        await s.dispose();
        live = null;
        expect(_snapshot(scope()), before);
        expect(File('${scope()}/$name').readAsStringSync(), 'corrupt-primary');
        expect(File('${scope()}/$name.bak').readAsStringSync(), 'corrupt-backup');
      });
    }

    test('corrupt primary and no backup at all: fail closed', () async {
      var s = await open();
      await accFor(s).accept(intentOf('t1'));
      await s.dispose();
      File('${scope()}/seq.json').writeAsStringSync('x');
      File('${scope()}/seq.json.bak').deleteSync();
      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      await expectLater(accFor(s).accept(intentOf('t2', setIndex: 2)),
          throwsA(isA<QueueRecoveryRequiredException>()));
      expect(File('${scope()}/seq.json').readAsStringSync(), 'x');
    });

    test('a fail-closed store can still send what it already holds', () async {
      var s = await open();
      final rec = (await accFor(s).accept(intentOf('t1'))).record;
      await s.dispose();
      File('${scope()}/seq.json').writeAsStringSync('x');
      File('${scope()}/seq.json.bak').writeAsStringSync('y');
      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      final rep = await senderFor(s, server, clock).sendNext();
      expect(rep.status, SendStatus.synced);
      expect(server.effects.single.operationId, rec.operationId);
    });
  });
}


Map<String, String> _snapshot(String scopeDir) => <String, String>{
      for (final e in Directory(scopeDir).listSync(recursive: true))
        if (e is File) e.path: base64.encode(e.readAsBytesSync()),
    };
