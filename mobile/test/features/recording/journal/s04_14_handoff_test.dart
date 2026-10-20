// S04-14 Finish hand-off (EP-D). Rows DT-14-1..8, 10..12 of
// docs/phase2/s04/S04_TEST_PLAN.md. Oracle: Design 4.3 (ordered steps, crash
// analysis "never neither copy"), not the code. DT-14-9 (190 000 sample cap) is a
// controller row and is reported NOT_RUN by this group.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import 'journal_kit.dart';

class ThrowingRunner extends HeavyWorkRunner {
  const ThrowingRunner();
  @override
  Future<R> run<P, R>(R Function(P input) fn, P input) async =>
      throw StateError('worker crashed 12.3456789');
}

/// Killed run + user presses Finish: seal (user) then hand off.
Future<void> prepRun(RecKit k) async {
  await k.record(recId(1), 6);
}

Future<void> stop(RecKit k) async {
  await k.journal.flush();
  await k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedBattery, 6500));
  await k.journal.seal(recId(1), const SealRequest(reason: StopReason.battery));
  await k.journal.handOff(recId(1));
}

/// Final-state invariant of the hand-off window (S04-R-018 AC): never neither
/// copy and never both (a restart has completed the silent finish).
Future<void> expectOneCopy(RecKit k, {required String why}) async {
  final offered = await k.journal.listUnfinished();
  final acts = await activityCount(k);
  final dirLeft = k.filesOf(recId(1)).isNotEmpty;
  if (offered.isNotEmpty) {
    expect(offered.single.status, UnfinishedStatus.readable, reason: why);
    expect(offered.single.sampleCount, 6, reason: '$why: the recording is whole');
    expect(acts, 0, reason: '$why: offered AND stored would be two copies');
  } else {
    expect(acts, 1, reason: '$why: neither copy is data loss');
    expect(dirLeft, isFalse, reason: '$why: the finished recording is cleaned up');
  }
}

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  test('DT-14-1 Stop order: flush, stop event, SEALED, put, verify read, delete directory, revision bump', () async {
    await prepRun(k);
    k.fs.clearLog();
    k.fs.note('STEP flush');
    await k.journal.flush();
    k.fs.note('STEP stop-event');
    await k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedBattery, 6500));
    k.fs.note('STEP seal');
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.battery));
    k.fs.note('STEP hand-off');
    await k.journal.handOff(recId(1));
    final log = k.fs.log.map((o) => o.kind == FsOpKind.note ? o.path : '${o.kind.name} ${o.path}${o.to == null ? '' : ' -> ${o.to}'}').toList();
    int at(bool Function(String) f, [int from = 0]) => log.indexWhere(f, from);
    final stopEvent = at((l) => l == 'STEP stop-event');
    final sealedRename = at((l) => l.startsWith('rename') && l.endsWith('/SEALED'), stopEvent);
    final lastSegFsync = log.lastIndexWhere((l) => l.startsWith('fsync') && l.contains('seg-0001.log'), sealedRename);
    final put = at((l) => l == 'activity.put');
    final read = at((l) => l == 'activity.read');
    final cleanupRename = at((l) => l == 'ops.renameDir ${k.dirOf(recId(1))} -> ${k.dirOf(recId(1))}.cleanup');
    final cleanupDelete = at((l) => l.startsWith('deleteDir') && l.endsWith('.cleanup'));
    expect(stopEvent, isNonNegative);
    expect(lastSegFsync, isNonNegative);
    expect(lastSegFsync, lessThan(sealedRename), reason: 'last flush (fsync) before SEALED');
    expect(sealedRename, isNonNegative);
    expect(sealedRename, lessThan(put), reason: 'SEALED before the put');
    expect(put, lessThan(read), reason: 'verify read after the put');
    expect(read, lessThan(cleanupRename), reason: 'the journal is deleted only after the verified put');
    expect(cleanupRename, lessThan(cleanupDelete));
    expect(k.handedOffCount, 1, reason: 'revision bump after the cleanup');
    expect(k.filesOf(recId(1)), isEmpty);
  });

  group('DT-14-2 crash at every step of the hand-off window', () {
    test('exhaustive: a crash after EVERY file operation ends in exactly one copy', () async {
      final ops = (await opsOf(prepRun, stop)).where((o) => o.kind != FsOpKind.note).toList();
      expect(ops.length, greaterThan(20));
      var offered = 0, finished = 0;
      for (final o in ops) {
        final c = await crashRun(prepRun, stop, o.index);
        await expectOneCopy(c, why: 'crash after $o');
        if ((await c.journal.listUnfinished()).isNotEmpty) {
          offered++;
          // the user finishes the offered recording: ends in exactly one session
          expect(await c.finish(recId(1), reason: StopReason.user), HandOffResult.done);
        } else {
          finished++;
        }
        expect(await activityCount(c), 1, reason: 'crash after $o: exactly one activity at the end');
        expect(c.filesOf(recId(1)), isEmpty);
        await c.dispose();
      }
      // Since review C15 a crash after the stop event is re-sealed and finished at
      // recovery, so no crash point of this window need remain offered.
      expect(offered, greaterThanOrEqualTo(0));
      expect(finished, greaterThan(0), reason: 'late crash points finish silently');
    });

    test('/after-step: a stop event without SEALED is re-sealed with its reason and finished (review C15)', () async {
      await prepRun(k);
      await k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedBattery, 6500));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(recId(1)), isEmpty);
    });

    test('/after-step SEALED, no stored session: re-run from step 3, silently', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(recId(1)), isEmpty);
      expect(k.handedOffCount, 1);
    });

    test('/after-put: SEALED plus stored id, silent delete after verify, one activity', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      k.activity.crashAfterPut = SimulatedCrash('after put');
      expect(await k.journal.handOff(recId(1)), HandOffResult.failedKept);
      expect(await activityCount(k), 1, reason: 'the put committed before the crash');
      expect(k.filesOf(recId(1)), contains('SEALED'));
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 1);
      expect(k.filesOf(recId(1)), isEmpty);
    });

    test('/after-rename-to-cleanup: the garbage directory is finished, one activity', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      k.ops.crashAfterPrefix = 'ops.renameDir';
      // The activity is verified; a failing cleanup does not undo it (review C9).
      expect(await k.journal.handOff(recId(1)), HandOffResult.done);
      expect(k.mem.dirs.contains('${k.dirOf(recId(1))}.cleanup'), isTrue);
      await k.kill();
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.mem.dirs.contains('${k.dirOf(recId(1))}.cleanup'), isFalse);
      expect(await activityCount(k), 1);
    });
  });

  group('DT-14-3 a failed save keeps the journal', () {
    for (final (name, err) in [
      ('/storage-full', JournalStorageFullException('full')),
      ('/key-unavailable', JournalKeyUnavailable('key')),
      ('/io', FileSystemException('io', '/x')),
    ]) {
      test(name, () async {
        await prepRun(k);
        await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
        final before = k.snapshot(recId(1));
        k.activity.putError = err;
        expect(await k.journal.handOff(recId(1)), HandOffResult.failedKept);
        expect(k.snapshot(recId(1)), before, reason: 'journal kept, byte for byte');
        expect(await activityCount(k), 0);
        expect(k.handedOffCount, 0, reason: 'never a claim of saved');
        // retry once per tap: the next tap works when the store works again
        k.activity.putError = null;
        expect(await k.journal.handOff(recId(1)), HandOffResult.done);
        expect(await activityCount(k), 1);
        expect(k.handedOffCount, 1);
      });
    }
  });

  group('DT-14-4 one hand-off in flight', () {
    test('/double-tap-finish: two concurrent hand-offs make one session', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      final gate = k.activity.putGate = Completer<void>();
      final a = k.journal.handOff(recId(1));
      final b = k.journal.handOff(recId(1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(k.activity.maxInFlight, 1, reason: 'one hand-off in flight');
      gate.complete();
      expect(await a, HandOffResult.done);
      expect(await b, HandOffResult.done);
      expect(k.activity.puts, 1);
      expect(await activityCount(k), 1);
    });

    test('/re-put-after-crash: an identical re-put is a no-op', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      k.activity.crashAfterPut = SimulatedCrash('x');
      await k.journal.handOff(recId(1));
      final first = (await k.activityReal.list()).single;
      k.activity.crashAfterPut = null;
      await k.kill();
      // a second hand-off attempt after the crash builds the same record
      expect(await k.journal.handOff(recId(1)), HandOffResult.done);
      final all = await k.activityReal.list();
      expect(all, hasLength(1));
      expect(all.single.generation, first.generation, reason: 'no new generation: the re-put is a no-op');
    });
  });

  test('DT-14-5 verify returns absent or throws: the directory is NOT deleted', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.activity.readAbsent = true;
    expect(await k.journal.handOff(recId(1)), HandOffResult.failedKept);
    expect(k.filesOf(recId(1)), containsAll(['meta.json', 'SEALED', 'seg-0001.log']));
    expect(k.handedOffCount, 0);
  });

  test('DT-14-5 verify read throws: the directory is NOT deleted', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.activity.readError = JournalIoException('stream lost');
    expect(await k.journal.handOff(recId(1)), HandOffResult.failedKept);
    expect(k.filesOf(recId(1)), containsAll(['meta.json', 'SEALED', 'seg-0001.log']));
    expect(k.handedOffCount, 0);
  });

  test('DT-14-5 a stored activity whose streams were lost does not allow the cleanup', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.activity.crashAfterPut = SimulatedCrash('after put');
    await k.journal.handOff(recId(1));
    final streams = k.mem.files.keys.where((f) => f.endsWith('streams.bin')).toList();
    expect(streams, hasLength(1));
    k.mem.files.remove(streams.single); // the stored streams are gone
    await k.kill();
    final probe = await k.activityReal.read(nativeActivityId(recId(1)));
    final lost = probe == null || probe.streamLost || !probe.streamsLoaded;
    // ignore: avoid_print
    print('DT-14-5 probe: null=${probe == null} streamLost=${probe?.streamLost} loaded=${probe?.streamsLoaded}');
    expect(lost, isTrue, reason: 'precondition: the stored copy has lost its streams');
    k.activity.crashAfterPut = null;
    await k.journal.handOff(recId(1));
    // design 4.3 step 5: verified = entry exists AND is not streamLost
    final left = k.filesOf(recId(1));
    final after = await k.activityReal.read(nativeActivityId(recId(1)));
    final stillLost = after == null || after.streamLost || !after.streamsLoaded;
    expect(left.isNotEmpty || !stillLost, isTrue,
        reason: 'the recording is deleted while the only stored copy has lost its streams');
  });

  test('DT-14-6 the produced session: id, provenance, sport, times, versions', () async {
    await prepRun(k);
    final t0 = k.nowMs;
    expect(await k.finish(recId(1), lastOffsetMs: 6000), HandOffResult.done);
    final s = k.activity.lastPut!;
    expect(s.id, nativeActivityId(recId(1)));
    expect(s.sport.name, 'running');
    expect(s.startUtc, DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true));
    expect(s.endUtc.difference(s.startUtc).inMilliseconds, 6000);
    expect(s.utcOffsetMinutes, 60);
    expect(s.formulaVersion, '$kCalculatorVersionPrefix.$kSmoothingAlgorithmId');
    expect(s.metricDefinitionVersion, isNotEmpty);
    final p = s.provenance.single;
    final want = nativeSourceRecord(recordingUuid: recId(1), importedAt: p.importedAt);
    expect(p.sourceId, want.sourceId);
    expect(p.externalId, want.externalId);
    expect(p.externalId, recId(1));
    expect(p.fieldsContributed, ['gps']);
  });

  test('DT-14-7 the worker throws: journal kept, bare error, no exception out', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.runnerOverride = const ThrowingRunner();
    await k.kill();
    final before = k.snapshot(recId(1));
    HandOffResult? r;
    Object? err;
    try {
      r = await k.journal.handOff(recId(1));
    } catch (e) {
      err = e;
    }
    expect(err, isNull, reason: 'the UI isolate sees no exception');
    expect(r, HandOffResult.failedKept);
    expect(k.snapshot(recId(1)), before);
    // seal with a throwing worker: a bare code, no message with the cause
    final k2 = await RecKit.create(uid: 'user-b');
    await prepRun(k2);
    k2.runnerOverride = const ThrowingRunner();
    await k2.kill();
    await expectLater(
        k2.journal.seal(recId(1), const SealRequest(reason: StopReason.user)),
        throwsA(isA<RecordingJournalError>().having((e) => e.toString(), 'text',
            allOf(isNot(contains('12.3456789')), isNot(contains('worker'))))));
    expect(k2.filesOf(recId(1)), isNot(contains('SEALED')));
    await k2.dispose();
    // recovery with a healthy worker offers the same data again
    k.runnerOverride = null;
    await k.kill();
    expect(await k.journal.handOff(recId(1)), HandOffResult.done);
  });

  test('DT-14-8 the revision is bumped once on success and not on a failure', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.activity.putError = StateError('x');
    await k.journal.handOff(recId(1));
    expect(k.handedOffCount, 0);
    k.activity.putError = null;
    await k.journal.handOff(recId(1));
    expect(k.handedOffCount, 1);
    await k.journal.handOff(recId(1)); // nothing left: failedKept, no extra bump
    expect(k.handedOffCount, 1);
  });

  group('DT-14-10 owner scope', () {
    test('an account switch during stopping writes nothing for the new account', () async {
      await prepRun(k);
      final ownerScope = k.scopeId;
      k.uid = 'user-b';
      // seal and hand-off look under the NEW account only: the recording is not there
      await expectLater(k.journal.seal(recId(1), const SealRequest(reason: StopReason.user)),
          throwsA(isA<RecordingJournalError>()));
      expect(await k.journal.handOff(recId(1)), HandOffResult.failedKept);
      expect(k.activity.puts, 0);
      expect(k.mem.files.keys.where((f) => f.contains(recId(1)) && !f.contains(ownerScope)), isEmpty);
      // a late flush under the other account is refused and reported
      k.journal.enqueueSample(smp(50), GateCounters.zero);
      await k.journal.flush();
      await Future<void>.delayed(Duration.zero);
      expect(k.faults, contains(JournalFault.ownerScopeLost));
      k.uid = 'user-a';
      expect(k.sampleCountOnDisk(recId(1)), 6);
      k.uid = 'user-b';
      // the owner is back: the hand-off lands
      k.uid = 'user-a';
      expect(await k.finish(recId(1)), HandOffResult.done);
      expect(await activityCount(k), 1);
    });
  });

  test('DT-14-11 a tombstoned activity is not re-created, the directory still goes', () async {
    await prepRun(k);
    await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
    k.activity.crashAfterPut = SimulatedCrash('x');
    await k.journal.handOff(recId(1));
    expect(await activityCount(k), 1);
    await k.activityReal.delete(nativeActivityId(recId(1))); // the user deletes it
    k.activity.crashAfterPut = null;
    expect(await k.journal.handOff(recId(1)), HandOffResult.tombstoned,
        reason: 'nothing was saved: a distinct result (review C9)');
    expect(await activityCount(k), 0, reason: 'the activity is NOT re-created');
    expect((await k.activityReal.listTombstones()), hasLength(1));
    expect(k.filesOf(recId(1)), isEmpty, reason: 'step 6 still deletes the recording directory');
  });

  group('DT-14-12 SEALED is written once', () {
    test('/stop-event-without-sealed-reseals-once: a second seal changes nothing', () async {
      await prepRun(k);
      await k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedBattery, 6500));
      await k.kill();
      k.clock.advance(const Duration(minutes: 1));
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.battery));
      final first = k.bytesOf('${k.dirOf(recId(1))}/SEALED')!;
      final plain1 = jsonDecode(utf8.decode(k.cipher().open(first))) as Map<String, dynamic>;
      expect(plain1['reason'], 'battery');
      expect(plain1['imported'], k.nowMs);
      k.clock.advance(const Duration(hours: 3));
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      expect(k.bytesOf('${k.dirOf(recId(1))}/SEALED'), first, reason: 'sealed once, immutable');
    });

    test('/importedAt-reused-on-repeat: the repeated hand-off builds the same provenance', () async {
      await prepRun(k);
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      final sealedAt = k.nowMs;
      k.activity.crashBeforePut = SimulatedCrash('before put');
      await k.journal.handOff(recId(1));
      expect(await activityCount(k), 0);
      k.activity.crashBeforePut = null;
      k.clock.advance(const Duration(hours: 5));
      await k.kill();
      expect(await k.journal.handOff(recId(1)), HandOffResult.done);
      final p = k.activity.lastPut!.provenance.single;
      expect(p.importedAt.millisecondsSinceEpoch, sealedAt, reason: 'importedAt is fixed once at SEALED');
    });
  });
}
