// Review-hardening behaviour: writer proof, per-session integrity block,
// store errors in the sender, unreadable records in status, open report,
// single-instance guard, unique temp files, builder constraints, stuck flag.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/in_memory_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/providers.dart';
import 'package:fitness_app/features/workouts/offline/queue_file_ops.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:fitness_app/features/workouts/offline/status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

Matcher get _canonErr => throwsA(isA<CanonicalizationException>());

String _hexOf(String s) => utf8
    .encode(s)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// Flips one payload byte on disk, keeping the stored hash (bit rot).
Future<void> _tamper(Directory root, String operationId) async {
  final file = File(
      '${rootPathOf(root)}/${queueScopeDirName(kUid)}/records/${_hexOf(operationId)}.json');
  final doc = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final rec = Map<String, Object?>.from(doc['record']! as Map);
  final bytes = base64.decode(rec['canonicalBytes']! as String);
  bytes[3] ^= 0x01;
  rec['canonicalBytes'] = base64.encode(bytes);
  doc['record'] = rec;
  await file.writeAsString(jsonEncode(doc));
}

/// Transport that runs a hook after the SENDING commit but before delegating.
class _HookTransport implements CommandTransport {
  _HookTransport(this.inner, this.beforeSend);
  final FakeServer inner;
  final void Function() beforeSend;
  @override
  Future<TransportAnswer> send(CommandEnvelope e) {
    beforeSend();
    return inner.send(e);
  }
}

/// Records the temp file names the real ops create, by listing the directory
/// from inside a delayed rename hook is not possible, so it compares the
/// directory content right after a write that is made to fail on rename.
class _SpyOps implements QueueFileOps {
  _SpyOps(this.names);
  final Set<String> names;
  @override
  Future<void> writeAtomic(String path, Uint8List bytes) async {
    // Make the target a directory so the rename fails and the temp file stays.
    final blocker = Directory('$path.block${names.length}');
    await blocker.create();
    final target = blocker.path;
    try {
      await const IoQueueFileOps().writeAtomic(target, bytes);
    } on FileSystemException {
      // expected
    }
    final parent = File(path).parent;
    for (final e in parent.listSync()) {
      if (e is File && e.path.endsWith('.tmp')) names.add(e.path);
    }
  }

  @override
  Future<void> ensureDir(String path) async {}
  @override
  Future<Uint8List?> read(String path) async => null;
  @override
  Future<List<String>> listFileNames(String dir) async => const <String>[];
  @override
  Future<void> delete(String path) async {}
}

class _EnsureDirFails extends FaultyFileOps {
  @override
  Future<void> ensureDir(String path) => throw const FileSystemException('disk gone');
}

void main() {
  late Directory dir;
  late TestClock clock;
  late IdMinter minter;
  late FakeServer server;
  final live = <FileCommandQueueStore>[];

  Future<FileCommandQueueStore> open({QueueFileOps ops = const IoQueueFileOps()}) async {
    for (final s in live) {
      await s.dispose();
    }
    live.clear();
    final s = await FileCommandQueueStore.open(
        uid: kUid, rootDir: rootPathOf(dir), ops: ops, nowMs: clock.nowMs);
    live.add(s);
    return s;
  }

  setUp(() async {
    dir = await makeTempRoot();
    clock = TestClock();
    minter = IdMinter();
    server = FakeServer();
  });
  tearDown(() async {
    for (final s in live) {
      await s.dispose();
    }
    live.clear();
    await removeTempRoot(dir);
  });

  CompleteSetAcceptor accFor(CommandQueueStore s) =>
      acceptorFor(s, clock, minter: minter);

  group('M1 writer proof', () {
    for (final kind in <String, Future<String?> Function(String, String)>{
      'null proof': (u, s) async => null,
      'empty proof': (u, s) async => '',
      'throwing provider': (u, s) async => throw StateError('keystore'),
    }.entries) {
      test('${kind.key}: nothing sent, record untouched, session held',
          () async {
        final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
        final rec = (await accFor(store).accept(intentOf('t'))).record;
        final sender = senderFor(store, server, clock, proof: kind.value);
        final rep = await sender.sendNext();
        expect(rep.status, SendStatus.proofUnavailable);
        expect(rep.operationId, rec.operationId);
        expect(rep.nextAttemptAt, isNotNull);
        expect(server.received, isEmpty);
        final r = (await store.get(rec.operationId))!;
        expect(r.state, CommandState.accepted);
        expect(r.maybeSent, isFalse);
        expect(r.attempts, 0);
        // The session is on hold: the next call does not even ask again.
        expect((await sender.sendNext()).status, SendStatus.sessionOnHold);
        await store.dispose();
      });
    }

    test('after the token appears and the hold is reset the record is sent',
        () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      final rec = (await accFor(store).accept(intentOf('t'))).record;
      String? token;
      final sender =
          senderFor(store, server, clock, proof: (u, s) async => token);
      expect((await sender.sendNext()).status, SendStatus.proofUnavailable);
      token = 'tok';
      sender.resetBackoff();
      expect((await sender.sendNext()).status, SendStatus.synced);
      expect(server.received.single.writerProof, 'tok');
      expect(server.received.single.operationId, rec.operationId);
      await store.dispose();
    });

    test('without a provider the sender still sends (no writer credential)',
        () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      await accFor(store).accept(intentOf('t'));
      expect((await senderFor(store, server, clock).sendNext()).status,
          SendStatus.synced);
      expect(server.received.single.writerProof, isNull);
      await store.dispose();
    });
  });

  group('M2 integrity failure blocks its session only', () {
    test('higher-seq records of the same session are not sent; other sessions are',
        () async {
      final s1 = await open();
      final acc = accFor(s1);
      final a1 = (await acc.accept(intentOf('a1', sessionId: 'sess-A', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      final a2 = (await acc.accept(intentOf('a2', sessionId: 'sess-A', setIndex: 2))).record;
      clock.advance(const Duration(seconds: 1));
      final b1 = (await acc.accept(intentOf('b1', sessionId: 'sess-B', setIndex: 1))).record;
      await s1.dispose();
      await _tamper(dir, a1.operationId);

      final s2 = await open();
      final sender = senderFor(s2, server, clock);
      final reports = await sender.sendAvailable();
      expect(reports.first.status, SendStatus.synced);
      expect(reports.first.operationId, b1.operationId);
      expect(reports.last.status, SendStatus.integrityFailure);
      expect(reports.last.operationId, a1.operationId);
      expect(server.effects.map((e) => e.operationId).toList(), <String>[b1.operationId]);
      for (final r in <CommandRecord>[a1, a2]) {
        final cur = (await s2.get(r.operationId))!;
        expect(cur.state, CommandState.accepted);
        expect(cur.maybeSent, isFalse);
      }
    });

    test('only corrupt records: integrityFailure, nothing sent', () async {
      final s1 = await open();
      final a1 = (await accFor(s1).accept(intentOf('a1'))).record;
      await s1.dispose();
      await _tamper(dir, a1.operationId);
      final s2 = await open();
      final rep = await senderFor(s2, server, clock).sendNext();
      expect(rep.status, SendStatus.integrityFailure);
      expect(server.received, isEmpty);
    });
  });

  group('M3 store errors never throw out of the sender', () {
    test('a failing SENDING commit: storeError, record ACCEPTED, transport uncalled',
        () async {
      final ops = FaultyFileOps();
      final s = await open(ops: ops);
      final rec = (await accFor(s).accept(intentOf('t'))).record;
      ops.armFor(isRecordPath);
      final sender = senderFor(s, server, clock);
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.storeError);
      expect(rep.code, isNotNull);
      expect(server.received, isEmpty);
      expect((await s.get(rec.operationId))!.state, CommandState.accepted);
      ops.disarm();
      expect((await sender.sendNext()).status, SendStatus.synced);
    });

    test('a failing result commit after the server applied: storeError, then the stale SENDING record is recovered and resent with the same bytes',
        () async {
      final ops = FaultyFileOps();
      final s = await open(ops: ops);
      final rec = (await accFor(s).accept(intentOf('t'))).record;
      final sender = senderFor(
          s, _HookTransport(server, () => ops.armFor(isRecordPath)), clock);
      final first = await sender.sendNext();
      expect(first.status, SendStatus.storeError);
      expect(server.effects.length, 1); // the server did apply it
      expect((await s.get(rec.operationId))!.state, CommandState.sending);

      ops.disarm();
      final sender2 = senderFor(s, server, clock);
      final second = await sender2.sendNext();
      expect(second.status, SendStatus.synced);
      expect(second.code, 'ALREADY_COMMITTED');
      expect(server.effects.length, 1);
      expect(server.received.last.payloadBytes, rec.canonicalBytes);
      expect(server.received.last.operationId, rec.operationId);
      final end = (await s.get(rec.operationId))!;
      expect(end.state, CommandState.synced);
      expect(end.attempts, 2);
    });

    test('the busy flag is released after a store error', () async {
      final ops = FaultyFileOps();
      final s = await open(ops: ops);
      await accFor(s).accept(intentOf('t'));
      ops.armFor(isRecordPath);
      final sender = senderFor(s, server, clock);
      expect((await sender.sendNext()).status, SendStatus.storeError);
      expect((await sender.sendNext()).status, SendStatus.storeError);
      ops.disarm();
      expect((await sender.sendNext()).status, SendStatus.synced);
    });
  });

  group('m5 retry classes and stuck flag', () {
    test('stuck fires at the 10th unanswered attempt, not before', () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      await accFor(store).accept(intentOf('t'));
      final sender = senderFor(store, server, clock);
      final stuck = <bool>[];
      for (var i = 0; i < 11; i++) {
        server.faults.add(Fault.throwWithoutApplying);
        sender.resetBackoff();
        final rep = await sender.sendNext();
        expect(rep.status, SendStatus.retryLater);
        stuck.add(rep.stuck);
      }
      expect(stuck.take(9).any((e) => e), isFalse);
      expect(stuck[9], isTrue);
      expect(stuck[10], isTrue);
      // Informational only: the record is still resendable.
      final r = (await store.listPending()).single;
      expect(r.state, CommandState.unknownEffect);
      sender.resetBackoff();
      expect((await sender.sendNext()).status, SendStatus.synced);
      await store.dispose();
    });

    test('the threshold is configurable', () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      await accFor(store).accept(intentOf('t'));
      final sender = CommandSender(
        store: store,
        transport: server,
        deviceInstallId: kDevice,
        clientBuild: 'b',
        stuckAttemptThreshold: 2,
        now: clock.now,
      );
      server.faults.addAll(<Fault>[Fault.throwWithoutApplying, Fault.throwWithoutApplying]);
      expect((await sender.sendNext()).stuck, isFalse);
      sender.resetBackoff();
      expect((await sender.sendNext()).stuck, isTrue);
      await store.dispose();
    });

    test('UNAVAILABLE stays UNKNOWN_EFFECT (T10) while FENCE_SHARD_FULL returns to ACCEPTED (T11)',
        () async {
      final store = InMemoryCommandQueueStore(uid: kUid, nowMs: clock.nowMs);
      final a = (await accFor(store).accept(intentOf('a', sessionId: 'A'))).record;
      final b = (await accFor(store).accept(intentOf('b', sessionId: 'B'))).record;
      server.scriptedCodes.addAll(<String>['UNAVAILABLE', 'FENCE_SHARD_FULL']);
      final sender = senderFor(store, server, clock);
      await sender.sendNext();
      await sender.sendNext();
      expect((await store.get(a.operationId))!.state, CommandState.unknownEffect);
      expect((await store.get(b.operationId))!.state, CommandState.accepted);
      await store.dispose();
    });
  });

  group('M4 unreadable record files and the open report', () {
    Future<void> corruptOneRecord(String operationId) => File(
            '${rootPathOf(dir)}/${queueScopeDirName(kUid)}/records/${_hexOf(operationId)}.json')
        .writeAsString('{garbage');

    test('an unreadable record file makes every session "could not sync" and never fully synced',
        () async {
      final s1 = await open();
      final acc = accFor(s1);
      final bad = (await acc.accept(intentOf('bad', sessionId: 'A'))).record;
      final ok = (await acc.accept(intentOf('ok', sessionId: 'B'))).record;
      await s1.markSending(ok.operationId);
      await s1.markResult(ok.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      await s1.dispose();
      await corruptOneRecord(bad.operationId);

      final s2 = await open();
      expect(s2.unreadableRecordCount, 1);
      final snap = await StoreSyncStatusSource(s2).snapshot();
      expect(snap.couldNotSync, 1);
      expect(snap.isFullySynced, isFalse);
      expect(snap.forSession('B').synced, 1);
      expect(snap.forSession('B').couldNotSync, 1);
      expect(snap.forSession('B').isFullySynced, isFalse);
      expect(snap.forSession('A').couldNotSync, 1); // unknown session: conservative
      expect(snap.forSession('never-heard-of').isFullySynced, isFalse);
      expect(File('${rootPathOf(dir)}/${queueScopeDirName(kUid)}/records/${_hexOf(bad.operationId)}.json')
          .existsSync(), isTrue);
    });

    test('a clean store reports fully synced; an in-memory store has no unreadable files',
        () async {
      final s = await open();
      final snap = await StoreSyncStatusSource(s).snapshot();
      expect(snap.isFullySynced, isTrue);
      final mem = InMemoryCommandQueueStore(uid: kUid);
      expect((await StoreSyncStatusSource(mem).snapshot()).isFullySynced, isTrue);
      await mem.dispose();
    });

    test('the open report is exposed by a provider (null for the in-memory fake)',
        () async {
      final s1 = await open();
      final bad = (await accFor(s1).accept(intentOf('bad'))).record;
      await s1.dispose();
      await corruptOneRecord(bad.operationId);
      final s2 = await open();

      final c1 = ProviderContainer(
          overrides: [offlineCommandQueueStoreProvider.overrideWithValue(s2)]);
      addTearDown(c1.dispose);
      final report = c1.read(offlineCommandQueueOpenReportProvider);
      expect(report, isNotNull);
      expect(report!.unreadableFiles.length, 1);

      final mem = InMemoryCommandQueueStore(uid: kUid);
      final c2 = ProviderContainer(
          overrides: [offlineCommandQueueStoreProvider.overrideWithValue(mem)]);
      addTearDown(c2.dispose);
      expect(c2.read(offlineCommandQueueOpenReportProvider), isNull);
      await mem.dispose();
    });
  });

  group('m2 repaired files in the open report', () {
    test('clean open: nothing repaired', () async {
      final s1 = await open();
      await accFor(s1).accept(intentOf('t'));
      final s2 = await open();
      expect(s2.openReport.seqFileRepaired, isFalse);
      expect(s2.openReport.markersFileRepaired, isFalse);
    });

    test('corrupt seq.json is reported and counters stay above surviving seqs',
        () async {
      final s1 = await open();
      await accFor(s1).accept(intentOf('t1', setIndex: 1));
      await accFor(s1).accept(intentOf('t2', setIndex: 2));
      await File('${rootPathOf(dir)}/${queueScopeDirName(kUid)}/seq.json')
          .writeAsString('][');
      final s2 = await open();
      expect(s2.openReport.seqFileRepaired, isTrue);
      expect(s2.openReport.markersFileRepaired, isFalse);
      expect((await accFor(s2).accept(intentOf('t3', setIndex: 3))).record.seq, 3);
    });

    test('corrupt logical_sets.json is reported and rewritten readable', () async {
      final s1 = await open();
      await accFor(s1).accept(intentOf('t1'));
      final f = File('${rootPathOf(dir)}/${queueScopeDirName(kUid)}/logical_sets.json');
      await f.writeAsString('nope');
      final s2 = await open();
      expect(s2.openReport.markersFileRepaired, isTrue);
      final s3 = await open();
      expect(s3.openReport.markersFileRepaired, isFalse); // repaired on disk
    });
  });

  group('m3 single instance and unique temp files', () {
    test('a second open of the same scope throws StateError until the first is disposed',
        () async {
      final s1 = await open();
      await expectLater(
          FileCommandQueueStore.open(uid: kUid, rootDir: rootPathOf(dir)),
          throwsA(isA<StateError>()));
      // The first instance is unaffected.
      expect((await accFor(s1).accept(intentOf('t'))).created, isTrue);
      await s1.dispose();
      live.clear();
      final s2 = await FileCommandQueueStore.open(
          uid: kUid, rootDir: rootPathOf(dir), nowMs: clock.nowMs);
      live.add(s2);
      expect((await s2.listAll()).length, 1);
    });

    test('another uid or another root may be open at the same time', () async {
      final s1 = await open();
      final other = await FileCommandQueueStore.open(
          uid: kOtherUid, rootDir: rootPathOf(dir));
      final dir2 = await makeTempRoot();
      final sameUidOtherRoot =
          await FileCommandQueueStore.open(uid: kUid, rootDir: rootPathOf(dir2));
      expect(s1.uid, isNot(other.uid));
      await other.dispose();
      await sameUidOtherRoot.dispose();
      await removeTempRoot(dir2);
    });

    test('a failed open releases the scope so a later open works', () async {
      await expectLater(
          FileCommandQueueStore.open(
              uid: kUid, rootDir: rootPathOf(dir), ops: _EnsureDirFails()),
          throwsA(isA<FileSystemException>()));
      final s = await open();
      expect(await s.listAll(), isEmpty);
    });

    test('concurrent atomic writes to one path never mix bytes (unique temp names)',
        () async {
      const ops = IoQueueFileOps();
      final path = '${rootPathOf(dir)}/shared.json';
      final payloads = <Uint8List>[
        for (var i = 0; i < 8; i++)
          Uint8List.fromList(utf8.encode('{"writer":$i,"pad":"${'x' * (5000 + i)}"}')),
      ];
      final errors = <Object>[];
      await Future.wait(<Future<void>>[
        for (final p in payloads)
          ops.writeAtomic(path, p).catchError((Object e) {
            errors.add(e); // Windows may refuse a rename while another is open
          }),
      ]);
      // A refused rename is a FileSystemException, never a data problem, and at
      // least one writer wins.
      expect(errors.every((e) => e is FileSystemException), isTrue);
      expect(errors.length, lessThan(payloads.length));
      final result = await ops.read(path);
      expect(payloads.any((p) => _same(p, result!)), isTrue,
          reason: 'file must equal exactly one complete payload');
    });

    test('every write uses its own temp file name', () async {
      final seen = <String>{};
      final ops = _SpyOps(seen);
      final path = '${rootPathOf(dir)}/spy.json';
      for (var i = 0; i < 5; i++) {
        await ops.writeAtomic(path, Uint8List.fromList(<int>[i]));
      }
      expect(seen.length, 5);
    });
  });

  group('m4 builder mirrors the server constraints', () {
    Map<String, Object?> build({
      String? operationId,
      String uid = kUid,
      String sessionId = 'sess-1',
      String device = kDevice,
      int generation = 1,
      int epoch = 0,
      int seq = 1,
      List<String> deps = const <String>[],
      String exerciseId = 'ex-1',
      int setIndex = 1,
      Map<String, Object?>? init,
      Map<String, Object?>? body,
    }) =>
        buildCompleteSetPayload(
          operationId: operationId ?? 'x' * 30,
          uid: uid,
          sessionId: sessionId,
          originDeviceInstallId: device,
          sessionGeneration: generation,
          acceptedEpoch: epoch,
          seq: seq,
          dependsOn: deps,
          exerciseId: exerciseId,
          setIndex: setIndex,
          sessionInit: init,
          body: body ?? setBody(setIndex),
        );

    Map<String, Object?> initOf({Object? title = 'default', Object? day, Object? at = 5}) =>
        <String, Object?>{'titleKey': title, 'dayId': day, 'startedAtClientMs': at};

    test('operationId must be exactly 30 characters of the id alphabet', () {
      expect(build(operationId: 'a' * 30), isNotEmpty);
      expect(() => build(operationId: 'a' * 29), _canonErr);
      expect(() => build(operationId: 'a' * 31), _canonErr);
      expect(() => build(operationId: '${'a' * 29}!'), _canonErr);
      expect(() => build(operationId: '${'a' * 29}é'), _canonErr);
    });

    test('uid length 1..128', () {
      expect(build(uid: 'u' * 128), isNotEmpty);
      expect(() => build(uid: 'u' * 129), _canonErr);
      expect(() => build(uid: ''), _canonErr);
    });

    test('session, exercise and device ids use the 1..128 id alphabet', () {
      for (final bad in <String>['', 'has space', 'a' * 129, 'a:b', 'a/b']) {
        expect(() => build(sessionId: bad), _canonErr, reason: 'session "$bad"');
        expect(() => build(exerciseId: bad), _canonErr, reason: 'exercise "$bad"');
        expect(() => build(device: bad), _canonErr, reason: 'device "$bad"');
      }
      expect(build(sessionId: 'a' * 128, exerciseId: 'b' * 128, device: 'c' * 128),
          isNotEmpty);
    });

    test('reserved ids matching ^__.*__ (whole id) are rejected like the server does', () {
      expect(() => build(sessionId: '__proto__'), _canonErr);
      expect(() => build(exerciseId: '__a__'), _canonErr);
      expect(build(sessionId: '__a', exerciseId: 'a__'), isNotEmpty);
    });

    test('generation 1..1000000, epoch 0..1000000, seq 1..2147483647', () {
      expect(build(generation: 1000000), isNotEmpty);
      expect(() => build(generation: 1000001), _canonErr);
      expect(() => build(generation: 0), _canonErr);
      expect(build(epoch: 1000000), isNotEmpty);
      expect(() => build(epoch: 1000001), _canonErr);
      expect(() => build(epoch: -1), _canonErr);
      expect(build(seq: 2147483647), isNotEmpty);
      expect(() => build(seq: 2147483648), _canonErr);
      expect(() => build(seq: 0), _canonErr);
    });

    test('dependsOn: 30 char ids, no self reference, no duplicates, at most 3', () {
      final a = 'a' * 30, b = 'b' * 30, c = 'c' * 30, d = 'd' * 30;
      expect(build(deps: [b, a])['dependsOn'], <String>[a, b]);
      expect(build(deps: [a, b, c]), isNotEmpty);
      expect(() => build(deps: [a, b, c, d]), _canonErr);
      expect(() => build(deps: [a, a]), _canonErr);
      expect(() => build(operationId: a, deps: [a]), _canonErr);
      expect(() => build(deps: ['short']), _canonErr);
    });

    test('sessionInit.titleKey: default, day:<id> or plan:<id> only', () {
      expect(build(init: initOf(title: 'default')), isNotEmpty);
      expect(build(init: initOf(title: 'day:d_1')), isNotEmpty);
      expect(build(init: initOf(title: 'plan:${'p' * 64}')), isNotEmpty);
      for (final bad in <Object?>[
        'Default', 'day:', 'plan:', 'day:${'d' * 65}', 'week:1', 'day: x', '', 5, null,
      ]) {
        expect(() => build(init: initOf(title: bad)), _canonErr,
            reason: 'title $bad');
      }
    });

    test('sessionInit.dayId and startedAtClientMs', () {
      expect(build(init: initOf(day: 'day_1')), isNotEmpty);
      expect(build(init: initOf(day: null)), isNotEmpty);
      expect(() => build(init: initOf(day: 'bad id')), _canonErr);
      expect(() => build(init: initOf(day: 'a' * 129)), _canonErr);
      expect(() => build(init: initOf(day: 5)), _canonErr);
      expect(build(init: initOf(at: 0)), isNotEmpty);
      expect(build(init: initOf(at: kMaxSafeInteger)), isNotEmpty);
      expect(() => build(init: initOf(at: -1)), _canonErr);
      expect(() => build(init: initOf(at: kMaxSafeInteger + 1)), _canonErr);
      expect(() => build(init: initOf(at: 1.5)), _canonErr);
    });

    test('body.source pattern and performedAtClientMs range', () {
      for (final ok in <String>['manual', 'a', 'A_b-9', 's' * 32]) {
        expect(build(body: {...setBody(1), 'source': ok}), isNotEmpty);
      }
      for (final bad in <Object?>['', 's' * 33, 'has space', 'a.b', 'é', null, 7]) {
        expect(() => build(body: {...setBody(1), 'source': bad}), _canonErr,
            reason: 'source $bad');
      }
      expect(build(body: {...setBody(1), 'performedAtClientMs': kMaxSafeInteger}),
          isNotEmpty);
      expect(
          () => build(body: {...setBody(1), 'performedAtClientMs': kMaxSafeInteger + 1}),
          _canonErr);
      expect(() => build(body: {...setBody(1), 'performedAtClientMs': -1}), _canonErr);
    });

    test('body numeric limits and the setId/setIndex pairing', () {
      expect(() => build(body: {...setBody(1), 'actualReps': 1001}), _canonErr);
      expect(() => build(body: {...setBody(1), 'targetReps': -1}), _canonErr);
      expect(() => build(body: {...setBody(1), 'loadGrams': 1000001}), _canonErr);
      expect(() => build(setIndex: 2, body: setBody(1)), _canonErr);
      expect(() => build(setIndex: 1001, body: setBody(1001)), _canonErr);
    });
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
