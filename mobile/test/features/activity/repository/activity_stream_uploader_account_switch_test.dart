// S02 remediation F2 (test epic 12b): the stream uploader across an account
// switch. Oracles: docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md F2 item 4 and
// S02_DESIGN.md 5.2 item 4 and 17 item 22: after A to B, `runPending()` serves
// B, A's late completion neither uploads, marks nor records a failure under B.
//
// One journal and one entry id stand for "the same deterministic activity id in
// both accounts"; the uid supplier is the account switch. Network calls are
// blocked on completers.
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

void main() {
  late StreamUploadWorld w;
  late String uid;
  late ActivityStreamUploader uploader;
  final id = idFor(1);

  setUp(() async {
    w = await StreamUploadWorld.open();
    uid = 'A';
    // Consent follows the signed-in uid here; the consent binding itself is
    // covered by the consent-uid tests.
    w.consent.followUid = () => uid;
    uploader = w.makeUploader(currentUid: () => uid);
    await w.h.journal.put(journalSession(id, seed: 1));
    await w.summarySync();
  });

  tearDown(() async => w.dispose());

  /// Blocks the n-th create call until its completer is completed.
  Map<int, Completer<void>> blockCreates(Set<int> which) {
    final gates = {for (final n in which) n: Completer<void>()};
    w.cloud.duringCreate = (n, _) async => gates[n]?.future;
    return gates;
  }

  void switchTo(String next) {
    uid = next;
    uploader.cancelQueued();
    uploader.resume();
  }

  Future<void> started(int creates) async {
    for (var i = 0; i < 200 && w.cloud.creates.length < creates; i++) {
      await pumpEventQueue();
    }
    expect(w.cloud.creates.length, greaterThanOrEqualTo(creates));
  }

  Future<bool> streamPending() async =>
      (await w.stateOf(id)).streamUploadPending;

  group('runPending after an account switch', () {
    test('B gets a NEW run (not A\'s future) and its entry is uploaded',
        () async {
      final gates = blockCreates({1});
      final first = uploader.runPending();
      await started(1);

      switchTo('B');
      final second = uploader.runPending();
      expect(identical(first, second), isFalse,
          reason: 'A\'s cancelled future must not be handed to B');
      await second;
      expect(w.cloud.creates.length, 2, reason: 'create was called for B');
      expect(w.cloud.commits, hasLength(1));
      expect(await streamPending(), isFalse, reason: 'B\'s entry is uploaded');

      gates[1]!.complete();
      await first;
    });

    test('A\'s released run ends cancelled: no put, no commit, no mark, no '
        'upload_failed under B', () async {
      final gates = blockCreates({1});
      final runA = uploader.uploadEntry(id);
      await started(1);
      final before = await w.stateOf(id);

      switchTo('B');
      gates[1]!.complete();
      expect(await runA, StreamUploadOutcome.cancelled);

      expect(w.cloud.puts, isEmpty);
      expect(w.cloud.commits, isEmpty);
      final after = await w.stateOf(id);
      expect(after.streamUploadPending, isTrue, reason: 'not marked uploaded');
      expect(after.syncState, before.syncState);
      expect(after.syncState, isNot(JournalSyncState.uploadFailed));
    });

    test('A\'s run that FAILS after the switch records no failure and does not '
        'suppress B', () async {
      final gates = blockCreates({1});
      w.cloud.duringCreate = (n, _) async {
        if (n == 1) {
          await gates[1]!.future;
          throw const StreamUploadTransient('boom');
        }
      };
      final runA = uploader.uploadEntry(id);
      await started(1);

      switchTo('B');
      gates[1]!.complete();
      expect(await runA, StreamUploadOutcome.cancelled);
      expect((await w.stateOf(id)).syncState,
          isNot(JournalSyncState.uploadFailed),
          reason: 'no upload_failed written under B');

      await uploader.runPending();
      expect(await streamPending(), isFalse, reason: 'B was not suppressed');
    });

    test('A\'s late completion does not clear B\'s in-flight slot', () async {
      final gates = blockCreates({1, 2});
      final first = uploader.runPending();
      await started(1);
      switchTo('B');
      final runB = uploader.runPending();
      await started(2);

      gates[1]!.complete();
      await first;
      final third = uploader.runPending();
      expect(identical(third, runB), isTrue,
          reason: 'B is still running; a third call joins B\'s run');
      expect(w.cloud.creates.length, 2, reason: 'no third run was started');

      gates[2]!.complete();
      await runB;
      expect(await streamPending(), isFalse);
    });

    test('uploadEntry single-flight does not hand B the outcome of A',
        () async {
      final gates = blockCreates({1});
      final runA = uploader.uploadEntry(id);
      await started(1);

      switchTo('B');
      final runB = uploader.uploadEntry(id);
      expect(identical(runA, runB), isFalse);
      expect(await runB, StreamUploadOutcome.uploaded);

      gates[1]!.complete();
      expect(await runA, StreamUploadOutcome.cancelled);
    });

    test('an id that failed for A is uploaded for B after the switch',
        () async {
      w.cloud.createFault =
          (n) => n <= kStreamUploadMaxAttempts ? const StreamUploadTransient() : null;
      await uploader.runPending(); // A: every attempt fails
      expect(w.cloud.commits, isEmpty);
      expect((await w.stateOf(id)).syncState, JournalSyncState.uploadFailed);

      // Control: without a switch the failed id is not retried in this start.
      final createsBefore = w.cloud.creates.length;
      await uploader.runPending();
      expect(w.cloud.creates.length, createsBefore,
          reason: 'failed this start: skipped for the same account');

      switchTo('B');
      await uploader.runPending();
      expect(w.cloud.creates.length, greaterThan(createsBefore),
          reason: 'A\'s failed ids do not suppress B');
      expect(w.cloud.commits, hasLength(1));
      expect(await streamPending(), isFalse);
    });

    test('same account, cancelQueued then resume: a run that was in flight '
        'records no failure in the new epoch', () async {
      final gate = Completer<void>();
      w.cloud.duringCreate = (n, _) async {
        if (n == 1) await gate.future;
        throw const StreamUploadTransient('down'); // every attempt fails
      };
      final runA = uploader.uploadEntry(id);
      await started(1);
      uploader.cancelQueued();
      uploader.resume();
      gate.complete();
      // The uid is unchanged, but the run belongs to the old epoch: its
      // exhausted attempts are not a failure of the new one.
      expect(await runA, StreamUploadOutcome.cancelled);
      expect((await w.stateOf(id)).syncState,
          isNot(JournalSyncState.uploadFailed));
    });
  });
}
