// Sender behaviour against a fake server: lost acknowledgement, restart
// recovery, result-code mapping, holds/backoff and integrity checks.
// Parametrised over the in-memory and the file store where it matters.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/result_codes.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/offline_test_support.dart';

void main() {
  for (final kind in <String>['in-memory', 'file']) {
    group('lost acknowledgement [$kind]', () {
      late TestClock clock;
      Directory? dir;
      late StoreFactory factory;
      late CommandQueueStore store;
      late IdMinter minter;
      late CompleteSetAcceptor acceptor;
      late FakeServer server;
      late CommandSender sender;

      setUp(() async {
        clock = TestClock();
        minter = IdMinter();
        server = FakeServer();
        if (kind == 'file') {
          dir = await makeTempRoot();
          factory = StoreFactory.file(clock, dir!);
        } else {
          dir = null;
          factory = StoreFactory.memory(clock);
        }
        store = await factory.open();
        acceptor = acceptorFor(store, clock, minter: minter);
        sender = senderFor(store, server, clock,
            sendTimeout: const Duration(milliseconds: 60));
      });

      tearDown(() async {
        await store.dispose();
        if (dir != null) await removeTempRoot(dir!);
      });

      test('happy path: COMMITTED -> SYNCED, one effect, payload erased',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        final rep = await sender.sendNext();
        expect(rep.status, SendStatus.synced);
        expect(rep.code, 'COMMITTED');
        expect(server.effects.length, 1);
        expect(server.effects.single.operationId, rec.operationId);
        expect(server.effects.single.bytes, rec.canonicalBytes);
        final after = (await store.get(rec.operationId))!;
        expect(after.state, CommandState.synced);
        expect(after.canonicalBytes, isNull);
        expect(after.ackSummary!.revisionAfter, 1);
        expect(after.ackSummary!.serverTimeMs, 42);
        expect((await sender.sendNext()).status, SendStatus.idle);
        expect(server.received.length, 1);
      });

      test('the envelope carries id, stored bytes, matching hash and device',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1', ))).record;
        await sender.sendNext();
        final env = server.received.single;
        expect(env.operationId, rec.operationId);
        expect(env.payloadBytes, rec.canonicalBytes);
        expect(env.payloadHash, rec.payloadHash);
        expect(env.writerEpochClaim, rec.acceptedEpoch);
        expect(env.deviceInstallId, kDevice);
        expect(env.clientBuild, 'test-build');
      });

      test('ack lost by a thrown transport error: resend is byte-identical and ends SYNCED with ONE effect',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        server.faults.add(Fault.applyThenThrow);

        final first = await sender.sendNext();
        expect(first.status, SendStatus.retryLater);
        expect(server.effects.length, 1); // the server DID apply it
        final mid = (await store.get(rec.operationId))!;
        expect(mid.state, CommandState.unknownEffect);
        expect(mid.maybeSent, isTrue);
        expect(mid.lastResultCode, 'TRANSPORT_ERROR');
        expect(mid.canonicalBytes, rec.canonicalBytes); // bytes kept
        expect(mid.operationId, rec.operationId);

        sender.resetBackoff(); // connectivity returned
        final second = await sender.sendNext();
        expect(second.status, SendStatus.synced);
        expect(second.code, 'ALREADY_COMMITTED');
        expect(server.effects.length, 1); // still exactly one effect
        expect(server.received.length, 2);
        expect(server.received[1].operationId, server.received[0].operationId);
        expect(server.received[1].payloadBytes, server.received[0].payloadBytes);
        expect(server.received[1].payloadHash, server.received[0].payloadHash);
        final end = (await store.get(rec.operationId))!;
        expect(end.state, CommandState.synced);
        expect(end.attempts, 2);
        expect(end.canonicalBytes, isNull);
      });

      test('ack lost by a timeout: same behaviour as a thrown error', () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        server.faults.add(Fault.applyThenHang);
        final first = await sender.sendNext();
        expect(first.status, SendStatus.retryLater);
        expect((await store.get(rec.operationId))!.state,
            CommandState.unknownEffect);
        expect(server.effects.length, 1);
        sender.resetBackoff();
        final second = await sender.sendNext();
        expect(second.status, SendStatus.synced);
        expect(server.effects.length, 1);
        expect(server.received[1].payloadBytes, rec.canonicalBytes);
        expect(server.received[1].operationId, rec.operationId);
      });

      test('request lost before the server saw it: the resend is the first effect',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        server.faults.add(Fault.throwWithoutApplying);
        expect((await sender.sendNext()).status, SendStatus.retryLater);
        expect(server.effects, isEmpty);
        sender.resetBackoff();
        final second = await sender.sendNext();
        expect(second.status, SendStatus.synced);
        expect(second.code, 'COMMITTED');
        expect(server.effects.length, 1);
        expect(server.received[1].payloadBytes, rec.canonicalBytes);
      });

      test('many lost acks in a row never change id or bytes and never give up',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        for (var i = 0; i < 6; i++) {
          server.faults.add(Fault.applyThenThrow);
        }
        for (var i = 0; i < 6; i++) {
          sender.resetBackoff();
          expect((await sender.sendNext()).status, SendStatus.retryLater);
        }
        sender.resetBackoff();
        expect((await sender.sendNext()).status, SendStatus.synced);
        expect(server.effects.length, 1);
        expect(server.received.length, 7);
        for (final env in server.received) {
          expect(env.operationId, rec.operationId);
          expect(env.payloadBytes, rec.canonicalBytes);
        }
        expect((await store.get(rec.operationId))!.attempts, 7);
      });

      test('an answer of SUPERSEDED / DETAIL_EXPIRED also ends in SYNCED with flags',
          () async {
        final a = (await acceptor.accept(intentOf('a', setIndex: 1))).record;
        final b = (await acceptor.accept(intentOf('b', setIndex: 2))).record;
        server.scriptedCodes.addAll(
            <String>['SUPERSEDED', 'ALREADY_COMMITTED_DETAIL_EXPIRED']);
        expect((await sender.sendNext()).status, SendStatus.synced);
        expect((await sender.sendNext()).status, SendStatus.synced);
        final ra = (await store.get(a.operationId))!;
        final rb = (await store.get(b.operationId))!;
        expect(ra.state, CommandState.synced);
        expect(ra.ackSummary!.superseded, isTrue);
        expect(ra.ackSummary!.detailExpired, isFalse);
        expect(rb.state, CommandState.synced);
        expect(rb.ackSummary!.detailExpired, isTrue);
        expect(rb.ackSummary!.superseded, isFalse);
        expect(server.effects, isEmpty); // scripted answers applied nothing
      });

      test('after a lost ack the backoff holds the session; probing resumes later',
          () async {
        await acceptor.accept(intentOf('tap-1'));
        server.faults.add(Fault.throwWithoutApplying);
        final first = await sender.sendNext();
        expect(first.nextAttemptAt, isNotNull);
        final delay = first.nextAttemptAt!.difference(clock.now());
        // 2 s base with half fixed jitter: between 1 s and 2 s.
        expect(delay >= const Duration(seconds: 1), isTrue);
        expect(delay <= const Duration(seconds: 2), isTrue);
        // Inside the window nothing is sent.
        final held = await sender.sendNext();
        expect(held.status, SendStatus.sessionOnHold);
        expect(server.received.length, 1);
        clock.advance(const Duration(seconds: 3));
        expect((await sender.sendNext()).status, SendStatus.synced);
      });

      test('retry backoff grows exponentially and is capped at 5 minutes',
          () async {
        await acceptor.accept(intentOf('tap-1'));
        final delays = <Duration>[];
        for (var i = 0; i < 12; i++) {
          server.faults.add(Fault.throwWithoutApplying);
          final rep = await sender.sendNext();
          delays.add(rep.nextAttemptAt!.difference(clock.now()));
          clock.advance(const Duration(minutes: 6));
        }
        // upper bounds 2,4,8,... capped; lower bound is half of the bound.
        var bound = const Duration(seconds: 2);
        for (final d in delays) {
          expect(d <= bound, isTrue, reason: '$d should be <= $bound');
          expect(d >= bound * 0.5 - const Duration(milliseconds: 1), isTrue,
              reason: '$d should be >= half of $bound');
          bound = bound * 2 > const Duration(minutes: 5)
              ? const Duration(minutes: 5)
              : bound * 2;
        }
        expect(delays.last <= const Duration(minutes: 5), isTrue);
        expect(delays.last >= const Duration(seconds: 150), isTrue);
      });

      test('a successful ack clears the hold so the next record goes at once',
          () async {
        await acceptor.accept(intentOf('a', setIndex: 1));
        await acceptor.accept(intentOf('b', setIndex: 2));
        server.faults.add(Fault.throwWithoutApplying);
        expect((await sender.sendNext()).status, SendStatus.retryLater);
        sender.resetBackoff();
        expect((await sender.sendNext()).status, SendStatus.synced);
        expect((await sender.sendNext()).status, SendStatus.synced);
        expect(server.effects.length, 2);
      });

      test('records of one session are sent in seq order', () async {
        final ids = <String>[];
        for (var i = 1; i <= 4; i++) {
          ids.add((await acceptor.accept(intentOf('t$i', setIndex: i)))
              .record
              .operationId);
          clock.advance(const Duration(milliseconds: 5));
        }
        final reports = await sender.sendAvailable();
        expect(reports.where((r) => r.status == SendStatus.synced).length, 4);
        expect(server.effects.map((e) => e.operationId).toList(), ids);
      });

      test('one sender per uid: a concurrent sendNext reports busy and sends nothing',
          () async {
        await acceptor.accept(intentOf('tap-1'));
        server.gate = Completer<TransportAnswer>();
        final inFlight = sender.sendNext();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((await sender.sendNext()).status, SendStatus.busy);
        expect(server.received.length, 1);
        server.gate!.complete(const TransportAnswer(code: 'COMMITTED'));
        expect((await inFlight).status, SendStatus.synced);
      });

      test('a failing writer-token read sends nothing and leaves the record untouched',
          () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        final s2 = senderFor(store, server, clock,
            proof: (uid, sid) async => throw StateError('keystore locked'));
        final rep = await s2.sendNext();
        expect(rep.status, SendStatus.proofUnavailable);
        final r = (await store.get(rec.operationId))!;
        expect(r.state, CommandState.accepted);
        expect(r.maybeSent, isFalse);
        expect(r.attempts, 0);
        expect(server.received, isEmpty);
      });

      test('the writer proof is passed to the server but never stored', () async {
        final rec = (await acceptor.accept(intentOf('tap-1'))).record;
        String? seenUid;
        String? seenSession;
        final s2 = senderFor(store, server, clock, proof: (uid, sid) async {
          seenUid = uid;
          seenSession = sid;
          return 'SECRET-WRITER-TOKEN';
        });
        await s2.sendNext();
        expect(server.received.single.writerProof, 'SECRET-WRITER-TOKEN');
        expect(seenUid, kUid);
        expect(seenSession, 'sess-1');
        expect(jsonEncode((await store.get(rec.operationId))!.toJson()),
            isNot(contains('SECRET-WRITER-TOKEN')));
        if (dir != null) {
          expect(await dumpTree(dir!), isNot(contains('SECRET-WRITER-TOKEN')));
        }
      });
    });
  }

  group('restart recovery with a real file store', () {
    late Directory dir;
    late TestClock clock;
    late IdMinter minter;
    late FakeServer server;
    final stores = <FileCommandQueueStore>[];
    FileCommandQueueStore? live;

    Future<FileCommandQueueStore> open() async {
      await live?.dispose(); // a restart: one live instance per scope
      final s = await FileCommandQueueStore.open(
          uid: kUid, rootDir: rootPathOf(dir), nowMs: clock.nowMs);
      live = s;
      stores.add(s);
      return s;
    }

    setUp(() async {
      dir = await makeTempRoot();
      clock = TestClock();
      minter = IdMinter();
      server = FakeServer();
    });
    tearDown(() async {
      for (final s in stores) {
        await s.dispose();
      }
      stores.clear();
      await removeTempRoot(dir);
    });

    test('crash while SENDING (server never received it): resend with same id and stored bytes',
        () async {
      final s1 = await open();
      final rec =
          (await acceptorFor(s1, clock, minter: minter).accept(intentOf('t'))).record;
      await s1.markSending(rec.operationId); // process dies right here

      final s2 = await open();
      final sender = senderFor(s2, server, clock);
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.synced);
      expect(server.received.single.operationId, rec.operationId);
      expect(server.received.single.payloadBytes, rec.canonicalBytes);
      expect(server.effects.length, 1);
      final end = (await s2.get(rec.operationId))!;
      expect(end.attempts, 2); // the lost first attempt + this one
      expect(end.maybeSent, isTrue);
    });

    test('crash while SENDING after the server applied: replay answers ALREADY_COMMITTED, one effect',
        () async {
      final s1 = await open();
      final rec =
          (await acceptorFor(s1, clock, minter: minter).accept(intentOf('t'))).record;
      final sending = await s1.markSending(rec.operationId);
      // The request reached the server before the process died.
      await server.send(CommandEnvelope(
          operationId: sending.operationId,
          payloadBytes: sending.canonicalBytes!,
          payloadHash: sending.payloadHash,
          writerProof: null,
          writerEpochClaim: 0,
          deviceInstallId: kDevice,
          clientBuild: 'b'));
      expect(server.effects.length, 1);

      final s2 = await open();
      final rep = await senderFor(s2, server, clock).sendNext();
      expect(rep.status, SendStatus.synced);
      expect(rep.code, 'ALREADY_COMMITTED');
      expect(server.effects.length, 1);
      expect(server.received.last.payloadBytes, rec.canonicalBytes);
      expect((await s2.get(rec.operationId))!.state, CommandState.synced);
    });

    test('lost ack, then the app restarts, then the resend completes once',
        () async {
      final s1 = await open();
      final rec =
          (await acceptorFor(s1, clock, minter: minter).accept(intentOf('t'))).record;
      server.faults.add(Fault.applyThenThrow);
      expect((await senderFor(s1, server, clock).sendNext()).status,
          SendStatus.retryLater);
      // Restart: backoff state is in memory and is gone, the record is not.
      final s2 = await open();
      expect(s2.openReport.recoveredSending, 0);
      final restored = (await s2.get(rec.operationId))!;
      expect(restored.state, CommandState.unknownEffect);
      expect(restored.canonicalBytes, rec.canonicalBytes);
      final rep = await senderFor(s2, server, clock).sendNext();
      expect(rep.status, SendStatus.synced);
      expect(server.effects.length, 1);
      expect(server.received[1].operationId, server.received[0].operationId);
      expect(server.received[1].payloadBytes, server.received[0].payloadBytes);
    });

    test('integrity: stored bytes that no longer match the stored hash are never sent',
        () async {
      final s1 = await open();
      final rec =
          (await acceptorFor(s1, clock, minter: minter).accept(intentOf('t'))).record;
      await s1.dispose();
      // Flip the payload on disk (bit-rot / tampering) keeping the old hash.
      final file = Directory('${rootPathOf(dir)}/${queueScopeDirName(kUid)}/records')
          .listSync()
          .whereType<File>()
          .single;
      final doc = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final recJson = Map<String, Object?>.from(doc['record']! as Map);
      final bytes = base64.decode(recJson['canonicalBytes']! as String);
      bytes[bytes.length ~/ 2] ^= 0x01;
      recJson['canonicalBytes'] = base64.encode(bytes);
      doc['record'] = recJson;
      await file.writeAsString(jsonEncode(doc));

      final s2 = await open();
      final sender = senderFor(s2, server, clock);
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.integrityFailure);
      expect(rep.operationId, rec.operationId);
      expect(server.received, isEmpty);
      final r = (await s2.get(rec.operationId))!;
      expect(r.state, CommandState.accepted); // untouched
      expect(r.maybeSent, isFalse);
      expect(r.attempts, 0);
    });

    test('a corrupt record in one session must not stop an unrelated session',
        () async {
      final s1 = await open();
      final acc = acceptorFor(s1, clock, minter: minter);
      final bad = (await acc.accept(intentOf('bad', sessionId: 'sess-A'))).record;
      clock.advance(const Duration(seconds: 1));
      final good = (await acc.accept(intentOf('good', sessionId: 'sess-B'))).record;
      await s1.dispose();
      final hex = utf8
          .encode(bad.operationId)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final file = File(
          '${rootPathOf(dir)}/${queueScopeDirName(kUid)}/records/$hex.json');
      final doc = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final recJson = Map<String, Object?>.from(doc['record']! as Map);
      final bytes = base64.decode(recJson['canonicalBytes']! as String);
      bytes[3] ^= 0x01;
      recJson['canonicalBytes'] = base64.encode(bytes);
      doc['record'] = recJson;
      await file.writeAsString(jsonEncode(doc));

      final s2 = await open();
      final sender = senderFor(s2, server, clock);
      final reports = await sender.sendAvailable();
      // The bad record is skipped; integrityFailure only once nothing else
      // is sendable.
      expect(reports.first.status, SendStatus.synced);
      expect(reports.first.operationId, good.operationId);
      expect(reports.last.status, SendStatus.integrityFailure);
      expect(reports.last.operationId, bad.operationId);
      expect(server.effects.any((e) => e.operationId == bad.operationId),
          isFalse);
      expect((await s2.get(bad.operationId))!.state, CommandState.accepted);
      expect(server.effects.map((e) => e.operationId), contains(good.operationId),
          reason: 'poison record in sess-A blocks the unrelated sess-B');
    });
  });

  group('result code mapping', () {
    late TestClock clock;
    late CommandQueueStore store;
    late CompleteSetAcceptor acceptor;
    late FakeServer server;
    late CommandSender sender;

    setUp(() async {
      clock = TestClock();
      store = await StoreFactory.memory(clock).open();
      acceptor = acceptorFor(store, clock);
      server = FakeServer();
      sender = senderFor(store, server, clock);
    });
    tearDown(() => store.dispose());

    Future<CommandRecord> sendWith(String code) async {
      final rec = (await acceptor.accept(intentOf('t-$code'))).record;
      server.scriptedCodes.add(code);
      await sender.sendNext();
      return (await store.get(rec.operationId))!;
    }

    for (final code in <String>[
      'COMMITTED',
      'ALREADY_COMMITTED',
      'ALREADY_COMMITTED_DETAIL_EXPIRED',
      'SUPERSEDED'
    ]) {
      test('$code -> SYNCED', () async {
        final r = await sendWith(code);
        expect(r.state, CommandState.synced);
        expect(r.lastResultCode, code);
        expect(r.canonicalBytes, isNull);
      });
    }

    for (final code in <String>[
      ...kTerminalRefusalCodes,
      ...kClientDefectCodes,
      'OUTCOME_UNKNOWN_REPLAY_CLOSED',
    ]) {
      test('$code -> CONFLICTED (terminal), never SYNCED, payload kept', () async {
        final r = await sendWith(code);
        expect(r.state, CommandState.conflicted);
        expect(r.conflictTerminal, isTrue);
        expect(r.conflictKind, code);
        expect(r.canonicalBytes, isNotNull);
        expect(await store.listPending(), isEmpty);
      });
    }

    for (final code in <String>['DEPENDENCY_PENDING', 'VERSION_RETIRED']) {
      test('$code -> back to ACCEPTED with maybeSent kept', () async {
        final r = await sendWith(code);
        expect(r.state, CommandState.accepted);
        expect(r.maybeSent, isTrue);
        expect(r.canonicalBytes, isNotNull);
        expect((await store.listPending()).length, 1);
      });
    }

    for (final code in <String>[
      'MIGRATION_HOLD',
      'AUTH_REVOKED',
      'ACCOUNT_DELETING',
      'RATE_LIMITED',
      'NOT_ATTEMPTED',
    ]) {
      test('$code -> ACCEPTED and the session is held', () async {
        final r = await sendWith(code);
        expect(r.state, CommandState.accepted);
        final next = await sender.sendNext();
        expect(next.status, SendStatus.sessionOnHold);
        expect(server.received.length, 1);
      });
    }

    test('FENCE_SHARD_FULL proves no effect: back to ACCEPTED (T11), resendable',
        () async {
      final rec = (await acceptor.accept(intentOf('t-fence'))).record;
      server.scriptedCodes.add('FENCE_SHARD_FULL');
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.retryLater);
      expect(rep.nextAttemptAt, isNotNull);
      final r = (await store.get(rec.operationId))!;
      expect(r.state, CommandState.accepted);
      expect(r.maybeSent, isTrue);
      expect(r.lastResultCode, 'FENCE_SHARD_FULL');
      expect(r.canonicalBytes, rec.canonicalBytes);
      expect((await store.listPending()).length, 1);
      sender.resetBackoff();
      expect((await sender.sendNext()).status, SendStatus.synced);
    });

    for (final code in <String>['UNAVAILABLE']) {
      test('$code -> UNKNOWN_EFFECT (resendable, same bytes)', () async {
        final rec = (await acceptor.accept(intentOf('t-$code'))).record;
        server.scriptedCodes.add(code);
        final rep = await sender.sendNext();
        expect(rep.status, SendStatus.retryLater);
        final r = (await store.get(rec.operationId))!;
        expect(r.state, CommandState.unknownEffect);
        expect(r.canonicalBytes, rec.canonicalBytes);
        expect(r.state.isSendable, isTrue);
      });
    }

    for (final code in <String>['NOT_WRITER', 'SESSION_COMMAND_LIMIT']) {
      test('$code -> non-terminal CONFLICTED and the session loop pauses', () async {
        final r = await sendWith(code);
        expect(r.state, CommandState.conflicted);
        expect(r.conflictTerminal, isFalse);
        expect(r.canonicalBytes, isNotNull);
      });
    }

    test('an unknown future code keeps the record ACCEPTED, never SYNCED, and counts',
        () async {
      final r = await sendWith('TOTALLY_NEW_CODE_V9');
      expect(r.state, CommandState.accepted);
      expect(r.canonicalBytes, isNotNull);
      expect(sender.unknownCodeCount, 1);
      expect(classifyResultCode('TOTALLY_NEW_CODE_V9'), ResultClass.unknown);
    });

    test('an empty and a lowercase code are unknown, not success', () async {
      expect(classifyResultCode(''), ResultClass.unknown);
      expect(classifyResultCode('committed'), ResultClass.unknown);
    });

    test('AUTH_REVOKED holds until sign-in; other holds clear on foreground',
        () async {
      await sendWith('AUTH_REVOKED');
      sender.resetBackoff(); // foreground / connectivity
      expect((await sender.sendNext()).status, SendStatus.sessionOnHold);
      sender.resetBackoff(signedIn: true);
      expect((await sender.sendNext()).status, SendStatus.synced);
    });

    test('a hold answer honours a larger server retryAfter', () async {
      final rec = (await acceptor.accept(intentOf('t'))).record;
      server.scriptedCodes.add('RATE_LIMITED');
      // scriptedCodes carry no retryAfter; use a transport wrapper instead.
      final wrapped = _RetryAfterTransport(server, 120000);
      final s2 = senderFor(store, wrapped, clock);
      final rep = await s2.sendNext();
      expect(rep.nextAttemptAt!.difference(clock.now()),
          const Duration(milliseconds: 120000));
      expect((await store.get(rec.operationId))!.state, CommandState.accepted);
    });

    test('a held session does not block an unrelated session', () async {
      final a = (await acceptor.accept(intentOf('a', sessionId: 'sess-A'))).record;
      clock.advance(const Duration(seconds: 1));
      final b = (await acceptor.accept(intentOf('b', sessionId: 'sess-B'))).record;
      server.scriptedCodes.add('MIGRATION_HOLD');
      expect((await sender.sendNext()).operationId, a.operationId);
      final rep = await sender.sendNext();
      expect(rep.status, SendStatus.synced);
      expect(rep.operationId, b.operationId);
    });

    test('sessions are served by acceptance time across sessions', () async {
      final b = (await acceptor.accept(intentOf('b', sessionId: 'sess-B'))).record;
      clock.advance(const Duration(seconds: 1));
      final a = (await acceptor.accept(intentOf('a', sessionId: 'sess-A'))).record;
      await sender.sendAvailable();
      expect(server.effects.map((e) => e.operationId).toList(),
          <String>[b.operationId, a.operationId]);
    });

    test('an empty queue is idle and sends nothing', () async {
      expect((await sender.sendNext()).status, SendStatus.idle);
      expect(server.received, isEmpty);
    });
  });
}

class _RetryAfterTransport implements CommandTransport {
  _RetryAfterTransport(this.inner, this.retryAfterMs);
  final FakeServer inner;
  final int retryAfterMs;
  @override
  Future<TransportAnswer> send(CommandEnvelope e) async {
    final a = await inner.send(e);
    return TransportAnswer(code: a.code, retryAfterMs: retryAfterMs);
  }
}
