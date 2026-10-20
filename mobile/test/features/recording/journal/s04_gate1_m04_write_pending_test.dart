// S04 gate 1, finding M-04: _writePending removed items from the snapshot list
// it was iterating when one drain crossed a segment boundary
// (ConcurrentModificationError, so the drain failed and re-wrote frames).
// These rows put kFramesPerSegment + 1 frames into ONE drain.
import 'dart:async';

import 'package:fitness_app/features/recording/journal/recording_codec.dart'
    show kFramesPerSegment;
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_kit.dart';

/// Every frame of every segment, decoded ONCE (decryption is the slow part).
List<List<Map<String, dynamic>>> decodeAll(RecKit k, String id) => [
      for (var s = 1; s <= k.segNames(id).length; s++) k.frames(id, s)
    ];

/// Every frame number, in segment order.
List<int> numbersOf(List<List<Map<String, dynamic>>> segs) => [
      for (final seg in segs) for (final f in seg) f['n'] as int
    ];

/// Every kept sample offset (ms), in disk order.
List<int> offsetsOf(List<List<Map<String, dynamic>>> segs) => [
      for (final seg in segs)
        for (final f in seg)
          if (f['k'] == 's') ...(f['t'] as List).cast<int>()
    ];

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  test('M-04 a failing disk accumulates kFramesPerSegment+1 pending frames; the '
      'recovering drain writes them in one pass across the segment boundary',
      () async {
    const total = kFramesPerSegment + 1;
    await k.journal.begin(k.meta(recId(1)));
    k.fs.failSegWrites = true;
    for (var i = 1; i <= total; i++) {
      k.journal.enqueueSample(smp(i), GateCounters.zero);
      await k.journal.flush(); // fails, the frame stays pending
    }
    expect(k.segNames(recId(1)), isEmpty, reason: 'nothing could be written');
    k.faults.clear();
    k.fs.failSegWrites = false;

    // ONE drain now holds `total` pending frames. Before the fix this threw a
    // ConcurrentModificationError that was swallowed as a storage failure.
    await k.journal.flush();

    expect(k.faults.map((f) => f.name), isNot(contains('storageFailing')),
        reason: 'the recovering drain itself must not fail');
    expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
    final segs = decodeAll(k, recId(1));
    expect(segs[0], hasLength(kFramesPerSegment));
    expect(segs[1], hasLength(1));
    // Counters: contiguous 1..total, no duplicate and no hole.
    expect(numbersOf(segs), [for (var i = 1; i <= total; i++) i]);
    // All samples in the order they were enqueued.
    expect(offsetsOf(segs), [for (var i = 1; i <= total; i++) i * 1000]);

    // Pending was pruned per segment and at the end: another drain writes
    // nothing again.
    await k.journal.flush();
    expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
    expect(k.frames(recId(1), 2), hasLength(1),
        reason: 'no frame is re-written by the next drain');

    // Recovery reads every frame, in order, after a process death.
    await k.kill();
    final r = await k.journal.listUnfinished();
    expect(r.single.status, UnfinishedStatus.readable);
    expect(r.single.sampleCount, total);
    expect(r.single.lastOffsetMs, total * 1000);
  });

  test('M-04 the same boundary crossing when a drain runs behind another drain '
      '(a gated first segment open)', () async {
    // Drain 1 holds the lock at the segment open with a single frame; while it
    // waits, more frames queue up, so drain 2 crosses the boundary with a
    // non-empty current segment.
    await k.journal.begin(k.meta(recId(1)));
    final gate = Completer<void>();
    final reached = Completer<void>();
    k.fs.gate = gate;
    k.fs.reached = reached;
    final flushes = <Future<void>>[];
    k.journal.enqueueSample(smp(1), GateCounters.zero);
    flushes.add(k.journal.flush());
    await reached.future; // drain 1 is inside openWrite
    // Release the gate hook for every later open (reached may complete once).
    k.fs.reached = null;
    const total = kFramesPerSegment + 2;
    for (var i = 2; i <= total; i++) {
      k.journal.enqueueSample(smp(i), GateCounters.zero);
      flushes.add(k.journal.flush());
    }
    gate.complete();
    await Future.wait(flushes); // none of them may throw
    k.fs.gate = null;

    expect(k.faults.map((f) => f.name), isNot(contains('storageFailing')));
    expect(k.segNames(recId(1)), ['seg-0001.log', 'seg-0002.log']);
    final segs = decodeAll(k, recId(1));
    expect(segs[0], hasLength(kFramesPerSegment));
    expect(segs[1], hasLength(2));
    expect(numbersOf(segs), [for (var i = 1; i <= total; i++) i]);
    expect(offsetsOf(segs), [for (var i = 1; i <= total; i++) i * 1000]);

    await k.kill();
    final r = await k.journal.listUnfinished();
    expect(r.single.status, UnfinishedStatus.readable);
    expect(r.single.sampleCount, total);
  });

  test('M-04 exactly one segment of frames in one drain stays one segment '
      '(boundary on the last frame)', () async {
    await k.journal.begin(k.meta(recId(1)));
    k.fs.failSegWrites = true;
    for (var i = 1; i <= kFramesPerSegment; i++) {
      k.journal.enqueueSample(smp(i), GateCounters.zero);
      await k.journal.flush();
    }
    k.fs.failSegWrites = false;
    await k.journal.flush();
    expect(k.segNames(recId(1)), ['seg-0001.log']);
    expect(numbersOf(decodeAll(k, recId(1))),
        [for (var i = 1; i <= kFramesPerSegment; i++) i]);
  });
}
