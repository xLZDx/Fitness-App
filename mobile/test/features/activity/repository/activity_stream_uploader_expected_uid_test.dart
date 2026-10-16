// S02 test epic 16c: the stream uploader and remediation J2/J3 B5. Oracles:
// S02_DESIGN.md 17 item 25 and S02_REMEDIATION_J_TEST_NOTES.md (CLIENT J2 (a),
// (b), (c), CLIENT J3b B5), not the code under test.
//
// The shared `StreamUploadWorld` (real journal on the in-memory file system,
// fake callables that record `expectedUid` of every create and commit). A
// "flip" is a uid supplier that answers A for N reads and B afterwards.
import 'package:fitness_app/features/activity/repository/account_changed.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

/// A scoped journal that records reads; it holds no entries.
class _ScopedProbe extends Fake implements ActivityJournal, AccountScopedJournal {
  _ScopedProbe(this.bound);
  final String? bound;
  int reads = 0;
  int lists = 0;

  @override
  String? get boundUid => bound;
  @override
  bool get isBound => bound != null;
  @override
  Future<JournalEntry?> read(String id) async {
    reads++;
    return null;
  }

  @override
  Future<List<JournalEntry>> list() async {
    lists++;
    return const [];
  }
}

class _Flip {
  _Flip(this.flipAfter);
  final int flipAfter;
  int reads = 0;
  String? call() => ++reads <= flipAfter ? 'A' : 'B';
}

void main() {
  late StreamUploadWorld w;
  late ActivityStreamUploader uploader;
  final id = idFor(1);

  setUp(() async {
    w = await StreamUploadWorld.open();
    w.consent.consentUid = 'A';
    uploader = w.makeUploader(currentUid: () => 'A');
    await w.h.journal.put(journalSession(id, seed: 1));
    await w.summarySync();
  });
  tearDown(() async => w.dispose());

  Future<JournalState> state() async => w.stateOf(id);

  group('the pass uid travels as expectedUid (J2 item b)', () {
    test('create and commit both receive the pass uid', () async {
      expect(await uploader.uploadEntry(id), StreamUploadOutcome.uploaded);
      expect(w.cloud.creates.single.expectedUid, 'A');
      expect(w.cloud.commits.single.expectedUid, 'A');
    });

    test('the uid is the one captured at the start, not a constant', () async {
      w.consent.consentUid = 'Zed';
      final u = w.makeUploader(currentUid: () => 'Zed');
      expect(await u.uploadEntry(id), StreamUploadOutcome.uploaded);
      expect(w.cloud.creates.single.expectedUid, 'Zed');
      expect(w.cloud.commits.single.expectedUid, 'Zed');
    });

    test('an explicit boundUid is the one passed on', () async {
      expect(await uploader.uploadEntry(id, boundUid: 'A'),
          StreamUploadOutcome.uploaded);
      expect(w.cloud.creates.single.expectedUid, 'A');
    });
  });

  group('ConsentAccountChangedException ends the upload as cancelled (item c)',
      () {
    Future<void> expectNoFailureTrace() async {
      final s = await state();
      expect(s.streamUploadPending, isTrue, reason: 'nothing marked uploaded');
      expect(s.syncState, isNot(JournalSyncState.uploadFailed),
          reason: 'no failure state');
      expect(w.delays, isEmpty, reason: 'no backoff, so no retry increment');
      expect(w.cloud.stored, isEmpty);
    }

    test('from create', () async {
      w.cloud.createFault =
          (n) => n == 1 ? const ConsentAccountChangedException() : null;
      expect(await uploader.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(w.cloud.creates, hasLength(1), reason: 'not retried');
      expect(w.cloud.puts, isEmpty);
      expect(w.cloud.commits, isEmpty);
      await expectNoFailureTrace();
    });

    test('from commit (the PUT happened, nothing is marked)', () async {
      w.cloud.commitFault =
          (n) => n == 1 ? const ConsentAccountChangedException() : null;
      expect(await uploader.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(w.cloud.commits, hasLength(1), reason: 'not retried');
      expect(w.cloud.creates, hasLength(1));
      await expectNoFailureTrace();
    });

    test('no quarantine: runPending afterwards still uploads the entry '
        '(it was not added to the failed-this-start set)', () async {
      w.cloud.createFault =
          (n) => n == 1 ? const ConsentAccountChangedException() : null;
      expect(await uploader.uploadEntry(id), StreamUploadOutcome.cancelled);
      await uploader.runPending();
      expect(w.cloud.creates, hasLength(2));
      expect((await state()).streamUploadPending, isFalse);
    });

    test('control: a generic transient failure DOES back off and a refusal is '
        'not cancelled (the assertions above can fail)', () async {
      w.cloud.createFault = (n) => n == 1 ? const StreamUploadTransient('x') : null;
      expect(await uploader.uploadEntry(id), StreamUploadOutcome.uploaded);
      expect(w.delays, isNotEmpty);
    });
  });

  group('the uid flips A to B at an exact point: zero calls for B', () {
    test('flip before create (loop check is the 2nd read): no create, no '
        'put, no commit, nothing marked', () async {
      final f = _Flip(1);
      final u = w.makeUploader(currentUid: f.call);
      expect(await u.uploadEntry(id, boundUid: 'A'),
          StreamUploadOutcome.cancelled);
      expect(f.reads, greaterThanOrEqualTo(2), reason: 'the flip was reached');
      expect(w.cloud.creates, isEmpty);
      expect(w.cloud.puts, isEmpty);
      expect(w.cloud.commits, isEmpty);
      expect((await state()).streamUploadPending, isTrue);
    });

    test('flip between create and commit (during the PUT): no commit, nothing '
        'marked, no failure state', () async {
      var uid = 'A';
      final u = w.makeUploader(currentUid: () => uid);
      w.cloud.duringPut = (_, __) async => uid = 'B';
      expect(await u.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(w.cloud.creates.single.expectedUid, 'A');
      expect(w.cloud.commits, isEmpty, reason: 'zero commit calls for B');
      final s = await state();
      expect(s.streamUploadPending, isTrue);
      expect(s.syncState, isNot(JournalSyncState.uploadFailed));
    });

    test('flip during commit: nothing marked for B', () async {
      var uid = 'A';
      final u = w.makeUploader(currentUid: () => uid);
      w.cloud.duringCommit = (_, __) async => uid = 'B';
      expect(await u.uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(w.cloud.commits.single.expectedUid, 'A');
      expect((await state()).streamUploadPending, isTrue);
    });

    test('every flip point 0..8: whatever was sent carried A, never B, and '
        'the entry is never marked after a flip that precedes the marker',
        () async {
      for (var n = 0; n <= 8; n++) {
        final world = await StreamUploadWorld.open();
        addTearDown(world.dispose);
        world.consent.followUid = null;
        world.consent.consentUid = 'A';
        await world.h.journal.put(journalSession(id, seed: 1));
        await world.summarySync();
        final f = _Flip(n);
        final u = world.makeUploader(currentUid: f.call);
        final out = await u.uploadEntry(id, boundUid: 'A');
        for (final c in world.cloud.creates) {
          expect(c.expectedUid, 'A', reason: 'flip after $n reads');
        }
        for (final c in world.cloud.commits) {
          expect(c.expectedUid, 'A', reason: 'flip after $n reads');
        }
        final s = await world.stateOf(id);
        if (out == StreamUploadOutcome.cancelled) {
          expect(s.streamUploadPending, isTrue, reason: 'flip after $n reads');
        }
        expect(s.syncState, isNot(JournalSyncState.uploadFailed),
            reason: 'flip after $n reads');
      }
    });
  });

  group('J3 B5: a scoped journal bound to another account is never read', () {
    ActivityStreamUploader over(ActivityJournal j, String? uid) =>
        ActivityStreamUploader(
          currentUid: () => uid,
          journal: j,
          callables: w.cloud,
          consent: w.consent,
          put: w.cloud.put,
          flags: w.flags,
          now: w.h.clock.call,
          delay: (_) async {},
        );

    test('uploadEntry: bound to B, pass uid A -> cancelled and no read',
        () async {
      final j = _ScopedProbe('B');
      expect(await over(j, 'A').uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(j.reads, 0);
      expect(w.cloud.creates, isEmpty);
    });

    test('uploadEntry: unbound scoped journal -> cancelled and no read',
        () async {
      final j = _ScopedProbe(null);
      expect(await over(j, 'A').uploadEntry(id), StreamUploadOutcome.cancelled);
      expect(j.reads, 0);
    });

    test('runPending: bound to B, pass uid A -> ends before the first '
        'journal read', () async {
      final j = _ScopedProbe('B');
      await over(j, 'A').runPending();
      expect(j.lists, 0);
      expect(j.reads, 0);
      expect(w.cloud.creates, isEmpty);
    });

    test('control: bound to the pass uid the journal IS read', () async {
      final j = _ScopedProbe('A');
      expect(await over(j, 'A').uploadEntry(id), StreamUploadOutcome.skipped);
      expect(j.reads, 1);
      final k = _ScopedProbe('A');
      await over(k, 'A').runPending();
      expect(k.lists, 1);
    });

    test('control: a plain journal is unaffected and uploads', () async {
      expect(await over(w.h.journal, 'A').uploadEntry(id),
          StreamUploadOutcome.uploaded);
      expect(w.cloud.creates.single.expectedUid, 'A');
    });
  });
}
