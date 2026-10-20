// S04-12 Recovery offer and resume, S04-13 Recovery failed is honest (EP-D).
// Rows DT-12-1..5, 11..13 and DT-13-1, 2, 5, 7 of docs/phase2/s04/S04_TEST_PLAN.md
// at the journal level (listUnfinished, openForResume, seal, hand-off,
// decideDelete, quarantine). The rows that need the controller or widgets
// (DT-12-6..10, 12-14, 13-3, 13-4, 13-6, 13-8) belong to other groups.
// Oracle: Design 4.3 and 4.5 (recovery table, ordered delete), not the code.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import 'journal_kit.dart';

/// begin + samples 1..[n] + flush, then the process dies.
Future<void> killedRun(RecKit k, String id, {int n = 8}) async {
  await k.record(id, n);
  await k.kill();
}

Future<T> noUncaught<T>(Future<T> Function() body, List<Object> errors) {
  final c = Completer<T>();
  runZonedGuarded(() async {
    try {
      c.complete(await body());
    } catch (e, s) {
      if (!c.isCompleted) c.completeError(e, s);
    }
  }, (e, s) => errors.add(e));
  return c.future;
}

Uint8List utf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  group('DT-12-1 the offer', () {
    test('/offer: a killed run is listed readable with its facts and blocks Start', () async {
      final t0 = k.nowMs;
      await killedRun(k, recId(1), n: 8);
      final r = await k.journal.listUnfinished();
      expect(r, hasLength(1));
      final u = r.single;
      expect(u.recordingId, recId(1));
      expect(u.status, UnfinishedStatus.readable);
      expect(u.startUtcMs, t0);
      expect(u.sampleCount, 8);
      expect(u.lastOffsetMs, 8000);
      expect(u.sport, isNotNull);
      expect(u.blocksStart, isTrue);
    });

    test('/start-blocked: every status but quarantined blocks Start', () async {
      for (final s in UnfinishedStatus.values) {
        final u = UnfinishedRecording(recordingId: 'x', status: s);
        expect(u.blocksStart, s != UnfinishedStatus.quarantined, reason: s.name);
      }
    });
  });

  group('DT-12-2 resume, save as finished, discard', () {
    test('/resume: same uuid, new segment, restart event, gap pair; the gap counts neither time nor distance', () async {
      await killedRun(k, recId(1), n: 10);
      k.clock.advance(const Duration(minutes: 5));
      final rec = await k.journal.openForResume(recId(1));
      expect(rec.meta.recordingId, recId(1));
      expect(rec.meta.ownerUid, 'user-a');
      expect(rec.keptCount, 10);
      expect(rec.lastOffsetMs, 10000);
      expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
      final f2 = k.frames(recId(1), 2);
      expect(f2.map((f) => f['e']).toList(), ['segmentBreak', 'restart', 'gapStart', 'gapEnd']);
      final restartAt = f2[1]['o'] as int;
      expect(restartAt, greaterThanOrEqualTo(5 * 60 * 1000));
      expect(f2[2]['o'], 10000, reason: 'gap starts at the last journaled offset');
      expect(f2[3]['o'], restartAt, reason: 'gap ends at the restart offset');

      // first fix after the restart is 1.1 km away: crossing the gap must not count
      k.journal.enqueueSample(
          PipelineSample(offsetMs: restartAt + 1000, lat: 47.01, lon: 8.0, accuracyM: 5, altitudeM: 400, speedMps: 3),
          GateCounters.zero);
      await k.journal.flush();
      final before = rec.distanceM;
      expect(before, greaterThan(20));
      expect(before, lessThan(60));
      expect(await k.finish(recId(1)), HandOffResult.done);
      final s = (await k.activityReal.read(nativeActivityId(recId(1))))!.session;
      expect(s.summary.distanceM!, lessThan(100), reason: 'the 1.1 km jump across the gap is not distance');
      expect(s.movingTimeS!, lessThan(30), reason: 'the 5 minute gap is not moving time');
    });

    test('/save-as-finished: seal and hand-off give exactly one session and clean the journal', () async {
      await killedRun(k, recId(1), n: 6);
      expect(await k.finish(recId(1)), HandOffResult.done);
      final list = await k.activityReal.list();
      expect(list, hasLength(1));
      expect(list.single.id, nativeActivityId(recId(1)));
      expect(k.filesOf(recId(1)), isEmpty);
      expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.handedOffCount, 1);
    });

    test('/discard: the directory is removed and the file listing is empty', () async {
      await killedRun(k, recId(1), n: 6);
      expect(await k.journal.decideDelete(recId(1)), DecisionOutcome.committed);
      expect(k.treeFiles().where((f) => f.contains(recId(1))), isEmpty);
      expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(await activityCount(k), 0, reason: 'a discard never creates an activity');
    });
  });

  test('DT-12-3 readable journal with no kept fix: silent delete, no offer', () async {
    await k.journal.begin(k.meta(recId(1)));
    await k.journal.appendEvent(const JournalEvent(JournalEventKind.pause, 500));
    await k.kill();
    expect(await k.journal.listUnfinished(), isEmpty);
    expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
    expect(k.treeFiles().where((f) => f.contains(recId(1))), isEmpty);
    // begin only (no frame at all)
    await k.journal.begin(k.meta(recId(2)));
    await k.kill();
    expect(await k.journal.listUnfinished(), isEmpty);
    expect(k.mem.dirs.contains(k.dirOf(recId(2))), isFalse);
  });

  group('DT-12-4 killed while paused', () {
    for (final auto in [false, true]) {
      test(auto ? '/killed-while-auto-paused' : '/killed-while-manual-paused', () async {
        Future<void> run(RecKit x) async {
          await x.journal.begin(x.meta(recId(1)));
          for (var i = 1; i <= 8; i++) {
            x.journal.enqueueSample(smp(i), GateCounters.zero);
          }
          await x.journal.appendEvent(JournalEvent(
              auto ? JournalEventKind.autoPause : JournalEventKind.pause, 8500));
          await x.kill();
        }

        // oracle: the values of the SAME journal finished without any resume
        final ref = await RecKit.create();
        await run(ref);
        expect(await ref.finish(recId(1)), HandOffResult.done);
        final refS = (await ref.activityReal.read(nativeActivityId(recId(1))))!.session;
        await ref.dispose();

        await run(k);
        k.clock.advance(const Duration(minutes: 10));
        final rec = await k.journal.openForResume(recId(1));
        expect(rec.distanceM, closeTo(refS.summary.distanceM!, 1e-6),
            reason: 'the recovered distance is unchanged by the recovery');
        expect(rec.movingTimeMs, (refS.movingTimeS! * 1000).round(),
            reason: 'the recovered moving time is unchanged by the recovery');
        // the pause origin and offset are preserved in the journal
        final seg1Kinds = k.frames(recId(1), 1).where((f) => f['k'] == 'e').map((f) => f['e']).toList();
        expect(seg1Kinds, [auto ? 'autoPause' : 'pause']);
        expect(k.frames(recId(1), 1).last['o'], 8500);
        // a restart gap pair is journaled and adds neither time nor distance
        final f2 = k.frames(recId(1), 2);
        expect(f2.map((f) => f['e']).toList(), ['segmentBreak', 'restart', 'gapStart', 'gapEnd']);
        // finish at once: nothing was added by the interrupted interval
        expect(await k.finish(recId(1)), HandOffResult.done);
        final s = (await k.activityReal.read(nativeActivityId(recId(1))))!.session;
        expect(s.summary.distanceM!, closeTo(refS.summary.distanceM!, 1e-6));
        expect(s.movingTimeS!, closeTo(refS.movingTimeS!, 1e-6),
            reason: 'the 10 minute interruption is not moving time');
      });
    }
  });

  group('DT-12-5 any gap is resumable', () {
    for (final (name, d) in [
      ('/gap-5-min', const Duration(minutes: 5)),
      ('/gap-2-hours', const Duration(hours: 2)),
    ]) {
      test(name, () async {
        await killedRun(k, recId(1), n: 6);
        final list = await k.journal.listUnfinished();
        expect(list.single.status, UnfinishedStatus.readable);
        // the age can be shown from startUtcMs and lastOffsetMs
        k.clock.advance(d);
        final age = k.nowMs - (list.single.startUtcMs! + list.single.lastOffsetMs!);
        expect(age, greaterThanOrEqualTo(d.inMilliseconds - 6000));
        final rec = await k.journal.openForResume(recId(1));
        expect(rec.keptCount, 6);
        final f2 = k.frames(recId(1), 2);
        expect(f2[1]['e'], 'restart');
        expect(f2[1]['o'] as int, greaterThanOrEqualTo(d.inMilliseconds));
        expect(f2[2]['e'], 'gapStart');
        expect(f2[3]['e'], 'gapEnd');
        expect(await k.finish(recId(1)), HandOffResult.done);
        final s = (await k.activityReal.read(nativeActivityId(recId(1))))!.session;
        expect(s.movingTimeS!, lessThan(20), reason: 'the gap is neither interpolated nor counted');
        expect(s.summary.distanceM!, lessThan(60));
      });
    }
  });

  test('DT-12-11 starting the app twice without choosing gives the same offer and changes nothing', () async {
    await killedRun(k, recId(1), n: 5);
    final before = k.snapshot(recId(1));
    final a = await k.journal.listUnfinished();
    await k.kill();
    final b = await k.journal.listUnfinished();
    expect(b.map((e) => e.recordingId), a.map((e) => e.recordingId));
    expect(b.single.sampleCount, a.single.sampleCount);
    expect(k.snapshot(recId(1)), before, reason: 'reading never changes the journal');
    expect(await k.journal.listUnfinished(), hasLength(1), reason: 'no duplicate');
  });

  test('DT-12-12 two unfinished recordings: deterministic order, none hidden, none deleted', () async {
    await killedRun(k, recId(1), n: 4);
    await killedRun(k, recId(2), n: 5);
    final a = await k.journal.listUnfinished();
    final b = await k.journal.listUnfinished();
    expect(a.map((e) => e.recordingId).toSet(), {recId(1), recId(2)});
    expect(b.map((e) => e.recordingId).toList(), a.map((e) => e.recordingId).toList(),
        reason: 'the order is deterministic');
    expect(a.every((e) => e.status == UnfinishedStatus.readable), isTrue);
    expect(k.filesOf(recId(1)), isNotEmpty);
    expect(k.filesOf(recId(2)), isNotEmpty);
  });

  group('DT-12-13 discard with a crash after each ordered step', () {
    Future<void> prep(RecKit x) => killedRun(x, recId(1), n: 5);
    Future<void> act(RecKit x) => x.journal.decideDelete(recId(1));

    test('meta.json is the last file to go; DISCARDING is plain and first', () async {
      final ops = await opsOf(prep, act);
      final dels = ops.where((o) => o.kind == FsOpKind.deleteFile).map((o) => o.path.split('/').last).toList();
      expect(dels.last, 'meta.json');
      expect(dels.indexOf('meta.json'), dels.length - 1);
      final discardRename = ops.indexWhere((o) => o.kind == FsOpKind.rename && (o.to ?? '').endsWith('DISCARDING'));
      final firstDelete = ops.indexWhere((o) => o.kind == FsOpKind.deleteFile && o.path.contains('seg-'));
      expect(discardRename, isNonNegative);
      expect(discardRename, lessThan(firstDelete), reason: 'DISCARDING before any deletion');
      expect(ops.last.kind == FsOpKind.deleteDir || ops.any((o) => o.kind == FsOpKind.deleteDir), isTrue);
    });

    test('every crash point: the next listUnfinished never offers a leftover and no sample stays', () async {
      final ops = await opsOf(prep, act);
      final real = ops.where((o) => o.kind != FsOpKind.note).toList();
      expect(real.length, greaterThan(10));
      var durableCases = 0, intactCases = 0;
      for (final o in real) {
        final c = await crashRun(prep, act, o.index);
        final dir = c.dirOf(recId(1));
        final decisionDurable = c.mem.files.containsKey('$dir/DECISION') &&
            utf8.decode(c.mem.files['$dir/DECISION']!) == 'DELETE';
        final r = await c.journal.listUnfinished();
        final left = c.filesOf(recId(1));
        if (decisionDurable) {
          durableCases++;
          expect(r, isEmpty, reason: 'crash after ${o} with DELETE durable: nothing offered');
          expect(left.where((f) => f.startsWith('seg-') || f == 'meta.json' || f == 'SEALED'), isEmpty,
              reason: 'crash after $o: no sample or meta may stay');
          expect(left, isEmpty, reason: 'crash after $o: the whole directory is completed away');
        } else if (r.isNotEmpty) {
          intactCases++;
          expect(r.single.status, UnfinishedStatus.readable, reason: 'crash before the decision: intact, not damaged');
          expect(r.single.sampleCount, 5, reason: 'crash after $o before DECISION: nothing was lost');
        } else {
          // nothing durable and nothing offered is only valid when nothing is left either
          expect(left.where((f) => f.startsWith('seg-')), isEmpty, reason: 'crash after $o');
        }
        expect(await activityCount(c), 0);
        await c.dispose();
      }
      expect(durableCases, greaterThan(5));
      expect(intactCases, greaterThan(0));
    });

    test('/delete-works-when-the-key-is-lost (DISCARDING and DECISION are plain)', () async {
      await prep(k);
      k.keys[k.scopeId]!.forget();
      await k.kill();
      expect(await k.journal.decideDelete(recId(1)), DecisionOutcome.committed);
      expect(k.filesOf(recId(1)), isEmpty);
      expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
      // the same through recovery: key lost, DECISION=DELETE already on disk
      final k2 = await RecKit.create(uid: 'user-b');
      await killedRun(k2, recId(2), n: 3);
      final d = k2.dirOf(recId(2));
      k2.put('$d/DECISION', utf('DELETE'));
      k2.keys[k2.scopeId]!.forget();
      await k2.kill();
      expect(await k2.journal.listUnfinished(), isEmpty);
      expect(k2.filesOf(recId(2)), isEmpty);
      await k2.dispose();
    });
  });

  group('DT-13-1 recoveryFailed is honest', () {
    Future<void> prepare() => killedRun(k, recId(1), n: 6);

    Future<void> expectFailed(String why) async {
      final before = k.snapshot(recId(1));
      final errors = <Object>[];
      final r = await noUncaught(() => k.journal.listUnfinished(), errors);
      expect(errors, isEmpty, reason: why);
      expect(r, hasLength(1), reason: why);
      expect(r.single.status, UnfinishedStatus.unreadable, reason: why);
      expect(r.single.sampleCount, isNull, reason: '$why: no track shown');
      expect(r.single.blocksStart, isTrue);
      expect(k.snapshot(recId(1)), before, reason: '$why: bytes unchanged');
      // repeated: still the same, still untouched
      final r2 = await k.journal.listUnfinished();
      expect(r2.single.status, UnfinishedStatus.unreadable, reason: why);
      expect(k.snapshot(recId(1)), before, reason: why);
    }

    String meta() => '${k.dirOf(recId(1))}/meta.json';

    test('/truncated-meta', () async {
      await prepare();
      final b = k.bytesOf(meta())!;
      k.put(meta(), Uint8List.sublistView(b, 0, b.length ~/ 2));
      await expectFailed('truncated meta');
    });

    test('/zero-meta', () async {
      await prepare();
      k.put(meta(), Uint8List(0));
      await expectFailed('zero meta');
    });

    test('/schema-v2', () async {
      await prepare();
      k.put(meta(), k.cipher().seal(utf(jsonEncode({
        'v': 2, 'id': recId(1), 't0': 1, 'tz': 0, 'sport': 'running', 'ap': true,
        'scope': k.scopeId, 'uid': 'user-a',
      }))));
      await expectFailed('schema v2');
    });

    test('/meta-tag-fails', () async {
      await prepare();
      final b = Uint8List.fromList(k.bytesOf(meta())!);
      b[b.length - 3] ^= 0x01;
      k.put(meta(), b);
      await expectFailed('meta tag');
    });

    test('/key-unavailable (the key is lost)', () async {
      await prepare();
      k.keys[k.scopeId]!.forget();
      await k.kill();
      await expectFailed('key lost');
    });

    test('/key-unavailable (the secure store throws): never reported as recovered', () async {
      await prepare();
      final before = k.snapshot(recId(1));
      k.keyOverride = (_) => ThrowingKeys0();
      await k.kill();
      final errors = <Object>[];
      Object? thrown;
      List<UnfinishedRecording>? r;
      try {
        r = await noUncaught(() => k.journal.listUnfinished(), errors);
      } catch (e) {
        thrown = e;
      }
      expect(errors, isEmpty);
      if (r != null) {
        expect(r.every((e) => e.status != UnfinishedStatus.readable), isTrue);
      } else {
        expect(thrown, isNotNull);
      }
      expect(k.snapshot(recId(1)), before);
    });

    test('/segments-no-meta', () async {
      await prepare();
      k.mem.files.remove(meta());
      await expectFailed('segments without meta');
    });

    test('/mid-log-bit-flip: no partial offer', () async {
      await prepare();
      // three frames, then flip a payload byte of the FIRST (not the tail)
      await k.kill();
      await k.journal.openForResume(recId(1));
      k.journal.enqueueSample(smp(40), GateCounters.zero);
      await k.journal.flush();
      await k.kill();
      final p = k.segPath(recId(1), 1);
      final b = Uint8List.fromList(k.bytesOf(p)!);
      b[20] ^= 0x10;
      k.put(p, b);
      await expectFailed('mid-log flip');
    });

    test('/sealed-disagrees-with-log (J-12)', () async {
      await prepare();
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.permissionRevoked));
      final p = '${k.dirOf(recId(1))}/SEALED';
      k.put(p, k.cipher().seal(utf(jsonEncode({
        'v': 1, 'samples': 99, 'frames': 1, 'last': 5000, 'reason': 'permissionRevoked',
        'imported': 1, 'lastSeg': 1,
      }))));
      await expectFailed('sealed mismatch');
    });
  });

  group('DT-13-2 / DT-13-5 keep (quarantine) and delete file', () {
    test('/three-restarts: bytes unchanged across restarts', () async {
      await killedRun(k, recId(1), n: 5);
      final meta = '${k.dirOf(recId(1))}/meta.json';
      k.put(meta, Uint8List(3));
      final before = k.snapshot(recId(1));
      for (var i = 0; i < 3; i++) {
        final r = await k.journal.listUnfinished();
        expect(r.single.status, UnfinishedStatus.unreadable);
        expect(k.snapshot(recId(1)), before, reason: 'restart $i');
        await k.kill();
      }
    });

    test('/keep: a QUARANTINED marker is written, the files stay byte-identical, Start is allowed', () async {
      await killedRun(k, recId(1), n: 5);
      final meta = '${k.dirOf(recId(1))}/meta.json';
      k.put(meta, Uint8List(3));
      final before = k.snapshot(recId(1));
      expect((await k.journal.listUnfinished()).single.blocksStart, isTrue);
      await k.journal.quarantine(recId(1));
      final after = k.snapshot(recId(1));
      expect(after.keys.toSet().difference(before.keys.toSet()), {'${k.dirOf(recId(1))}/QUARANTINED'});
      for (final e in before.entries) {
        expect(after[e.key], e.value, reason: 'file ${e.key} unchanged');
      }
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.quarantined);
      expect(r.single.blocksStart, isFalse);
      await k.kill();
      expect((await k.journal.listUnfinished()).single.status, UnfinishedStatus.quarantined);
      // quarantine is idempotent
      await k.journal.quarantine(recId(1));
      expect(k.snapshot(recId(1)).length, after.length);
    });

    test('/delete-file: the directory is gone after the delete decision', () async {
      await killedRun(k, recId(1), n: 5);
      k.put('${k.dirOf(recId(1))}/meta.json', Uint8List(3));
      expect(await k.journal.decideDelete(recId(1)), DecisionOutcome.committed);
      expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
      expect(k.filesOf(recId(1)), isEmpty);
      expect(await k.journal.listUnfinished(), isEmpty);
    });
  });

  test('DT-13-7 a quarantined recording lives 29 d 23 h and is deleted at 30 d with no sample left', () async {
    await killedRun(k, recId(1), n: 5);
    k.put('${k.dirOf(recId(1))}/meta.json', Uint8List(3));
    await k.journal.quarantine(recId(1));
    k.clock.advance(const Duration(days: 29, hours: 23));
    var r = await k.journal.listUnfinished();
    expect(r.single.status, UnfinishedStatus.quarantined);
    expect(k.sampleBytesLeft(recId(1)), isTrue);
    k.clock.advance(const Duration(hours: 1));
    r = await k.journal.listUnfinished();
    expect(r, isEmpty);
    expect(k.filesOf(recId(1)), isEmpty, reason: 'no sample or marker left at 30 days');
    expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
  });
}

class ThrowingKeys0 implements JournalKeyProvider {
  @override
  Future<Uint8List?> loadKey() async => throw StateError('store unavailable');
  @override
  Future<Uint8List> loadOrCreateKey() async => throw StateError('store unavailable');
  @override
  Future<void> forget() async {}
}

extension on RecKit {
  bool sampleBytesLeft(String id) => segNames(id).isNotEmpty;
}
