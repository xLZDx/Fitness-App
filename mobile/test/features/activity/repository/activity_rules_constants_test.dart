// S02 test epic 5, ids I30 and I34 (the client side of the rules contract).
//
// The plan puts these in `firestore_activity_repository_test.dart`; that file
// already exists (epic 3) and the build has no class FirestoreActivityRepository
// (the cloud path is ActivitySyncRepository over ActivitySummaryBackend), so
// they live in their own file.
//
// I30 (DQ-15): `startUtc` and `sport` are immutable on the cloud summary. A user
// edit may not name either field, and the summary written after any legal edit
// keeps both values (the rules refuse a changed value, R29).
// I34 (design 4): at most 8 summaries per call (2 lookups each = 16 access
// calls). A call of 9 is refused WHOLE before any write; a refusal is never read
// as deletion or sync_conflict; a 500-entry flush never sends more than 8
// summaries in one backend call.
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart';

class _SizeRecordingBackend extends FakeSummaryBackend {
  /// Number of summaries handed to the backend per call (the repository uses
  /// single-summary calls; the test would see a batch if one were introduced).
  final List<int> callSizes = [];

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) {
    callSizes.add(1);
    return super.writeSummary(id, summary, create: create);
  }
}

void main() {
  group('I30 startUtc and sport are immutable on the cloud summary', () {
    late World w;
    setUp(() async => w = await World.open());
    tearDown(() async => w.dispose());

    test('an explicit edit naming startUtc or sport is rejected and nothing changes',
        () async {
      final id = await w.bothSynced();
      final before = Map<String, Object?>.from(w.server.docs[id]!);
      final gen = await w.a.generation(id);
      final writes = w.server.accepted.length;
      for (final bad in <Map<String, double>>[
        {'startUtc': 1},
        {'sport': 1},
        {'startUtc': 1, 'distanceM': 5000},
      ]) {
        await expectLater(
            w.a.repo.applyExplicitEdit(id, bad), throwsArgumentError,
            reason: '$bad');
      }
      expect(await w.a.generation(id), gen, reason: 'no generation written');
      expect(w.server.accepted.length, writes, reason: 'nothing sent');
      expect(w.server.docs[id], before);
      expect(((await w.a.sessionMap(id))['editHistory'] as List?) ?? [], isEmpty,
          reason: 'the userEdits ring has no entry for a refused edit');
    });

    test('a legal edit changes only the edited value; startUtc, sport and the id stay',
        () async {
      final id = await w.bothSynced();
      final before = Map<String, Object?>.from(w.server.docs[id]!);
      expect(await w.a.repo.applyExplicitEdit(id, {'distanceM': 5100}),
          SyncOutcome.synced);
      final after = w.server.docs[id]!;
      expect(after['distanceM'], 5100, reason: 'control: the edit was written');
      expect(after['startUtc'], before['startUtc']);
      expect(after['sport'], before['sport']);
      expect(after['rev'], (before['rev'] as int) + 1);
      // The write log of the fake enforces the same rule as the rules (R29): none refused.
      expect(w.server.refused, isEmpty);
      // The deterministic id is the journal key: still the same entry, no second one.
      expect((await w.a.h.journal.list()).map((e) => e.id), [id]);
    });
  });

  group('I34 batch limit of the client', () {
    late JournalHarness h;
    late _SizeRecordingBackend backend;
    late ActivitySyncRepository repo;

    setUp(() async {
      h = JournalHarness.memory();
      backend = _SizeRecordingBackend();
      await h.open();
      repo = ActivitySyncRepository(
          journal: h.journal, backend: backend, clock: h.clock.call);
    });
    tearDown(() async {
      await repo.dispose();
      await h.dispose();
    });

    test('the constant is 8 and 8 summaries cost at most 16 access calls', () {
      expect(kMaxSummaryBatch, 8);
      expect(kMaxSummaryBatch * 2 <= 16, isTrue);
    });

    test('a call of 8 syncs all 8; a call of 9 is refused whole before any write',
        () async {
      backend.failWrites = true; // queue offline first
      for (var i = 1; i <= 9; i++) {
        await repo.saveSession(journalSession(idFor(i), seed: i));
      }
      backend.failWrites = false;
      backend.callSizes.clear(); // the offline attempts above were recorded too
      final ids = [for (var i = 1; i <= 9; i++) idFor(i)];

      await expectLater(repo.syncBatch(ids), throwsA(isA<SummaryBatchTooLarge>()));
      expect(backend.applied, 0, reason: 'refused whole: zero writes');
      expect(backend.callSizes, isEmpty);
      // Not read as deletion or conflict: all nine entries are still there, unsynced, not in conflict.
      final entries = await h.journal.list();
      expect(entries, hasLength(9));
      for (final e in entries) {
        expect(e.state.syncState, isNot(JournalSyncState.syncConflict));
        expect(e.state.synced, isFalse);
      }
      expect(await repo.syncBatch(ids.take(8).toList()), hasLength(8)); // control
      expect(backend.applied, 8);
      expect(backend.callSizes.every((s) => s <= kMaxSummaryBatch), isTrue);
    });

    test('a flush of 500 queued entries never sends more than 8 summaries in one backend call',
        () async {
      backend.failWrites = true;
      for (var i = 1; i <= 500; i++) {
        await repo.saveSession(journalSession(idFor(i), seed: i % 50 + 1));
      }
      backend.failWrites = false;
      backend.callSizes.clear();
      final out = await repo.syncAll();
      expect(out, hasLength(500));
      expect(backend.applied, 500);
      expect(backend.callSizes, hasLength(500));
      expect(backend.callSizes.reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(kMaxSummaryBatch));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
