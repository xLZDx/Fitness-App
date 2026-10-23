// Crash, restart, atomic-write and uid-scope behaviour of the file store.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/queue_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

void main() {
  late Directory dir;
  late TestClock clock;
  late String root;
  final opened = <FileCommandQueueStore>[];
  final live = <String, FileCommandQueueStore>{};

  Future<FileCommandQueueStore> open({
    String uid = kUid,
    QueueFileOps ops = const IoQueueFileOps(),
  }) async {
    // A "restart": the previous instance of this uid is gone (the store allows
    // one live instance per scope).
    await live.remove(uid)?.dispose();
    final s = await FileCommandQueueStore.open(
        uid: uid, rootDir: root, ops: ops, nowMs: clock.nowMs);
    live[uid] = s;
    opened.add(s);
    return s;
  }

  // One minter per test, like a CSPRNG: ids never repeat across store reopens.
  late IdMinter minter;
  CompleteSetAcceptor accFor(CommandQueueStore s) =>
      acceptorFor(s, clock, minter: minter);

  setUp(() async {
    dir = await makeTempRoot();
    root = rootPathOf(dir);
    clock = TestClock();
    minter = IdMinter();
  });

  tearDown(() async {
    for (final s in opened) {
      await s.dispose();
    }
    opened.clear();
    live.clear();
    await removeTempRoot(dir);
  });

  group('crash before / after the local commit', () {
    test('crash before the record is durable: nothing stored, nothing sendable',
        () async {
      final ops = FaultyFileOps()..armFor((p) => isRecordPath(p));
      final s1 = await open(ops: ops);
      await expectLater(accFor(s1).accept(intentOf('tap-1')),
          throwsA(isA<FileSystemException>()));
      expect(ops.failures, 1);
      // The in-memory view of the live instance shows nothing either.
      expect(await s1.listAll(), isEmpty);
      expect(await s1.listPending(), isEmpty);

      // "Process restart": a new store over the same directory.
      final s2 = await open();
      expect(await s2.listAll(), isEmpty);
      expect(await s2.listPending(), isEmpty);
      expect(s2.openReport.loaded, 0);
      expect(s2.openReport.unreadableFiles, isEmpty);
      expect(s2.openReport.removedTempFiles, 1); // the half-written temp
      // Nothing is on disk as a record file.
      final names = await const IoQueueFileOps()
          .listFileNames('${rootOfScope(root, kUid)}/records');
      expect(names.where((n) => n.endsWith('.json')), isEmpty);
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test('the retry of the same tap after a failed commit creates the record',
        () async {
      final ops = FaultyFileOps()..armFor((p) => isRecordPath(p));
      final s1 = await open(ops: ops);
      await expectLater(accFor(s1).accept(intentOf('tap-1')), throwsA(anything));
      ops.disarm();
      final r = await accFor(s1).accept(intentOf('tap-1'));
      expect(r.created, isTrue);
      // The failed attempt burnt seq 1; gaps are allowed, reuse is not.
      expect(r.record.seq, 2);
      final s2 = await open();
      expect((await s2.listAll()).single.seq, 2);
    });

    test('failure before the temp file is even written changes nothing', () async {
      final ops = FaultyFileOps()
        ..armFor((p) => isSeqPath(p), m: FaultMode.beforeTempWrite);
      final s1 = await open(ops: ops);
      await expectLater(accFor(s1).accept(intentOf('tap-1')), throwsA(anything));
      expect(await s1.listAll(), isEmpty);
      ops.disarm();
      final r = await accFor(s1).accept(intentOf('tap-1'));
      expect(r.record.seq, 1); // the counter was not advanced by the failure
    });

    test('crash after the local commit: record survives reopen, still pending',
        () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      // No dispose: the process "dies".
      final s2 = await open();
      final b = (await s2.get(a.operationId))!;
      expect(b.state, CommandState.accepted);
      expect(b.operationId, a.operationId);
      expect(b.seq, a.seq);
      expect(b.canonicalBytes, a.canonicalBytes);
      expect(b.payloadHash, a.payloadHash);
      expect(b.payloadFields, a.payloadFields);
      expect(b.intentKey, 'tap-1');
      expect(b.maybeSent, isFalse);
      expect(b.attempts, 0);
      expect((await s2.listPending()).map((e) => e.operationId),
          <String>[a.operationId]);
      expect(s2.openReport.loaded, 1);
      expect(s2.openReport.recoveredSending, 0);
    });

    test('every field round-trips through the file unchanged', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      final s2 = await open();
      expect((await s2.get(a.operationId))!.toJson(), a.toJson());
    });

    test('dedupe by intentKey and the logical-set guard survive a restart',
        () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      final s2 = await open();
      final dup = await accFor(s2).accept(intentOf('tap-1'));
      expect(dup.created, isFalse);
      expect(dup.record.operationId, a.operationId);
      await expectLater(accFor(s2).accept(intentOf('tap-2')),
          throwsA(isA<DuplicateLogicalSetException>()));
      expect((await s2.listAll()).length, 1);
    });

    test('seq counters survive a restart (no reuse)', () async {
      final s1 = await open();
      await accFor(s1).accept(intentOf('t1', setIndex: 1));
      await accFor(s1).accept(intentOf('t2', setIndex: 2));
      final s2 = await open();
      final c = (await accFor(s2).accept(intentOf('t3', setIndex: 3))).record;
      expect(c.seq, 3);
    });

    test('seq counters survive pruning and a restart', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('t1'))).record;
      await s1.markSending(a.operationId);
      await s1.markResult(a.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s1.prune(), 1);
      final s2 = await open();
      expect(await s2.listAll(), isEmpty);
      final b = (await accFor(s2).accept(intentOf('t2', setIndex: 2))).record;
      expect(b.seq, 2);
    });

    test('a lost counter file is repaired above the highest surviving seq',
        () async {
      final s1 = await open();
      await accFor(s1).accept(intentOf('t1', setIndex: 1));
      await accFor(s1).accept(intentOf('t2', setIndex: 2));
      await File('${rootOfScope(root, kUid)}/seq.json').delete();
      final s2 = await open();
      final c = (await accFor(s2).accept(intentOf('t3', setIndex: 3))).record;
      expect(c.seq, 3);
    });
  });

  group('crash while SENDING', () {
    test('reopen returns the record to a resendable state, same id and bytes',
        () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      final sending = await s1.markSending(a.operationId);
      expect(sending.state, CommandState.sending);
      // Crash: the SENDING record is on disk, the process is gone.
      final s2 = await open();
      expect(s2.openReport.recoveredSending, 1);
      final b = (await s2.get(a.operationId))!;
      expect(b.state, CommandState.unknownEffect);
      expect(b.state.isSendable, isTrue);
      expect(b.maybeSent, isTrue); // we cannot claim it never left the device
      expect(b.attempts, 1);
      expect(b.operationId, a.operationId);
      expect(b.canonicalBytes, a.canonicalBytes); // identical stored bytes
      expect(b.payloadHash, a.payloadHash);
      expect((await s2.listPending()).single.operationId, a.operationId);
      // The recovery itself was made durable: a third open sees the same state
      // and has nothing left to recover.
      final s3 = await open();
      expect(s3.openReport.recoveredSending, 0);
      expect((await s3.get(a.operationId))!.state, CommandState.unknownEffect);
    });

    test('a record that is not SENDING is not touched by recovery', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('t1', setIndex: 1))).record;
      final b = (await accFor(s1).accept(intentOf('t2', setIndex: 2))).record;
      await s1.markSending(b.operationId);
      await s1.markResult(b.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      final s2 = await open();
      expect(s2.openReport.recoveredSending, 0);
      expect((await s2.get(a.operationId))!.state, CommandState.accepted);
      expect((await s2.get(b.operationId))!.state, CommandState.synced);
    });

    test('crash while the SENDING commit itself fails: record stays ACCEPTED',
        () async {
      final ops = FaultyFileOps();
      final s1 = await open(ops: ops);
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      ops.armFor((p) => isRecordPath(p));
      await expectLater(s1.markSending(a.operationId), throwsA(anything));
      // Live view and durable state agree: still ACCEPTED, maybeSent false.
      final live = (await s1.get(a.operationId))!;
      expect(live.state, CommandState.accepted);
      expect(live.maybeSent, isFalse);
      final s2 = await open();
      final disk = (await s2.get(a.operationId))!;
      expect(disk.state, CommandState.accepted);
      expect(disk.maybeSent, isFalse);
      expect(disk.attempts, 0);
      expect(disk.canonicalBytes, a.canonicalBytes);
    });
  });

  group('atomic write', () {
    test('failure between temp write and rename keeps the previous durable record',
        () async {
      final ops = FaultyFileOps();
      final s1 = await open(ops: ops);
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      ops.armFor((p) => isRecordPath(p)); // truncated temp, then "crash"
      await expectLater(s1.markSending(a.operationId), throwsA(anything));
      expect(ops.failures, 1);

      final scope = rootOfScope(root, kUid);
      final tmpFiles = (await Directory('$scope/records').list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(tmpFiles.length, 1, reason: 'the crash leaves the temp behind');

      final s2 = await open();
      expect(s2.openReport.removedTempFiles, 1);
      expect(s2.openReport.unreadableFiles, isEmpty);
      final r = (await s2.get(a.operationId))!;
      expect(r.toJson(), a.toJson()); // the previous durable state, intact
      expect((await s2.listAll()).length, 1);
    });

    test('a partial temp file is never read as a record', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      final scope = rootOfScope(root, kUid);
      // Plant a half-written sibling temp for the same record and one for seq.
      final recFile = Directory('$scope/records')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.json'));
      final full = await recFile.readAsBytes();
      await File('${recFile.path}.tmp').writeAsBytes(full.sublist(0, full.length ~/ 3));
      await File('$scope/seq.json.tmp').writeAsString('{"format":1,"coun');
      final s2 = await open();
      expect(s2.openReport.removedTempFiles, 2);
      expect(s2.openReport.loaded, 1);
      expect((await s2.get(a.operationId))!.toJson(), a.toJson());
      expect(File('${recFile.path}.tmp').existsSync(), isFalse);
      expect(File('$scope/seq.json.tmp').existsSync(), isFalse);
    });

    test('failure persisting a SYNCED result keeps the payload and the old state',
        () async {
      final ops = FaultyFileOps();
      final s1 = await open(ops: ops);
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      await s1.markSending(a.operationId);
      ops.armFor((p) => isRecordPath(p));
      await expectLater(
          s1.markResult(a.operationId,
              const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED')),
          throwsA(anything));
      // Live and durable views both still say SENDING with the payload.
      expect((await s1.get(a.operationId))!.state, CommandState.sending);
      expect((await s1.get(a.operationId))!.canonicalBytes, a.canonicalBytes);
      final s2 = await open();
      final r = (await s2.get(a.operationId))!;
      expect(r.state, CommandState.unknownEffect); // recovered from SENDING
      expect(r.canonicalBytes, a.canonicalBytes);
    });

    test('a pruned stub stays gone after a restart', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      await s1.markSending(a.operationId);
      await s1.markResult(a.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 9));
      expect(await s1.prune(), 1);
      final s2 = await open();
      expect(await s2.get(a.operationId), isNull);
    });

    test('synced stub on disk holds no payload bytes', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      final b64 = base64.encode(a.canonicalBytes!);
      expect(await dumpTree(dir), contains(b64)); // present while pending
      await s1.markSending(a.operationId);
      await s1.markResult(a.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      final text = await dumpTree(dir);
      expect(text, isNot(contains(b64)));
      expect(text, isNot(contains('actualReps')));
      final s2 = await open();
      final r = (await s2.get(a.operationId))!;
      expect(r.canonicalBytes, isNull);
      expect(r.state, CommandState.synced);
    });
  });

  group('uid scoping', () {
    test('the raw uid is not used as a path segment and scopes differ', () async {
      final sa = await open();
      final sb = await open(uid: kOtherUid);
      await accFor(sa).accept(intentOf('tap-1'));
      final dirs = (await dir.list().toList()).map((e) => e.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last);
      expect(dirs.length, 2);
      for (final d in dirs) {
        expect(d, startsWith('u_'));
        expect(d.contains(kUid), isFalse);
        expect(d.contains(kOtherUid), isFalse);
      }
      expect(queueScopeDirName(kUid), isNot(queueScopeDirName(kOtherUid)));
      expect(queueScopeDirName(kUid), queueScopeDirName(kUid));
      expect(await sb.listAll(), isEmpty);
    });

    test('another uid never sees the records, also after restart', () async {
      final sa = await open();
      final a = (await accFor(sa).accept(intentOf('tap-1'))).record;
      final sb = await open(uid: kOtherUid);
      expect(await sb.listAll(), isEmpty);
      expect(await sb.get(a.operationId), isNull);
      expect(sb.openReport.loaded, 0);
      // The other uid taps the same intent key / logical set: independent.
      final b = await accFor(sb).accept(intentOf('tap-1'));
      expect(b.created, isTrue);
      expect(b.record.uid, kOtherUid);
      expect(b.record.operationId, isNot(a.operationId));
      final sa2 = await open();
      expect((await sa2.listAll()).single.operationId, a.operationId);
    });

    test('a record file of another uid dropped into this scope is ignored',
        () async {
      final sa = await open();
      final a = (await accFor(sa).accept(intentOf('tap-1'))).record;
      final srcScope = rootOfScope(root, kUid);
      final dstScope = rootOfScope(root, kOtherUid);
      await Directory('$dstScope/records').create(recursive: true);
      for (final f in Directory('$srcScope/records').listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        await f.copy('$dstScope/records/$name');
      }
      final sb = await open(uid: kOtherUid);
      expect(await sb.listAll(), isEmpty);
      expect(await sb.get(a.operationId), isNull);
      expect(await sb.listPending(), isEmpty);
    });

    test('sign-out: store of one uid disposed, the next uid starts clean',
        () async {
      final sa = await open();
      await accFor(sa).accept(intentOf('tap-1'));
      await sa.dispose();
      final sb = await open(uid: kOtherUid);
      expect(await sb.listAll(), isEmpty);
    });
  });

  group('logical-set marker', () {
    bool isMarkerPath(String p) => p.endsWith('/logical_sets.json');
    String markerFile() => '${rootOfScope(root, kUid)}/logical_sets.json';

    test('marker write failure rolls the record back on disk and in memory',
        () async {
      final ops = FaultyFileOps()..armFor(isMarkerPath);
      final s1 = await open(ops: ops);
      await expectLater(accFor(s1).accept(intentOf('tap-1')), throwsA(anything));
      expect(ops.failures, 1);
      // Not saved means not saved: live view and disk agree.
      expect(await s1.listAll(), isEmpty);
      expect(await s1.listPending(), isEmpty);
      final recordFiles = Directory('${rootOfScope(root, kUid)}/records')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));
      expect(recordFiles, isEmpty);
      final s2 = await open();
      expect(await s2.listAll(), isEmpty);
      // The tap can be retried and then succeeds (the set is not blocked).
      final r = await accFor(s2).accept(intentOf('tap-1'));
      expect(r.created, isTrue);
    });

    test('residual record without a marker (crash after the record write): open rebuilds the marker',
        () async {
      final s1 = await open();
      final rec = (await accFor(s1).accept(intentOf('tap-1'))).record;
      await s1.dispose();
      // The marker write never happened: neither the backup nor the primary.
      File(markerFile()).deleteSync();
      File('${markerFile()}.bak').deleteSync();
      final s2 = await open();
      expect((await s2.listAll()).single.operationId, rec.operationId);
      expect(File(markerFile()).existsSync(), isTrue,
          reason: 'open must persist the rebuilt marker');
      expect(await File(markerFile()).readAsString(), contains(rec.logicalSetId!));
      expect(s2.openReport.markersFileRepaired, isFalse); // rebuilt, not restored
      await s2.markSending(rec.operationId);
      await s2.markResult(rec.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s2.prune(), 1);
      final s3 = await open();
      await expectLater(accFor(s3).accept(intentOf('tap-2')),
          throwsA(isA<DuplicateLogicalSetException>()));
    });

    test('marker survives prune and restart on disk, identity only', () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('tap-1'))).record;
      await s1.markSending(a.operationId);
      await s1.markResult(a.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s1.prune(), 1);
      final text = await File(markerFile()).readAsString();
      expect(text, contains(a.logicalSetId!));
      expect(text, isNot(contains('actualReps')));
      final s2 = await open();
      expect(await s2.listAll(), isEmpty);
      await expectLater(accFor(s2).accept(intentOf('tap-2')),
          throwsA(isA<DuplicateLogicalSetException>()));
    });

    test('only the primary marker file missing: restored from the backup', () async {
      final s1 = await open();
      final rec = (await accFor(s1).accept(intentOf('tap-1'))).record;
      await s1.dispose();
      File(markerFile()).deleteSync();
      final s2 = await open();
      expect(s2.openReport.markersFileRepaired, isTrue);
      expect(s2.openReport.recoveryRequired, isFalse);
      expect(File(markerFile()).existsSync(), isTrue);
      expect((await s2.listAll()).single.operationId, rec.operationId);
    });

    test('corrupt primary marker file: restored from the backup, corrupt copy preserved, pruned-stub marker kept',
        () async {
      final s1 = await open();
      final pruned = (await accFor(s1).accept(intentOf('t1', setIndex: 1))).record;
      final live = (await accFor(s1).accept(intentOf('t2', setIndex: 2))).record;
      await s1.markSending(pruned.operationId);
      await s1.markResult(pruned.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s1.prune(), 1);
      await File(markerFile()).writeAsString('{not json');

      final s2 = await open();
      expect(s2.openReport.markersFileRepaired, isTrue);
      expect(s2.openReport.recoveryRequired, isFalse);
      expect((await s2.listAll()).single.operationId, live.operationId);
      // The corrupt evidence is kept beside the restored file.
      final kept = Directory(rootOfScope(root, kUid))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('logical_sets.json.corrupt-'))
          .toList();
      expect(kept.length, 1);
      expect(kept.single.readAsStringSync(), '{not json');
      // Both sets still refuse a second APPEND, the pruned one included.
      await expectLater(accFor(s2).accept(intentOf('t3', setIndex: 2)),
          throwsA(isA<DuplicateLogicalSetException>()));
      await expectLater(accFor(s2).accept(intentOf('t4', setIndex: 1)),
          throwsA(isA<DuplicateLogicalSetException>()));
      // The restored file is healthy again.
      final s3 = await open();
      expect(s3.openReport.markersFileRepaired, isFalse);
    });
  });

  group('corruption handling', () {
    test('an unreadable record file is reported, kept on disk and not loaded',
        () async {
      final s1 = await open();
      final a = (await accFor(s1).accept(intentOf('t1', setIndex: 1))).record;
      await accFor(s1).accept(intentOf('t2', setIndex: 2));
      final scope = rootOfScope(root, kUid);
      final victim = Directory('$scope/records')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.json') &&
              f.path.contains(_hexOf(a.operationId)));
      await victim.writeAsString('{not json');
      final s2 = await open();
      expect(s2.openReport.unreadableFiles.length, 1);
      expect(victim.existsSync(), isTrue); // never deleted
      expect(await s2.get(a.operationId), isNull);
      expect((await s2.listAll()).length, 1);
    });
  });
}

String rootOfScope(String root, String uid) => '$root/${queueScopeDirName(uid)}';

String _hexOf(String s) => utf8
    .encode(s)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
