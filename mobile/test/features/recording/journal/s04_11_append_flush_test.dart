// S04-11 Journal append and flush (EP-D). Rows DT-11-1 .. DT-11-18 of
// docs/phase2/s04/S04_TEST_PLAN.md. Oracle: the plan rows and Design 4.2/4.4
// (frames, segments, flush bound), not the production code. The independent
// decoder in the kit (RecKit.frames) is used so the journal does not mark its
// own homework.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart' show StreamKind;
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/journal/recording_codec.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart' show fixedJournalKey, journalSession, idFor;
import 'journal_kit.dart';

Future<void> pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ThrowingKeys implements JournalKeyProvider {
  @override
  Future<Uint8List?> loadKey() async => throw StateError('store unavailable');
  @override
  Future<Uint8List> loadOrCreateKey() async => throw StateError('store unavailable');
  @override
  Future<void> forget() async {}
}

/// (start, end) of every complete frame of [b].
List<(int, int)> frameSpans(Uint8List b) {
  final bd = ByteData.sublistView(b);
  final out = <(int, int)>[];
  var pos = 0;
  while (b.length - pos >= kFrameHeaderBytes) {
    final len = bd.getUint32(pos);
    if (pos + kFrameHeaderBytes + len > b.length) break;
    out.add((pos, pos + kFrameHeaderBytes + len));
    pos += kFrameHeaderBytes + len;
  }
  return out;
}

Future<int> firstOpIndex(FsOpKind kind, Future<void> Function(RecKit) action,
    {String? contains}) async {
  final s = await RecKit.create();
  try {
    s.fs.clearLog();
    await action(s);
    final op = s.fs.log.firstWhere(
        (o) => o.kind == kind && (contains == null || o.path.contains(contains)));
    return op.index;
  } finally {
    await s.dispose();
  }
}

Map<String, dynamic> decodePlain(Uint8List p) =>
    jsonDecode(utf8.decode(p)) as Map<String, dynamic>;

Uint8List encodeJson(Map<String, dynamic> m) =>
    Uint8List.fromList(utf8.encode(jsonEncode(m)));

String stripComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

final RegExp _ioPattern =
    RegExp(r"dart:io|path_provider|RandomAccessFile|\bFile\(|\bDirectory\(");

/// Two-frame recording (3 + 3 samples) in segment 1.
Future<void> twoFrames(RecKit k, String id) async {
  await k.journal.begin(k.meta(id));
  for (var i = 1; i <= 3; i++) {
    k.journal.enqueueSample(smp(i), GateCounters.zero);
  }
  await k.journal.flush();
  for (var i = 4; i <= 6; i++) {
    k.journal.enqueueSample(smp(i), GateCounters.zero);
  }
  await k.journal.flush();
}

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  group('DT-11-1 / DT-11-2 file access only inside journal/ through the seam', () {
    test('DT-11-1 no recording folder outside journal/ touches files', () {
      final root = Directory('lib/features/recording');
      expect(root.existsSync(), isTrue, reason: 'cwd must be mobile/');
      final hits = <String>[];
      var scanned = 0;
      for (final e in root.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final p = e.path.replaceAll('\\', '/');
        if (p.contains('/journal/')) continue;
        scanned++;
        if (_ioPattern.hasMatch(stripComments(e.readAsStringSync()))) hits.add(p);
      }
      expect(scanned, greaterThan(30), reason: 'the scan must really cover the tree');
      expect(hits, isEmpty);
    });

    test('DT-11-2 the journal itself reaches files only through the seams', () {
      for (final f in [
        'file_recording_journal.dart',
        'recording_codec.dart',
        'pre_unbind_hook.dart',
      ]) {
        final src = stripComments(
            File('lib/features/recording/journal/$f').readAsStringSync());
        expect(_ioPattern.hasMatch(src), isFalse, reason: f);
      }
      final j = File('lib/features/recording/journal/file_recording_journal.dart')
          .readAsStringSync();
      expect(j.contains('JournalFileSystem'), isTrue);
      expect(j.contains('RecordingFileOps'), isTrue);
    });
  });

  group('DT-11-3 recorder append and an unrelated ActivityJournal.put', () {
    test('/append-first: both land, nothing blocks', () async {
      await k.journal.begin(k.meta(recId(1)));
      for (var i = 1; i <= 3; i++) {
        k.journal.enqueueSample(smp(i), GateCounters.zero);
      }
      final gate = k.activity.putGate = Completer<void>();
      final append = k.journal.flush();
      final put = k.activity.put(journalSession(idFor(7)));
      await append; // the recorder append finishes while the put is still held
      expect(k.sampleCountOnDisk(recId(1)), 3);
      gate.complete();
      await put;
      expect((await k.activityReal.list()).map((e) => e.id), contains(idFor(7)));
      expect(k.sampleCountOnDisk(recId(1)), 3);
    });

    test('/put-first: both land, nothing blocks', () async {
      await k.journal.begin(k.meta(recId(1)));
      final gate = k.activity.putGate = Completer<void>();
      final put = k.activity.put(journalSession(idFor(8)));
      for (var i = 1; i <= 4; i++) {
        k.journal.enqueueSample(smp(i), GateCounters.zero);
      }
      await k.journal.flush(); // must not wait for the held put
      expect(k.sampleCountOnDisk(recId(1)), 4);
      gate.complete();
      await put;
      expect((await k.activityReal.list()).map((e) => e.id), contains(idFor(8)));
    });
  });

  group('DT-11-4 meta first', () {
    test('/meta-before-first-sample: temp write, fsync, rename, then the first frame', () async {
      k.fs.clearLog();
      await k.journal.begin(k.meta(recId(1)));
      k.journal.enqueueSample(smp(1), GateCounters.zero);
      await k.journal.flush();
      final ops = k.fs.log.where((o) => o.kind != FsOpKind.note).toList();
      int idx(bool Function(FsOp) f) => ops.indexWhere(f);
      final metaWrite = idx((o) => o.kind == FsOpKind.write && o.path.endsWith('meta.json.tmp'));
      final metaFsync = idx((o) => o.kind == FsOpKind.fsync && o.path.endsWith('meta.json.tmp'));
      final metaRename = idx((o) => o.kind == FsOpKind.rename && (o.to ?? '').endsWith('meta.json'));
      final segOpen = idx((o) => o.kind == FsOpKind.openWrite && o.path.endsWith('seg-0001.log'));
      expect(metaWrite, isNonNegative);
      expect(metaWrite, lessThan(metaFsync));
      expect(metaFsync, lessThan(metaRename));
      expect(metaRename, lessThan(segOpen), reason: 'meta.json must be durable before any sample');
      expect(k.bytesOf('${k.dirOf(recId(1))}/meta.json'), isNotNull);
    });

    test('/begin-failure: a failed meta write leaves no recording directory', () async {
      final idx = await firstOpIndex(FsOpKind.write, (s) => s.journal.begin(s.meta(recId(1))),
          contains: 'meta.json');
      k.fs.arm(FaultPlan(idx, FaultMode.failAt));
      await expectLater(k.journal.begin(k.meta(recId(1))), throwsA(isA<RecordingJournalError>()));
      expect(k.fs.fired, isTrue);
      expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse,
          reason: 'no empty recording directory may remain');
      expect([for (final f in k.mem.files.keys) if (f.contains(recId(1))) f], isEmpty);
      k.fs.disarm();
      // and the next start is not blocked by a ghost
      final left = await k.journal.listUnfinished();
      expect(left, isEmpty);
    });
  });

  group('DT-11-5 flush triggers', () {
    test('/10-fixes: the tenth queued fix flushes at once', () async {
      await k.journal.begin(k.meta(recId(1)));
      for (var i = 1; i <= 9; i++) {
        k.journal.enqueueSample(smp(i), GateCounters.zero);
      }
      await pump();
      expect(k.sampleCountOnDisk(recId(1)), 0, reason: '9 fixes: no size trigger yet');
      k.journal.enqueueSample(smp(10), GateCounters.zero);
      await pump();
      expect(k.sampleCountOnDisk(recId(1)), 10);
    });

    test('/5-seconds: fewer than 10 fixes are flushed by the 5 s timer, not before', () {
      fakeAsync((fa) {
        final f = settle(fa, RecKit.create());
        settle(fa, f.journal.begin(f.meta(recId(1))));
        for (var i = 1; i <= 3; i++) {
          f.journal.enqueueSample(smp(i), GateCounters.zero);
        }
        tick(fa, f, 4900);
        expect(f.mem.files.keys.any((p) => p.endsWith('seg-0001.log')), isFalse,
            reason: 'nothing written before the interval');
        tick(fa, f, 200);
        expect(f.sampleCountOnDisk(recId(1)), 3);
        settle(fa, f.journal.closeScope(f.scopeId));
      });
    });

    test('/event-forces-flush: pause, resume, gap and stop events flush at once', () async {
      await k.journal.begin(k.meta(recId(1)));
      k.journal.enqueueSample(smp(1), GateCounters.zero);
      var n = 0;
      for (final kind in [
        JournalEventKind.pause,
        JournalEventKind.resume,
        JournalEventKind.gapStart,
        JournalEventKind.gapEnd,
        JournalEventKind.stoppedStorage,
      ]) {
        await k.journal.appendEvent(JournalEvent(kind, 1000 + n++));
        expect(eventKinds(k, recId(1)).last, kind.name,
            reason: '${kind.name} must be on disk when appendEvent returns');
      }
      expect(k.sampleCountOnDisk(recId(1)), 1, reason: 'the queued sample goes before the event');
      // each flush is write then fsync (never fsync before the last write)
      final ops = k.fs.log.where((o) => o.path.endsWith('seg-0001.log')).toList();
      final lastWrite = ops.lastIndexWhere((o) => o.kind == FsOpKind.write);
      final lastFsync = ops.lastIndexWhere((o) => o.kind == FsOpKind.fsync);
      expect(lastFsync, greaterThan(lastWrite));
    });
  });

  group('DT-11-6 the 50 kill points', () {
    test('worst gap at most 6 s over 50 LCG kill points; recovered records complete', () {
      final lcg = Lcg(20261017);
      var worst = 0;
      final points = <int>[];
      for (var run = 0; run < 50; run++) {
        final killAt = 1 + lcg.next(180); // seconds of fixes enqueued before the kill
        points.add(killAt);
        fakeAsync((fa) {
          final f = settle(fa, RecKit.create());
          settle(fa, f.journal.begin(f.meta(recId(1))));
          for (var s = 1; s <= killAt; s++) {
            tick(fa, f, 1000);
            f.journal.enqueueSample(smp(s), GateCounters.zero);
            fa.flushMicrotasks();
          }
          // the process dies right here: no flush, timer abandoned
          settle(fa, f.kill());
          final recovered = settle(fa, f.journal.listUnfinished());
          var endMs = 0;
          if (recovered.isNotEmpty) {
            expect(recovered.single.status, UnfinishedStatus.readable);
            endMs = recovered.single.lastOffsetMs!;
            // every recovered record is complete: contiguous prefix 1..m
            final offs = <int>[];
            for (var sg = 1; sg <= f.segNames(recId(1)).length; sg++) {
              for (final fr in f.frames(recId(1), sg)) {
                if (fr['k'] == 's') offs.addAll((fr['t'] as List).cast<int>());
              }
            }
            for (var i = 1; i < offs.length; i++) {
              expect(offs[i], greaterThan(offs[i - 1]), reason: 'strictly increasing');
            }
            expect(offs, [for (var s = 1; s <= offs.length; s++) s * 1000]);
            expect(endMs, offs.last);
          } else {
            expect(killAt, lessThanOrEqualTo(5),
                reason: 'only a kill before the first flush may leave nothing');
          }
          final gap = killAt * 1000 - endMs;
          if (gap > worst) worst = gap;
          expect(gap, lessThanOrEqualTo(6000), reason: 'kill at ${killAt}s');
          settle(fa, f.dispose());
        });
      }
      // ignore: avoid_print
      print('DT-11-6 worst gap over 50 kill points: $worst ms; points: $points');
      expect(points.toSet().length, greaterThan(20), reason: 'the points must vary');
    });
  });

  group('DT-11-7 torn tail variants (last segment)', () {
    Future<Uint8List> prepare() async {
      await twoFrames(k, recId(1));
      return k.bytesOf(k.segPath(recId(1), 1))!;
    }

    Future<void> check(String name, Uint8List Function(Uint8List) damage,
        {required int expectSamples}) async {
      final b = await prepare();
      k.put(k.segPath(recId(1), 1), damage(b));
      await k.kill();
      final before = k.snapshot(recId(1));
      final r = await k.journal.listUnfinished();
      expect(r, hasLength(1), reason: name);
      expect(r.single.status, UnfinishedStatus.readable, reason: name);
      expect(r.single.sampleCount, expectSamples, reason: name);
      expect(k.snapshot(recId(1)), before, reason: '$name: reading never rewrites');
    }

    test('/short-length-prefix', () => check('short', (b) => Uint8List.fromList([...b, 0, 0, 1]), expectSamples: 6));
    test('/truncated-payload', () => check('trunc', (b) => Uint8List.sublistView(b, 0, b.length - 10), expectSamples: 3));
    test('/bad-crc', () => check('crc', (b) {
          final c = Uint8List.fromList(b);
          final last = frameSpans(c).last;
          c[last.$1 + 5] ^= 0xFF;
          return c;
        }, expectSamples: 3));
    test('/payload-bit-flip', () => check('flip', (b) {
          final c = Uint8List.fromList(b);
          final last = frameSpans(c).last;
          c[last.$2 - 3] ^= 0x01;
          return c;
        }, expectSamples: 3));
    test('/zero-length', () => check('zero', (b) => Uint8List.fromList([...b, 0, 0, 0, 0, 0, 0, 0, 0]), expectSamples: 6));
    test('/length-larger-than-remaining (huge length does not allocate)', () => check('huge', (b) {
          final t = Uint8List(8);
          ByteData.sublistView(t).setUint32(0, 0xFFFFFFF0);
          return Uint8List.fromList([...b, ...t, 1, 2, 3]);
        }, expectSamples: 6));
  });

  group('DT-11-8 a torn tail is never appended to', () {
    test('restart opens the NEXT segment; records after the restart are recovered', () async {
      await twoFrames(k, recId(1));
      final b = k.bytesOf(k.segPath(recId(1), 1))!;
      k.put(k.segPath(recId(1), 1), Uint8List.sublistView(b, 0, b.length - 7)); // torn
      final tornBytes = k.bytesOf(k.segPath(recId(1), 1))!;
      await k.kill();
      final rec = await k.journal.openForResume(recId(1));
      expect(rec.keptCount, 3, reason: 'only the first frame survived');
      for (var i = 20; i <= 22; i++) {
        k.journal.enqueueSample(smp(i), GateCounters.zero);
      }
      await k.journal.flush();
      expect(k.bytesOf(k.segPath(recId(1), 1)), tornBytes, reason: 'the dirty segment is never appended to');
      expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
      expect(k.frames(recId(1), 2).first['e'], 'segmentBreak');
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.readable);
      expect(r.single.sampleCount, 6, reason: '3 before the tear + 3 written after the restart');
    });
  });

  group('DT-11-9 rotation and a missing middle segment', () {
    test('/rotation: 5000 frames per segment, numbered without gaps, order preserved', () async {
      await k.journal.begin(k.meta(recId(1)));
      for (var i = 0; i < 5001; i++) {
        await k.journal.appendEvent(JournalEvent(
            i.isEven ? JournalEventKind.pause : JournalEventKind.resume, 1000 + i));
      }
      expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
      expect(k.frames(recId(1), 1), hasLength(kFramesPerSegment));
      expect(k.frames(recId(1), 2), hasLength(1));
      expect(k.frames(recId(1), 2).single['n'], 5001);
      expect(k.frames(recId(1), 1).first['n'], 1);
      expect(k.frames(recId(1), 1).last['n'], 5000);
      await k.kill();
      final r = await k.journal.listUnfinished();
      // events only: no kept sample, so the readable-but-empty path applies
      expect(r, isEmpty);
    });

    test('/missing-middle-segment (J-9): recoveryFailed, no partial track, files untouched', () async {
      await k.record(recId(1), 3);
      await k.kill();
      await k.journal.openForResume(recId(1));
      k.journal.enqueueSample(smp(50), GateCounters.zero);
      await k.journal.flush();
      await k.kill();
      await k.journal.openForResume(recId(1));
      k.journal.enqueueSample(smp(60), GateCounters.zero);
      await k.journal.flush();
      await k.kill();
      expect(k.segNames(recId(1)), hasLength(3));
      expect((await k.journal.listUnfinished()).single.status, UnfinishedStatus.readable);
      k.mem.files.remove(k.segPath(recId(1), 2));
      final before = k.snapshot(recId(1));
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.unreadable);
      expect(r.single.sampleCount, isNull, reason: 'no partial track information');
      expect(k.snapshot(recId(1)), before);
    });
  });

  test('DT-11-11 a second open of the same recording scope fails and writes nothing', () async {
    await k.journal.begin(k.meta(recId(1)));
    final j2 = k.secondJournal();
    await expectLater(j2.begin(k.meta(recId(2))), throwsJournalCode('journalLocked'));
    await expectLater(j2.listUnfinished(), throwsJournalCode('journalLocked'));
    expect(k.mem.dirs.contains(k.dirOf(recId(2))), isFalse);
    // the same object cannot start a second recording either
    await expectLater(k.journal.begin(k.meta(recId(3))), throwsJournalCode('alreadyActive'));
  });

  test('DT-11-12 the key provider throws at begin: refused, no directory, no sample', () async {
    k.keyOverride = (_) => ThrowingKeys();
    await k.kill();
    await expectLater(k.journal.begin(k.meta(recId(1))), throwsA(anything));
    expect(k.mem.dirs.contains(k.dirOf(recId(1))), isFalse);
    expect(k.mem.files.keys.where((f) => f.contains(recId(1))), isEmpty);
    // a provider that only fails creating a key
    k.keyOverride = null;
  });

  test('DT-11-13 a retry after a half-written frame goes to a NEW segment', () async {
    await k.journal.begin(k.meta(recId(1)));
    for (var i = 1; i <= 3; i++) {
      k.journal.enqueueSample(smp(i), GateCounters.zero);
    }
    await k.journal.flush();
    final before = k.bytesOf(k.segPath(recId(1), 1))!;
    k.fs.clearLog();
    k.fs.arm(const FaultPlan(0, FaultMode.failAt)); // the next write fails
    for (var i = 4; i <= 6; i++) {
      k.journal.enqueueSample(smp(i), GateCounters.zero);
    }
    await k.journal.flush();
    await pump();
    expect(k.fs.fired, isTrue);
    expect(k.faults, contains(JournalFault.storageFailing));
    // the failed write left half a frame in the volatile view
    final b = Uint8List.fromList([...before, 0, 0, 1, 0, 9, 9, 9, 9, 7, 7]);
    k.put(k.segPath(recId(1), 1), b);
    k.fs.disarm();
    await k.journal.flush(); // retry
    await pump();
    expect(k.faults, contains(JournalFault.storageRecovered));
    expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
    final f2 = k.frames(recId(1), 2);
    expect(f2.first['e'], 'segmentBreak');
    expect(f2.first['ps'], 1);
    expect(f2.first['pf'], 1, reason: 'one valid frame before the half frame');
    final ns = <int>[
      ...k.frames(recId(1), 1).map((f) => f['n'] as int),
      ...f2.map((f) => f['n'] as int),
    ];
    expect(ns.toSet().length, ns.length, reason: 'no duplicated frame counter');
    expect(ns, [for (var i = 1; i <= ns.length; i++) i], reason: 'counters contiguous');
    await k.kill();
    final r = await k.journal.listUnfinished();
    expect(r.single.status, UnfinishedStatus.readable);
    expect(r.single.sampleCount, 6);
  });

  group('DT-11-14 / DT-11-15 frame codec', () {
    test('DT-11-14 /samples-schema exact columns and counters', () {
      final p = samplesPayload(5, [smp(1), smp(2)], const GateCounters(accuracy: 1, speed: 2, invalid: 3, nonMonotonic: 4));
      final m = decodePlain(p);
      expect(m.keys.toSet(), {'k', 'n', 't', 'la', 'lo', 'ac', 'al', 'sp', 'rj'});
      expect(m['rj'], [1, 2, 3, 4]);
      expect(m['t'], [1000, 2000]);
    });

    test('DT-11-14 /event-kind: every port kind but the journal-internal break is accepted, a stray kind or field is rejected on read', () async {
      await k.journal.begin(k.meta(recId(1)));
      k.journal.enqueueSample(smp(1), GateCounters.zero);
      var o = 1000;
      for (final kind in JournalEventKind.values.where((e) => e != JournalEventKind.segmentBreak)) {
        await k.journal.appendEvent(JournalEvent(kind, o++));
      }
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.readable, reason: 'closed set of event kinds');

      // reject on read: unknown kind
      final c = k.cipher();
      Uint8List seg(List<Uint8List> payloads) => Uint8List.fromList([
            for (final p in payloads) ...encodeFrame(c, p),
          ]);
      AnalyseResult job(List<Uint8List> ps) => analyseRecording(
          AnalyseJob(segNumbers: const [1], segBytes: [seg(ps)], key: k.keyBytes()));
      expect(job([samplesPayload(1, [smp(1)], GateCounters.zero), eventPayload(2, 'placeName', 5)]).damage,
          Damage.badSchema);
      // reject on read: a stray field in a samples frame (place name)
      final stray = decodePlain(samplesPayload(1, [smp(1)], GateCounters.zero))..['place'] = 'home';
      expect(job([encodeJson(stray)]).damage, Damage.badSchema);
      // reject on read: a stray field in an event frame
      final strayE = decodePlain(eventPayload(1, 'pause', 5))..['dev'] = 'x';
      expect(job([encodeJson(strayE)]).damage, Damage.badSchema);
      // control: the same frames without the stray parts are readable
      expect(job([samplesPayload(1, [smp(1)], GateCounters.zero), eventPayload(2, 'pause', 1500)]).damage, isNull);
    });

    test('DT-11-15 round trip keeps nulls, negative latitude, offsets above 2^31', () {
      final key = fixedJournalKey(3);
      final c = AesGcmJournalCipher(key);
      const big = 2147483648 + 5000;
      final samples = [
        const PipelineSample(offsetMs: big, lat: -33.8688197, lon: 151.2092955, accuracyM: 4.25, altitudeM: null, speedMps: null),
        const PipelineSample(offsetMs: big + 1000, lat: -33.8688107, lon: 151.2093055, accuracyM: null, altitudeM: -12.5, speedMps: 0.0),
      ];
      final bytes = encodeFrame(c, samplesPayload(1, samples, GateCounters.zero));
      final r = analyseRecording(AnalyseJob(segNumbers: const [1], segBytes: [bytes], key: key, wantTrack: true));
      expect(r.damage, isNull);
      expect(r.offsets, [big, big + 1000]);
      expect(r.lats, [-33.8688197, -33.8688107]);
      expect(r.lons, [151.2092955, 151.2093055]);
      expect(r.altOffsets, [big + 1000]);
      expect(r.alts, [-12.5]);
      expect(r.spdOffsets, [big + 1000]);
      expect(r.spds, [0.0]);
      expect(r.accuracies, [4.25, 30.0], reason: 'a missing accuracy is read as the gate limit, never as a perfect fix');
    });
  });

  group('DT-11-17 damaged middle is not read as a short complete track', () {
    Future<void> tornFirstSegmentThenResume() async {
      await twoFrames(k, recId(1));
      final b = k.bytesOf(k.segPath(recId(1), 1))!;
      k.put(k.segPath(recId(1), 1), Uint8List.sublistView(b, 0, b.length - 9));
      await k.kill();
    }

    test('/torn-end-of-earlier-segment-announced (J-11): tolerated, every valid frame counted', () async {
      await tornFirstSegmentThenResume();
      await k.journal.openForResume(recId(1));
      k.journal.enqueueSample(smp(30), GateCounters.zero);
      await k.journal.flush();
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.readable);
      expect(r.single.sampleCount, 4, reason: '3 from frame 1, the torn frame dropped, 1 after');
    });

    test('/torn-end-of-earlier-segment-unannounced (J-10): unreadable, untouched', () async {
      await tornFirstSegmentThenResume();
      final c = k.cipher();
      // segment 2 starts with an ordinary frame (counter 2), no segmentBreak
      k.put(k.segPath(recId(1), 2), encodeFrame(c, samplesPayload(2, [smp(30)], GateCounters.zero)));
      final before = k.snapshot(recId(1));
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.unreadable);
      expect(k.snapshot(recId(1)), before);
    });

    test('/frame-counter-gap: unreadable', () async {
      await twoFrames(k, recId(1));
      final c = k.cipher();
      final b = k.bytesOf(k.segPath(recId(1), 1))!;
      await k.kill();
      k.put(k.segPath(recId(1), 1), Uint8List.fromList([...b, ...encodeFrame(c, eventPayload(4, 'pause', 7000))]));
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.unreadable);
    });

    test('/segmentBreak-count-mismatch: unreadable', () async {
      await tornFirstSegmentThenResume();
      final c = k.cipher();
      k.put(k.segPath(recId(1), 2), encodeFrame(c, eventPayload(2, 'segmentBreak', 3000, prevSegment: 1, prevFrames: 5)));
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.unreadable);
    });
  });

  group('DT-11-18 segmentBreak rules', () {
    test('/segmentBreak-is-the-first-frame-after-resume', () async {
      await k.record(recId(1), 3);
      await k.kill();
      await k.journal.openForResume(recId(1));
      await k.journal.flush();
      final f2 = k.frames(recId(1), 2);
      expect(f2.first['e'], 'segmentBreak');
      expect(f2.first['ps'], 1);
      expect(f2.first['pf'], 1);
      expect(f2.skip(1).map((f) => f['e']).toList(), ['restart', 'gapStart', 'gapEnd']);
    });

    test('/segmentBreak-after-seal-after-kill: sealing a killed recording appends nothing', () async {
      await k.record(recId(1), 3);
      await k.kill();
      await k.journal.seal(recId(1), const SealRequest(reason: StopReason.user));
      expect(k.segNames(recId(1)), ['seg-0001.log'], reason: 'SEALED is a separate file, no segment is opened');
      expect(k.filesOf(recId(1)), contains('SEALED'));
    });

    test('/segmentBreak-after-write-error-rotation', () async {
      await k.journal.begin(k.meta(recId(1)));
      k.journal.enqueueSample(smp(1), GateCounters.zero);
      await k.journal.flush();
      k.fs.arm(const FaultPlan(0, FaultMode.failAt));
      k.journal.enqueueSample(smp(2), GateCounters.zero);
      await k.journal.flush();
      k.fs.disarm();
      await k.journal.flush();
      final f2 = k.frames(recId(1), 2);
      expect(f2.first['e'], 'segmentBreak');
      expect(f2.first['ps'], 1);
    });

    test('/duplicate-frame-counter-keeps-the-first-occurrence (J-14)', () async {
      await twoFrames(k, recId(1));
      final c = k.cipher();
      final b = k.bytesOf(k.segPath(recId(1), 1))!;
      // a duplicate of counter 1 carrying a different (wrong) coordinate
      final dup = encodeFrame(c, samplesPayload(1, [
        const PipelineSample(offsetMs: 9999000, lat: -1.5, lon: -1.5, accuracyM: 3),
      ], GateCounters.zero));
      k.put(k.segPath(recId(1), 1), Uint8List.fromList([...b, ...dup]));
      await k.kill();
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.readable, reason: 'a duplicate does not fail the recording');
      expect(r.single.sampleCount, 6);
      expect(await k.finish(recId(1)), HandOffResult.done);
      final e = await k.activityReal.read(nativeActivityId(recId(1)));
      final lats = e!.session.streams[StreamKind.gps]!.lats;
      expect(lats, isNot(contains(-1.5)), reason: 'the first occurrence is kept');
      expect(lats, hasLength(6));
    });
  });
}
