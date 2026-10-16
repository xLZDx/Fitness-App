// S02 test epic 10b: remediation C item FL5 (uploader). Oracle:
// docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md (FL5 uploader) and the
// design 5.2 item 4 rule "an upload belongs to the account it started with",
// not the uploader code.
//
// A run is bound to the uid it started with. When the injected `currentUid`
// supplier returns another uid or null, the run ends with `cancelled`: no later
// network call and no journal mark. The flip is injected at each step through
// the shared fake hooks (create / PUT / commit) or a spying journal (read).
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

/// Counts the two journal writes the uploader may make and can run a hook when
/// an entry is read. Everything else goes to the real journal.
class _SpyJournal extends Fake implements ActivityJournal {
  _SpyJournal(this.inner);

  final ActivityJournal inner;
  void Function()? onRead;
  int marks = 0;
  int syncStateWrites = 0;

  @override
  Future<JournalEntry?> read(String id) async {
    final e = await inner.read(id);
    onRead?.call();
    return e;
  }

  @override
  Future<List<JournalEntry>> list() => inner.list();

  @override
  Future<bool> markStreamUploaded(String id, {int? expectedGeneration}) {
    marks++;
    return inner.markStreamUploaded(id, expectedGeneration: expectedGeneration);
  }

  @override
  Future<bool> updateSyncState(
    String id,
    JournalSyncState state, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) {
    syncStateWrites++;
    return inner.updateSyncState(id, state,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }
}

void main() {
  late StreamUploadWorld w;
  late _SpyJournal spy;
  String? uid;
  final id = idFor(1);

  Future<void> seedSynced(String activityId, {int seed = 0}) async {
    await w.h.journal.put(journalSession(activityId, seed: seed));
    await w.summarySync();
  }

  /// A fresh uploader on the spying journal, bound through [uid].
  ActivityStreamUploader bound() => ActivityStreamUploader(
        journal: spy,
        callables: w.cloud,
        consent: w.consent,
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        delay: (d) async {
          w.cloud.log.add('delay');
          w.h.clock.advance(d);
        },
        currentUid: () => uid,
      );

  setUp(() async {
    w = await StreamUploadWorld.open();
    spy = _SpyJournal(w.h.journal);
    uid = 'A';
    // These tests flip the signed-in uid; consent follows it (remediation H
    // needs consentUid == the run's uid). Consent binding has its own tests.
    w.consent.followUid = () => uid;
    await seedSynced(id);
  });

  tearDown(() => w.dispose());

  /// Nothing may be marked and the entry must still be a pending upload.
  Future<void> expectUntouched() async {
    expect(spy.marks, 0, reason: 'markStreamUploaded must not run');
    expect(spy.syncStateWrites, 0, reason: 'no upload_failed mark');
    final s = await w.stateOf(id);
    expect(s.streamUploadPending, isTrue);
    expect(s.syncState, JournalSyncState.synced);
  }

  for (final target in <String?>['B', null]) {
    final label = target == null ? 'null (signed out)' : 'uid B';

    group('uid A -> $label', () {
      test('before create: cancelled, no network call, no mark', () async {
        final u = bound();
        spy.onRead = () => uid = target;
        final out = await u.uploadEntry(id);
        expect(out, StreamUploadOutcome.cancelled);
        expect(w.cloud.log, isEmpty, reason: 'not even create');
        await expectUntouched();
      });

      test('before PUT (flip while create runs): cancelled, create only',
          () async {
        final u = bound();
        w.cloud.duringCreate = (n, _) async => uid = target;
        final out = await u.uploadEntry(id);
        expect(out, StreamUploadOutcome.cancelled);
        expect(w.cloud.log, ['create'], reason: 'no PUT, no commit');
        await expectUntouched();
      });

      test('before commit (flip while the PUT runs): cancelled, no commit',
          () async {
        final u = bound();
        w.cloud.duringPut = (n, _) async => uid = target;
        final out = await u.uploadEntry(id);
        expect(out, StreamUploadOutcome.cancelled);
        expect(w.cloud.log, ['create', 'put']);
        expect(w.cloud.commits, isEmpty);
        await expectUntouched();
      });

      test('before markStreamUploaded (flip during commit): cancelled, the '
          'journal is not marked', () async {
        final u = bound();
        w.cloud.afterCommit = (n, _) async => uid = target;
        final out = await u.uploadEntry(id);
        expect(out, StreamUploadOutcome.cancelled);
        expect(w.cloud.log, ['create', 'put', 'commit']);
        await expectUntouched();
      });

      test('before the upload_failed mark (flip during the last failing '
          'attempt): cancelled, not marked failed', () async {
        final u = bound();
        w.cloud.putFault = (n) {
          if (n == kStreamUploadMaxAttempts) uid = target;
          return Exception('network down');
        };
        final out = await u.uploadEntry(id);
        expect(out, StreamUploadOutcome.cancelled);
        expect(w.cloud.puts, hasLength(kStreamUploadMaxAttempts));
        await expectUntouched();
      });

      test('runPending: the flip stops the run before the next entry',
          () async {
        await seedSynced(idFor(2), seed: 2);
        final u = bound();
        w.cloud.afterCommit = (n, _) async => uid = target;
        await u.runPending();
        expect(w.cloud.creates, hasLength(1),
            reason: 'the second entry is never started');
        expect(spy.marks, 0);
      });
    });
  }

  group('controls', () {
    test('uid stays A through every step: the entry is uploaded and marked',
        () async {
      final out = await bound().uploadEntry(id);
      expect(out, StreamUploadOutcome.uploaded);
      expect(w.cloud.log, ['create', 'put', 'commit']);
      expect(spy.marks, 1);
      expect((await w.stateOf(id)).streamUploadPending, isFalse);
    });

    test('uid null before the run starts: nothing is sent', () async {
      uid = null;
      final u = bound();
      await u.runPending();
      expect(await u.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(w.cloud.log, isEmpty);
      expect(spy.marks, 0);
    });

    test('without a supplier the uploader is unbound (unchanged behaviour)',
        () async {
      expect(await w.uploader.uploadEntry(id), StreamUploadOutcome.uploaded);
    });
  });

  group('single flight', () {
    test('two concurrent runPending calls are one run: same future, one '
        'create per entry', () async {
      await seedSynced(idFor(2), seed: 2);
      final gate = Completer<void>();
      w.cloud.duringCreate = (n, _) => gate.future;
      final u = bound();

      final a = u.runPending();
      final b = u.runPending();
      expect(identical(a, b), isTrue, reason: 'the second call joins the run');
      for (var i = 0; i < 100 && w.cloud.creates.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(w.cloud.creates, hasLength(1), reason: 'blocked in create');
      gate.complete();
      await Future.wait([a, b]);

      expect(w.cloud.creates, hasLength(2), reason: 'one create per entry');
      expect(w.cloud.puts, hasLength(2));
      expect(w.cloud.commits, hasLength(2));
      expect(spy.marks, 2);
    });

    test('after a run finished the next runPending starts a new run',
        () async {
      final u = bound();
      await u.runPending();
      expect(w.cloud.creates, hasLength(1));
      await seedSynced(idFor(2), seed: 2);
      await u.runPending();
      expect(w.cloud.creates, hasLength(2),
          reason: 'the in-flight slot was released');
    });

    test('two concurrent uploadEntry calls for one id are one upload',
        () async {
      final gate = Completer<void>();
      w.cloud.duringCreate = (n, _) => gate.future;
      final u = bound();

      final a = u.uploadEntry(id);
      final b = u.uploadEntry(id);
      expect(identical(a, b), isTrue);
      for (var i = 0; i < 100 && w.cloud.creates.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.complete();
      expect(await Future.wait([a, b]),
          [StreamUploadOutcome.uploaded, StreamUploadOutcome.uploaded]);
      expect(w.cloud.creates, hasLength(1));
      expect(w.cloud.puts, hasLength(1));
      expect(w.cloud.commits, hasLength(1));
      expect(spy.marks, 1);
    });

    test('uploadEntry for two different ids is not merged', () async {
      await seedSynced(idFor(2), seed: 2);
      final gate = Completer<void>();
      w.cloud.duringCreate = (n, _) => gate.future;
      final u = bound();
      final a = u.uploadEntry(id);
      final b = u.uploadEntry(idFor(2));
      expect(identical(a, b), isFalse);
      for (var i = 0; i < 100 && w.cloud.creates.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.complete();
      await Future.wait([a, b]);
      expect(w.cloud.creates, hasLength(2));
    });

    test('a finished uploadEntry is not cached: a later call runs again',
        () async {
      w.cloud.createFault = (n) => n == 1 ? const StreamUploadRefused('x') : null;
      final u = bound();
      expect(await u.uploadEntry(id), StreamUploadOutcome.refused);
      expect(await u.uploadEntry(id), StreamUploadOutcome.uploaded);
      expect(w.cloud.creates, hasLength(2));
    });
  });
}
