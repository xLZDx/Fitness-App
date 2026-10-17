// EP-D journal side of the revocation / KEEP / DELETE rows: DECISION arbitration,
// the recovery table through listUnfinished, KEEP cleanup. Rows DT-19-12..25 of
// docs/phase2/s04/S04_TEST_PLAN.md (S04-19 AC-5..13 at the journal level) and the
// "pending decision does not block Start" rule of Design 4.3/5.4. Oracle: Design
// 4.3 (decision rule Z5/Z7, table, KEEP cleanup Z16) and 4.5, not the code.
// Rows that need the controller or widgets (DT-19-16, the recoveryComplete
// gating of DT-19-22) are NOT_RUN in this group.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import 'journal_kit.dart';

final String id1 = recId(1);

Uint8List utf(String s) => Uint8List.fromList(utf8.encode(s));

/// Revocation: five fixes flushed, a permissionRevoked event, SEALED (pending).
Future<void> revokedRecording(RecKit k) async {
  await k.record(id1, 5);
  await revokeSeal(k);
}

Future<void> revokeSeal(RecKit k) async {
  await k.journal.appendEvent(const JournalEvent(JournalEventKind.permissionRevoked, 5200));
  await k.journal.seal(id1, const SealRequest(reason: StopReason.permissionRevoked, lastOffsetMs: 5200));
}

Future<void> keepFlow(RecKit k) async {
  if (await k.journal.decideKeep(id1) == DecisionOutcome.committed) {
    await k.journal.handOff(id1);
  }
}

String decisionPath(RecKit k) => '${k.dirOf(id1)}/DECISION';

String? decisionText(RecKit k) {
  final b = k.bytesOf(decisionPath(k));
  return b == null ? null : utf8.decode(b);
}

Future<void> expectPendingOrFinished(RecKit k, String why, {required bool deleteFlow}) async {
  final decisionBefore = decisionText(k);
  final r = await k.journal.listUnfinished();
  final acts = await activityCount(k);
  if (r.isNotEmpty) {
    expect(r.single.status, UnfinishedStatus.readable, reason: why);
    expect(r.single.pendingDecision, isTrue, reason: '$why: still the pending decision');
    expect(r.single.sampleCount, 5, reason: '$why: nothing lost');
    expect(acts, 0, reason: '$why: pending and stored would be two copies');
    expect(decisionBefore, isNull, reason: '$why: a durable decision is always completed by recovery');
    expect(k.filesOf(id1), contains('SEALED'));
  } else if (deleteFlow) {
    expect(acts, 0, reason: '$why: a deleted recording never becomes an activity');
    expect(k.filesOf(id1), isEmpty, reason: '$why: no sample or marker may stay');
  } else {
    expect(acts, 1, reason: '$why: kept means exactly one activity');
    expect(k.filesOf(id1), isEmpty, reason: '$why: the recording is cleaned up');
  }
}

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  group('pending decision (Z2) is listed and does not block Start', () {
    test('a revoked, sealed recording is listed pending and survives a kill', () async {
      await revokedRecording(k);
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.readable);
      expect(r.single.pendingDecision, isTrue);
      expect(r.single.blocksStart, isFalse, reason: 'Design 5.4: the revoked item does not block Start');
      expect(k.filesOf(id1), contains('SEALED'));
      // it is not offered as a normal Resume
      await expectLater(k.journal.openForResume(id1), throwsJournalCode('notResumable'));
    });

    test('an ordinary unfinished recording still blocks Start; not listed for another uid', () async {
      await k.record(id1, 4);
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.pendingDecision, isFalse);
      expect(r.single.blocksStart, isTrue);
      k.uid = 'user-b';
      expect(await k.journal.listUnfinished(), isEmpty);
    });
  });

  group('DT-19-12 a fault at every step of the canonical sequence', () {
    test('/fault-at-revocation and /fault-after-seal: after any crash the partial recording is offered whole', () async {
      Future<void> prep(RecKit x) => x.record(id1, 5);
      final ops = (await opsOf(prep, revokeSeal)).where((o) => o.kind != FsOpKind.note).toList();
      expect(ops.length, greaterThan(10));
      for (final o in ops) {
        final c = await crashRun(prep, revokeSeal, o.index);
        final r = await c.journal.listUnfinished();
        expect(r, hasLength(1), reason: 'crash after $o');
        expect(r.single.status, UnfinishedStatus.readable, reason: '$o');
        expect(r.single.sampleCount, 5, reason: '$o');
        expect(await activityCount(c), 0);
        await c.dispose();
      }
    });

    test('/process-death-while-pending, /fault-during-keep, /fault-during-hand-off: one consistent state at every point', () async {
      final ops = (await opsOf(revokedRecording, keepFlow)).where((o) => o.kind != FsOpKind.note).toList();
      expect(ops.length, greaterThan(15));
      var finished = 0, pending = 0;
      for (final o in ops) {
        final c = await crashRun(revokedRecording, keepFlow, o.index);
        final before = decisionText(c);
        await expectPendingOrFinished(c, 'keep: crash after $o', deleteFlow: false);
        (await activityCount(c)) == 1 ? finished++ : pending++;
        if (before == 'KEEP') {
          expect(await activityCount(c), 1, reason: 'a durable KEEP is completed by recovery: $o');
        }
        await c.dispose();
      }
      expect(finished, greaterThan(0));
      expect(pending, greaterThan(0));
    });

    test('/fault-during-delete: pending or gone, never a leftover offered', () async {
      final ops = (await opsOf(revokedRecording, (x) async => x.journal.decideDelete(id1)))
          .where((o) => o.kind != FsOpKind.note)
          .toList();
      expect(ops.length, greaterThan(15));
      var gone = 0, pending = 0;
      for (final o in ops) {
        final c = await crashRun(revokedRecording, (x) async => x.journal.decideDelete(id1), o.index);
        final before = decisionText(c);
        await expectPendingOrFinished(c, 'delete: crash after $o', deleteFlow: true);
        if (before == 'DELETE') {
          expect(c.filesOf(id1), isEmpty, reason: 'a durable DELETE is completed by recovery: $o');
        }
        (await c.journal.listUnfinished()).isEmpty ? gone++ : pending++;
        await c.dispose();
      }
      expect(gone, greaterThan(0));
      expect(pending, greaterThan(0));
    });
  });

  group('DT-19-13 one activity, no resurrection', () {
    test('/keep-repeated-and-keep-after-restart-give-one-activity', () async {
      await revokedRecording(k);
      expect(await k.journal.decideKeep(id1), DecisionOutcome.committed);
      final first = decisionText(k);
      expect(first, 'KEEP');
      expect(await k.journal.decideKeep(id1), isIn([DecisionOutcome.committed, DecisionOutcome.alreadyDecided]));
      expect(decisionText(k), 'KEEP', reason: 'the replay changes nothing');
      await k.kill();
      await k.journal.decideKeep(id1);
      expect(await k.journal.handOff(id1), HandOffResult.done);
      expect(await k.journal.handOff(id1), HandOffResult.done, reason: 'a repeat after completion is still done');
      expect(await activityCount(k), 1);
      expect(k.handedOffCount, 1);
    });

    test('/delete-after-a-started-hand-off-never-resurrects: Delete after a durable KEEP is refused, the activity stays', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.activity.crashAfterPut = SimulatedCrash('after put');
      await k.journal.handOff(id1);
      expect(await activityCount(k), 1);
      k.activity.crashAfterPut = null;
      expect(await k.journal.decideDelete(id1), DecisionOutcome.alreadyDecided);
      expect(await activityCount(k), 1, reason: 'Delete never removes the finished activity');
      expect(k.filesOf(id1), contains('seg-0001.log'), reason: 'and deletes no recording file');
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);
    });
  });

  group('DT-19-14 / DT-19-15 Keep and Delete are exclusive; the first durable marker wins', () {
    test('/crash-before-put-with-keep-marker: recovery completes the idempotent upsert', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.activity.crashBeforePut = SimulatedCrash('before put');
      await k.journal.handOff(id1);
      expect(await activityCount(k), 0);
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);
    });

    test('/crash-before-put-with-delete-marker: recovery completes the ordered delete', () async {
      await revokedRecording(k);
      k.ops.crashAfterPrefix = 'ops.link';
      await expectLater(k.journal.decideDelete(id1), throwsA(isA<SimulatedCrash>()));
      expect(decisionText(k), 'DELETE');
      expect(k.filesOf(id1), contains('seg-0001.log'));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.filesOf(id1), isEmpty);
      expect(await activityCount(k), 0);
    });

    test('/crash-immediately-after-a-successful-put and /crash-before-journal-cleanup', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.activity.crashAfterPut = SimulatedCrash('after put');
      await k.journal.handOff(id1);
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);

      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      await k2.journal.decideKeep(id1);
      k2.ops.renameDirError = SimulatedCrash('before cleanup');
      await k2.journal.handOff(id1);
      expect(await activityCount(k2), 1);
      expect(k2.filesOf(id1), contains('DECISION'));
      await k2.kill();
      expect(await k2.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k2), 1);
      expect(k2.filesOf(id1), isEmpty);
      await k2.dispose();
    });

    test('/replayed-keep and /replayed-delete change nothing', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      final snap = k.snapshot(id1);
      await k.journal.decideKeep(id1);
      expect(k.snapshot(id1), snap);

      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      k2.ops.crashAfterPrefix = 'ops.link';
      await k2.journal.decideDelete(id1).then((_) {}, onError: (_) {});
      await k2.kill();
      // DELETE is durable but not executed yet; a replay reports/continues, never reverts
      final out = await k2.journal.decideDelete(id1);
      expect(out, isIn([DecisionOutcome.committed, DecisionOutcome.alreadyDecided]));
      expect(k2.filesOf(id1), isEmpty);
      await k2.dispose();
    });

    test('/forced-delete-after-KEEP-is-durable (DT-19-15): refused, activity intact', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      expect(await k.journal.decideDelete(id1), DecisionOutcome.alreadyDecided);
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1), contains('seg-0001.log'));
      await k.journal.handOff(id1);
      expect(await activityCount(k), 1);
      // after the cleanup the directory is gone: a late Delete must not touch the activity
      Object? thrown;
      DecisionOutcome? out;
      try {
        out = await k.journal.decideDelete(id1);
      } catch (e) {
        thrown = e;
      }
      expect(out == null || out == DecisionOutcome.alreadyDecided || thrown == null, isTrue);
      expect(await activityCount(k), 1, reason: 'the finished S02 activity is intact');
    });

    test('/keep-after-DELETE-is-durable (DT-19-15): refused, the delete completes on recovery', () async {
      await revokedRecording(k);
      k.ops.crashAfterPrefix = 'ops.link';
      await k.journal.decideDelete(id1).then((_) {}, onError: (_) {});
      await k.kill();
      expect(decisionText(k), 'DELETE');
      expect(await k.journal.decideKeep(id1), DecisionOutcome.alreadyDecided);
      expect(k.activity.puts, 0, reason: 'the loser does nothing irreversible');
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.filesOf(id1), isEmpty);
      expect(await activityCount(k), 0);
    });

    test('/two-concurrent-keeps-give-one-activity (same journal object)', () async {
      await revokedRecording(k);
      final a = k.journal.decideKeep(id1);
      final b = k.journal.decideKeep(id1);
      await Future.wait([a, b]);
      final h1 = k.journal.handOff(id1);
      final h2 = k.journal.handOff(id1);
      expect(await h1, HandOffResult.done);
      expect(await h2, HandOffResult.done);
      expect(await activityCount(k), 1);
      expect(k.handedOffCount, 1);
    });
  });

  group('DT-19-17 DECISION is created exclusively, durable before anything irreversible', () {
    test('/decision-created-exclusively-never-renamed-over (hard link, and the fallback)', () async {
      await revokedRecording(k);
      k.fs.clearLog();
      await k.journal.decideKeep(id1);
      final text = k.fs.log.map((o) => '${o.kind.name} ${o.path} ${o.to ?? ''}').join('\n');
      expect(text, contains('ops.link '));
      expect(text, contains('/DECISION'));
      expect(k.fs.log.where((o) => o.kind == FsOpKind.rename && (o.to ?? '').endsWith('/DECISION')), isEmpty,
          reason: 'never renamed over');
      expect(k.fs.log.where((o) => (o.kind == FsOpKind.openWrite) && o.path.endsWith('/DECISION')), isEmpty,
          reason: 'DECISION is never written in place');
      expect(k.filesOf(id1).where((f) => f.startsWith('DECISION.')), isEmpty, reason: 'temp file removed');

      final k2 = await RecKit.create(uid: 'user-b');
      k2.ops.linkSupported = false;
      await revokedRecording(k2);
      k2.fs.clearLog();
      expect(await k2.journal.decideDelete(id1), DecisionOutcome.committed);
      // Without hard links the durable temp file is renamed into place while
      // the target is absent: no empty DECISION window (review C6).
      expect(k2.fs.log.where((o) => o.kind == FsOpKind.rename && (o.to ?? '').endsWith('/DECISION')),
          isNotEmpty);
      expect(k2.fs.log.map((o) => o.path), isNot(contains(startsWith('ops.createExclusive'))));
      await k2.dispose();
    });

    test('/file-then-directory-fsync-before-the-first-irreversible-step (Delete and Keep)', () async {
      await revokedRecording(k);
      k.fs.clearLog();
      await k.journal.decideDelete(id1);
      final log = [for (final o in k.fs.log) o.kind == FsOpKind.note ? o.path : '${o.kind.name} ${o.path} ${o.to ?? ''}'];
      final tmpFsync = log.indexWhere((l) => l.startsWith('fsync') && l.contains('DECISION.'));
      final link = log.indexWhere((l) => l.startsWith('ops.link '));
      final dirSync = log.indexWhere((l) => l.startsWith('ops.fsyncDir'));
      final discarding = log.indexWhere((l) => l.startsWith('rename') && l.contains('DISCARDING'));
      final firstDelete = log.indexWhere((l) => l.startsWith('deleteFile') && l.contains('seg-'));
      expect(tmpFsync, isNonNegative);
      expect(tmpFsync, lessThan(link));
      expect(link, lessThan(dirSync));
      expect(dirSync, lessThan(discarding), reason: 'DISCARDING only after both barriers');
      expect(discarding, lessThan(firstDelete));

      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      k2.fs.clearLog();
      await keepFlow(k2);
      final l2 = [for (final o in k2.fs.log) o.kind == FsOpKind.note ? o.path : '${o.kind.name} ${o.path} ${o.to ?? ''}'];
      expect(l2.indexWhere((l) => l.startsWith('ops.link ')), lessThan(l2.indexWhere((l) => l == 'activity.put')));
      expect(l2.indexWhere((l) => l.startsWith('ops.fsyncDir')), lessThan(l2.indexWhere((l) => l == 'activity.put')),
          reason: 'no put before the file fsync and the directory fsync');
      await k2.dispose();
    });

    test('/recovery-reads-the-marker: KEEP completes, DELETE completes, none stays pending', () async {
      // KEEP
      await revokedRecording(k);
      k.put(decisionPath(k), utf('KEEP'));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      // DELETE
      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      k2.put(decisionPath(k2), utf('DELETE'));
      await k2.kill();
      expect(await k2.journal.listUnfinished(), isEmpty);
      expect(k2.filesOf(id1), isEmpty);
      expect(await activityCount(k2), 0);
      // none
      final k3 = await RecKit.create(uid: 'user-c');
      await revokedRecording(k3);
      await k3.kill();
      final r = await k3.journal.listUnfinished();
      expect(r.single.pendingDecision, isTrue);
      expect(await activityCount(k3), 0);
      await k2.dispose();
      await k3.dispose();
    });
  });

  group('DT-19-18 / DT-19-19 forced two-writer interleaving (mutex bypassed)', () {
    Future<(DecisionOutcome?, DecisionOutcome?)> race(
        RecKit x, {required bool aKeep, required bool bKeep, required bool aFirst}) async {
      final (b, bops) = x.journalWithOwnOps();
      final reachedA = Completer<void>(), reachedB = Completer<void>();
      final relA = Completer<void>(), relB = Completer<void>();
      x.ops.beforeLink = () async {
        reachedA.complete();
        await relA.future;
      };
      bops.beforeLink = () async {
        reachedB.complete();
        await relB.future;
      };
      final fa = aKeep ? x.journal.decideKeep(id1) : x.journal.decideDelete(id1);
      final fb = bKeep ? b.decideKeep(id1) : b.decideDelete(id1);
      await reachedA.future;
      await reachedB.future; // both have checked for a marker, neither has created DECISION
      Future<DecisionOutcome?> settleOne(Future<DecisionOutcome> f) =>
          f.then<DecisionOutcome?>((v) => v, onError: (_) => null);
      final ra = settleOne(fa), rb = settleOne(fb);
      if (aFirst) {
        relA.complete();
        final a = await ra;
        relB.complete();
        return (a, await rb);
      }
      relB.complete();
      final bb = await rb;
      relA.complete();
      return (await ra, bb);
    }

    test('/barrier-keep-released-first: Keep wins, Delete does nothing irreversible', () async {
      await revokedRecording(k);
      final (a, b) = await race(k, aKeep: true, bKeep: false, aFirst: true);
      expect(a, DecisionOutcome.committed);
      expect(b, DecisionOutcome.alreadyDecided);
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1), containsAll(['seg-0001.log', 'meta.json', 'SEALED']), reason: 'the loser deleted nothing');
      expect(k.filesOf(id1).where((f) => f.startsWith('DECISION.')), isEmpty);
      await k.journal.handOff(id1);
      expect(await activityCount(k), 1);
    });

    test('/barrier-delete-released-first: Delete wins, Keep does nothing irreversible', () async {
      await revokedRecording(k);
      final (a, b) = await race(k, aKeep: false, bKeep: true, aFirst: true);
      expect(a, DecisionOutcome.committed);
      expect(b, isNot(DecisionOutcome.committed), reason: 'the late Keep never commits after DELETE');
      expect(k.activity.puts, 0);
      expect(await activityCount(k), 0);
      expect(k.filesOf(id1), isEmpty, reason: 'the winner completed the delete; nothing resurrected');
    });

    test('/barrier-delete-first-in-the-other-order (B released first)', () async {
      await revokedRecording(k);
      final (a, b) = await race(k, aKeep: true, bKeep: false, aFirst: false);
      expect(b, DecisionOutcome.committed, reason: 'B (Delete) linked first');
      expect(a, isNot(DecisionOutcome.committed), reason: 'the Keep that linked second is refused');
      expect(k.activity.puts, 0);
      expect(await activityCount(k), 0);
      expect(k.filesOf(id1), isEmpty);
    });

    test('/barrier-two-keeps and /barrier-two-deletes: one DECISION, one winner', () async {
      await revokedRecording(k);
      final (a, b) = await race(k, aKeep: true, bKeep: true, aFirst: true);
      expect(a, DecisionOutcome.committed);
      expect(b, DecisionOutcome.committed, reason: 'the same decision is idempotent');
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1).where((f) => f.startsWith('DECISION')), ['DECISION']);
      await k.journal.handOff(id1);
      expect(await activityCount(k), 1);

      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      final (c, d) = await race(k2, aKeep: false, bKeep: false, aFirst: false);
      expect(d, DecisionOutcome.committed);
      expect(c, anyOf(isNull, DecisionOutcome.committed), reason: 'the second delete must not fail loudly or revive anything');
      expect(k2.filesOf(id1), isEmpty);
      expect(await activityCount(k2), 0);
      await k2.dispose();
    });

    test('/mutex-bypassed-keep-vs-delete: the file alone arbitrates and a rename-based implementation would fail', () async {
      await revokedRecording(k);
      final (a, b) = await race(k, aKeep: false, bKeep: true, aFirst: false);
      // B (Keep) linked first: exactly one winner, no second decision
      expect(b, DecisionOutcome.committed);
      expect(a, isNot(DecisionOutcome.committed));
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1), contains('seg-0001.log'), reason: 'the Delete loser removed nothing');
    });
  });

  group('DT-19-20 a malformed DECISION at recovery is quarantined, never trusted', () {
    for (final (name, bytes) in [
      ('/empty-file-at-recovery', Uint8List(0)),
      ('/truncated-file-at-recovery', utf('KE')),
      ('/unknown-token-at-recovery', utf('MAYBE')),
    ]) {
      test(name, () async {
        await revokedRecording(k);
        k.put(decisionPath(k), bytes);
        await k.kill();
        final before = k.snapshot(id1);
        final r = await k.journal.listUnfinished();
        expect(r.single.status, UnfinishedStatus.quarantined);
        expect(k.bytesOf(decisionPath(k)), bytes, reason: 'the DECISION file is never removed or rewritten');
        final after = k.snapshot(id1);
        for (final e in before.entries) {
          expect(after[e.key], e.value, reason: '${e.key} unchanged');
        }
        expect(after.keys.toSet().difference(before.keys.toSet()), {'${k.dirOf(id1)}/QUARANTINED'});
        expect(await activityCount(k), 0, reason: 'nothing is handed off');
        expect(k.filesOf(id1), contains('seg-0001.log'), reason: 'nothing is deleted');
      });
    }

    test('/fallback publish has no empty window (review C6): the loser sees the whole winner', () async {
      await revokedRecording(k);
      k.ops.linkSupported = false;
      k.fs.clearLog();
      final winner = k.journal.decideKeep(id1);
      final loser = k.journal.decideDelete(id1);
      expect(await winner, DecisionOutcome.committed);
      expect(await loser, DecisionOutcome.alreadyDecided);
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1), contains('seg-0001.log'));
      expect(k.fs.log.where((o) => o.kind == FsOpKind.openWrite && o.path.endsWith('/DECISION')), isEmpty,
          reason: 'DECISION is never opened for writing: it appears whole by rename');
    });
  });

  group('DT-19-21 the full recovery matrix through listUnfinished', () {
    Future<void> build(RecKit x, {String? decision, bool discarding = false}) async {
      await revokedRecording(x);
      if (decision != null) x.put('${x.dirOf(id1)}/DECISION', utf(decision));
      if (discarding) x.put('${x.dirOf(id1)}/DISCARDING', utf('1'));
      await x.kill();
    }

    test('/DELETE-with-DISCARDING: the ordered deletion is completed', () async {
      await build(k, decision: 'DELETE', discarding: true);
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.filesOf(id1), isEmpty);
      expect(await activityCount(k), 0);
    });

    test('/DELETE-without-DISCARDING: DISCARDING is written, then everything is deleted', () async {
      await build(k, decision: 'DELETE');
      k.fs.clearLog();
      expect(await k.journal.listUnfinished(), isEmpty);
      final l = [for (final o in k.fs.log) '${o.kind.name} ${o.path} ${o.to ?? ''}'];
      final disc = l.indexWhere((e) => e.startsWith('rename') && e.contains('DISCARDING'));
      final del = l.indexWhere((e) => e.startsWith('deleteFile') && e.contains('seg-'));
      expect(disc, isNonNegative);
      expect(disc, lessThan(del));
      expect(k.filesOf(id1), isEmpty);
    });

    test('/KEEP-without-DISCARDING: the idempotent hand-off completes, one activity, then cleanup', () async {
      await build(k, decision: 'KEEP');
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);
      expect(k.mem.dirs.contains('${k.dirOf(id1)}.cleanup'), isFalse);
    });

    for (final (name, decision, discarding) in [
      ('/KEEP-with-DISCARDING', 'KEEP', true),
      ('/DISCARDING-without-a-valid-DELETE-decision', null, true),
    ]) {
      test(name, () async {
        await build(k, decision: decision, discarding: discarding);
        final before = k.snapshot(id1);
        final r = await k.journal.listUnfinished();
        expect(r.single.status, UnfinishedStatus.quarantined);
        final after = k.snapshot(id1);
        for (final e in before.entries) {
          expect(after[e.key], e.value, reason: 'bytes unchanged: ${e.key}');
        }
        expect(after.keys.toSet().difference(before.keys.toSet()), {'${k.dirOf(id1)}/QUARANTINED'});
        expect(await activityCount(k), 0, reason: 'no hand-off');
        expect(k.filesOf(id1), contains('seg-0001.log'), reason: 'no delete');
      });
    }

    test('/no-DECISION-and-no-DISCARDING: a pending decision, listed and untouched', () async {
      await build(k);
      final before = k.snapshot(id1);
      final r = await k.journal.listUnfinished();
      expect(r.single.pendingDecision, isTrue);
      expect(k.snapshot(id1), before);
      expect(await activityCount(k), 0);
    });
  });

  group('DT-19-22 / DT-19-23 a DECISION is never removed or replaced while its writer can commit', () {
    test('/recovery-runs-while-the-writer-is-paused (between the temp fsync and the link)', () async {
      await revokedRecording(k);
      final (b, _) = k.journalWithOwnOps();
      final reached = Completer<void>(), release = Completer<void>();
      k.ops.beforeLink = () async {
        reached.complete();
        await release.future;
      };
      final writer = k.journal.decideKeep(id1);
      await reached.future;
      expect(k.bytesOf(decisionPath(k)), isNull, reason: 'nothing published yet');
      final r = await b.listUnfinished(); // recovery while the writer waits
      expect(r.single.pendingDecision, isTrue);
      expect(k.bytesOf(decisionPath(k)), isNull);
      release.complete();
      expect(await writer, DecisionOutcome.committed);
      expect(decisionText(k), 'KEEP', reason: 'the writer committed and won');
    });

    test('/retrying-caller-runs-while-the-writer-is-paused: the DECISION never changes once visible', () async {
      await revokedRecording(k);
      final (b, _) = k.journalWithOwnOps();
      final reached = Completer<void>(), release = Completer<void>();
      k.ops.beforeLink = () async {
        reached.complete();
        await release.future;
      };
      final writer = k.journal.decideKeep(id1);
      await reached.future;
      final retry = await b.decideKeep(id1); // links first, wins
      expect(retry, DecisionOutcome.committed);
      final seen = k.bytesOf(decisionPath(k));
      release.complete();
      await writer;
      expect(k.bytesOf(decisionPath(k)), seen, reason: 'never replaced');
      expect(decisionText(k), 'KEEP');
      expect(k.filesOf(id1).where((f) => f.startsWith('DECISION.')), isEmpty);
    });

    test('DT-19-23 /reader-never-sees-an-empty-decision-with-hard-link-publish', () async {
      await revokedRecording(k);
      final seen = <String?>[];
      k.fs.clearLog();
      // poll DECISION at every journal step
      final sub = Stream<void>.periodic(Duration.zero).listen((_) => seen.add(decisionText(k)));
      await k.journal.decideKeep(id1);
      await sub.cancel();
      seen.add(decisionText(k));
      expect(seen.where((s) => s != null && s != 'KEEP' && s != 'DELETE'), isEmpty,
          reason: 'only absent or whole, never empty or partial');
      expect(k.fs.log.where((o) => o.kind == FsOpKind.write && o.path.endsWith('/DECISION')), isEmpty);
    });

    test('DT-19-23 /fallback-without-hard-link: published by exclusive create, whole to a waiting reader', () async {
      await revokedRecording(k);
      k.ops.linkSupported = false;
      expect(await k.journal.decideDelete(id1), DecisionOutcome.committed);
      expect(k.filesOf(id1), isEmpty);
      final k2 = await RecKit.create(uid: 'user-b');
      k2.ops.linkSupported = false;
      await revokedRecording(k2);
      expect(await k2.journal.decideKeep(id1), DecisionOutcome.committed);
      expect(decisionText(k2), 'KEEP');
      await k2.dispose();
    });

    test('DT-19-23 /journal-lifetime-lock-stays-held and /second-journal-instance-fails-to-open', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      final j2 = k.secondJournal(); // same process-wide lock set
      await expectLater(j2.listUnfinished(), throwsJournalCode('journalLocked'));
      await expectLater(j2.begin(k.meta(recId(2))), throwsJournalCode('journalLocked'));
      expect(k.mem.dirs.contains(k.dirOf(recId(2))), isFalse, reason: 'it records nothing');
    });
  });

  group('DT-19-24 KEEP cleanup is ONE atomic rename after a verified hand-off', () {
    test('/completed-keep-cleanup: verify, rename, parent fsync, then the contents', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.fs.clearLog();
      await k.journal.handOff(id1);
      final l = [for (final o in k.fs.log) o.kind == FsOpKind.note ? o.path : '${o.kind.name} ${o.path} ${o.to ?? ''}'];
      final put = l.indexOf('activity.put');
      final read = l.indexOf('activity.read');
      final ren = l.indexWhere((e) => e.startsWith('ops.renameDir'));
      final fsync = l.indexWhere((e) => e.startsWith('ops.fsyncDir'), ren);
      final del = l.indexWhere((e) => e.startsWith('deleteDir') && e.contains('.cleanup'));
      expect(put, lessThan(read));
      expect(read, lessThan(ren), reason: 'the rename only after the verified hand-off');
      expect(ren, lessThan(fsync));
      expect(fsync, lessThan(del));
      expect(k.filesOf(id1), isEmpty);
      expect(k.mem.dirs.contains(k.dirOf(id1)), isFalse);
      expect(k.mem.dirs.contains('${k.dirOf(id1)}.cleanup'), isFalse);
      expect(await activityCount(k), 1);
    });

    test('/crash-a-after-verification-before-the-rename: nothing deleted, recovery repeats hand-off and rename', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.ops.renameDirError = SimulatedCrash('before rename');
      await k.journal.handOff(id1);
      expect(k.filesOf(id1), containsAll(['DECISION', 'meta.json', 'SEALED', 'seg-0001.log']));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);
    });

    test('/crash-b-after-the-rename-before-any-content-deletion', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.ops.crashAfterPrefix = 'ops.renameDir';
      await k.journal.handOff(id1);
      expect(k.mem.dirs.contains(k.dirOf(id1)), isFalse);
      expect(k.mem.dirs.contains('${k.dirOf(id1)}.cleanup'), isTrue);
      final puts = k.activity.puts;
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.mem.dirs.contains('${k.dirOf(id1)}.cleanup'), isFalse);
      expect(await activityCount(k), 1);
      expect(k.activity.puts, 0, reason: 'a fresh process makes no put for the garbage ($puts before)');
    });

    test('/crash-c-after-meta-json-removal-inside-the-cleanup-directory and /crash-d-before-the-final-directory-removal', () async {
      await revokedRecording(k);
      await k.journal.decideKeep(id1);
      k.ops.crashAfterPrefix = 'ops.renameDir';
      await k.journal.handOff(id1);
      final tomb = '${k.dirOf(id1)}.cleanup';
      // c: meta.json already removed inside the cleanup directory
      k.mem.files.remove('$tomb/meta.json');
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.mem.dirs.contains(tomb), isFalse);
      expect(await activityCount(k), 1);
      // d: everything removed, only the empty directory is left
      final k2 = await RecKit.create(uid: 'user-b');
      await revokedRecording(k2);
      await k2.journal.decideKeep(id1);
      k2.ops.crashAfterPrefix = 'ops.renameDir';
      await k2.journal.handOff(id1);
      final t2 = '${k2.dirOf(id1)}.cleanup';
      k2.mem.files.removeWhere((f, _) => f.startsWith('$t2/'));
      await k2.kill();
      expect(await k2.journal.listUnfinished(), isEmpty);
      expect(k2.mem.dirs.contains(t2), isFalse);
      expect(await activityCount(k2), 1);
      await k2.dispose();
    });
  });

  test('DT-19-25 a .cleanup directory at recovery is deleted: no owner check, no hand-off, no activity', () async {
    final base = '${k.recDir}';
    await k.journal.listUnfinished(); // creates the scope directories
    // with meta.json (claiming ANOTHER scope) and without it
    await k.mem.createDir('$base/${recId(7)}.cleanup');
    k.put('$base/${recId(7)}.cleanup/meta.json', utf('not even valid'));
    k.put('$base/${recId(7)}.cleanup/seg-0001.log', Uint8List(40));
    await k.mem.createDir('$base/${recId(8)}.cleanup');
    k.put('$base/${recId(8)}.cleanup/seg-0001.log', Uint8List(40));
    k.put('$base/${recId(8)}.cleanup/DECISION', utf('KEEP'));
    final r = await k.journal.listUnfinished();
    expect(r, isEmpty);
    expect(k.mem.dirs.where((d) => d.endsWith('.cleanup')), isEmpty);
    expect(await activityCount(k), 0, reason: 'no activity is created for garbage');
    expect(k.activity.puts, 0);
  });
}
