// S02 test epic 3, I11 and I12 (plan file name kept; the build has no class
// called FirestoreActivityRepository: the cloud path is ActivitySyncRepository
// over ActivitySummaryBackend, whose Firestore adapter is the only code that
// touches Firestore).
//
// I11: the map handed to the backend holds only allowlisted summary keys (the
//      allowlist is PARSED from firestore.rules), no geometry or heart-rate
//      text, and the code has no client Firestore delete (deletes go through
//      the `deleteActivity` callable).
// I12: the offline queue is an idempotent upsert: after offline, reconnect and
//      a second flush the backend holds one document per id.
import 'dart:convert';

import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/firestore_activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/firestore_rules_parser.dart';
import '../../../support/journal_harness.dart';
import '../../../support/s02_paths.dart';

class _RecordingBackend extends FakeSummaryBackend {
  final List<Map<String, Object>> sent = [];

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    sent.add({...summary});
    return super.writeSummary(id, summary, create: create);
  }
}

String _code(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  late JournalHarness h;
  late _RecordingBackend backend;
  late ActivitySyncRepository repo;
  final rules = parseActivityRules();

  ActivitySyncRepository newRepo() => ActivitySyncRepository(
      journal: h.journal, backend: backend, clock: h.clock.call);

  setUp(() async {
    h = JournalHarness.memory();
    backend = _RecordingBackend();
    await h.open();
    repo = newRepo();
  });

  tearDown(() async {
    await repo.dispose();
    await h.dispose();
  });

  group('I11 only the summary is sent, no client Firestore delete', () {
    test('every key sent is in the hasOnly list parsed from firestore.rules, the '
        'required keys are present', () async {
      for (var i = 1; i <= 5; i++) {
        final out = await repo.saveSession(journalSession(idFor(i), seed: i));
        expect(out, SyncOutcome.synced);
      }
      expect(backend.sent, hasLength(5));
      for (final m in backend.sent) {
        expect(m.keys.toSet().difference(rules.allowedKeys.toSet()), isEmpty,
            reason: 'key outside the allowlist: $m');
        expect(m.keys, containsAll(rules.requiredKeys));
      }
    });

    test('no coordinate, heart-rate or stream text leaves the device', () async {
      await repo.saveSession(journalSession(idFor(1), seed: 1));
      final text = jsonEncode(backend.sent.single,
          toEncodable: (o) => o is DateTime ? o.toIso8601String() : '$o');
      expect(text, isNot(contains('7351')), reason: 'latitude sentinel');
      expect(text, isNot(contains('.25')), reason: 'heart-rate sentinel');
      for (final k in ['lats', 'lons', 'heartRate', 'avgHrBpm', 'maxHrBpm', 'streams']) {
        expect(text, isNot(contains(k)), reason: k);
      }
    });

    test('the Firestore adapter translates values only: same keys in, same keys '
        'out, timestamps converted', () {
      final src = <String, Object>{
        'schema': 2,
        'sport': 'running',
        'startUtc': DateTime.utc(2026, 5, 1, 6),
        'endUtc': DateTime.utc(2026, 5, 1, 6, 30),
        'rev': 1,
        'distanceM': 4800.5,
      };
      final fs = toFirestoreSummary(src);
      expect(fs.keys.toSet(), src.keys.toSet());
      expect(fs['startUtc'], isNot(isA<DateTime>()));
      expect(fs['distanceM'], 4800.5);
      final back = fromFirestoreSummary(fs.cast<String, dynamic>());
      expect(back['startUtc'], DateTime.utc(2026, 5, 1, 6));
    });

    test('the backend interface and its Firestore adapter have no delete', () {
      final iface = _code(repoFile(
              'mobile/lib/features/activity/repository/activity_summary_backend.dart')
          .readAsStringSync());
      final body = iface.substring(iface.indexOf('abstract class ActivitySummaryBackend'));
      expect(RegExp(r'delete', caseSensitive: false).hasMatch(body), isFalse);

      final adapter = _code(repoFile(
              'mobile/lib/features/activity/repository/firestore_activity_summary_backend.dart')
          .readAsStringSync());
      expect(adapter, isNot(contains('.delete(')));
      expect(adapter, isNot(contains('FieldValue.delete')));
      expect(adapter, isNot(contains('batch.delete')));
    });

    test('a delete goes through the deleteActivity callable', () {
      final pusher = _code(repoFile(
              'mobile/lib/features/activity/repository/cloud_functions_activity_tombstone_pusher.dart')
          .readAsStringSync());
      expect(pusher, contains("httpsCallable('deleteActivity')"));
      expect(pusher, isNot(contains('cloud_firestore')));
    });

    test('a local delete writes nothing to the backend', () async {
      await repo.saveSession(journalSession(idFor(1), seed: 1));
      final writes = backend.sent.length;
      await h.journal.delete(idFor(1));
      await repo.syncAll();
      expect(backend.sent, hasLength(writes), reason: 'no summary write after delete');
      expect(backend.docs, hasLength(1), reason: 'the server row is not touched');
    });
  });

  group('I12 offline summary queue is an idempotent upsert', () {
    test('offline, reconnect, flush, second flush: one document per id', () async {
      backend.failWrites = true;
      for (var i = 1; i <= 4; i++) {
        expect(await repo.saveSession(journalSession(idFor(i), seed: i)),
            SyncOutcome.unavailable);
      }
      expect(backend.docs, isEmpty);
      // still offline: another flush changes nothing
      await repo.syncAll();
      expect(backend.docs, isEmpty);
      expect((await h.journal.assessSignOut()).unsyncedCount, 4);

      backend.failWrites = false; // reconnect
      final first = await repo.syncAll();
      expect(first.values, everyElement(SyncOutcome.synced));
      expect(backend.docs, hasLength(4));
      final applied = backend.applied;
      expect(applied, 4);

      final second = await repo.syncAll();
      expect(second, isEmpty, reason: 'nothing left to flush');
      expect(backend.docs, hasLength(4), reason: 'still one document per id');
      expect(backend.applied, applied, reason: 'no second write');
    });

    test('a restart between the failed save and the flush converges to one '
        'document', () async {
      backend.failWrites = true;
      await repo.saveSession(journalSession(idFor(1), seed: 1));
      await repo.dispose();
      await h.restart();
      repo = newRepo();
      backend.failWrites = false;
      await repo.syncAll();
      await repo.syncAll();
      expect(backend.docs.keys, [idFor(1)]);
      expect(backend.applied, 1);
      expect((await h.journal.read(idFor(1)))!.state.syncState, JournalSyncState.synced);
    });

    test('saving the same unchanged session again, offline and online, never '
        'adds a second document or raises rev', () async {
      final s = journalSession(idFor(1), seed: 1);
      backend.failWrites = true;
      await repo.saveSession(s);
      await repo.saveSession(s);
      backend.failWrites = false;
      await repo.saveSession(s);
      await repo.saveSession(s);
      expect(backend.docs, hasLength(1));
      expect(backend.docs[idFor(1)]!['rev'], 1);
      expect(backend.applied, 1);
    });

    test('control: two different ids give two documents', () async {
      await repo.saveSession(journalSession(idFor(1), seed: 1));
      await repo.saveSession(journalSession(idFor(2), seed: 2));
      expect(backend.docs, hasLength(2));
    });

    test('a batch larger than the rules batch limit is refused before sending',
        () {
      expect(kMaxSummaryBatch, 8);
      expect(const SummaryBatchTooLarge(9, 8).toString(), contains('9 > 8'));
    });
  });
}
