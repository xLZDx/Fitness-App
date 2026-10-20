// S02 test epic 15: remediation I1, the display path is tied to the auth uid.
// Oracles: S02_REMEDIATION_H_TEST_NOTES.md heading I1 (cases 1 to 4 and 6),
// design 17 item 24: with a scoped journal and an auth supplier a state read is
// valid only while the journal uid equals the signed-in uid; otherwise it is
// retried (3 attempts) and ends in JournalUnbound, logged as
// `journal-auth-mismatch` without a uid. Real scoped journal on temp files.
//
// Each negative test names the guard it needs: without `_viewTied` before the
// read, case 1/3 would return A's conflict and `list()` would be called.
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stale_view_world.dart';

void main() {
  late ScopedJournalWorld w;
  late HookJournal journal;
  late RecBackend backend;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;
  late int listed;
  String? cur;
  ActivitySyncRepository? repo;

  final idA = idFor(1);
  final idB = idFor(2);

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = HookJournal(w.factory,
        scopesRoot: () async => '${w.base}/activity_journal');
    backend = RecBackend();
    logs = [];
    listed = 0;
    cur = null;
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    journal.onListed = () async => listed++;
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    await repo?.dispose();
    repo = null;
    await journal.close();
    await w.tmp.delete(recursive: true);
  });

  ActivitySyncRepository build({String? Function()? auth}) =>
      repo = ActivitySyncRepository(
        journal: journal,
        backend: backend,
        clock: () => DateTime.utc(2026, 10, 16, 12),
        authUid: auth,
      );

  /// Account [uid] holds one entry in sync_conflict; the journal is left bound
  /// to [uid].
  Future<void> seedConflict(String uid, String id, {int seed = 1}) async {
    expect(await journal.bindUid(uid), isTrue);
    await journal.put(journalSession(id, seed: seed, distanceM: 6000));
    await journal.updateSyncState(id, JournalSyncState.syncConflict);
  }

  bool leaksUid(String line) => line.contains('uidA') || line.contains('uidB');

  group('case 1 and 3: journal bound to A, supplier returns B from the start',
      () {
    test('refreshState never returns A\'s conflict: JournalUnbound after three '
        'attempts, list() never called, the skip is logged without a uid',
        () async {
      await seedConflict('uidA', idA);
      cur = 'uidB';
      final r = build(auth: () => cur);
      final g = Gate();
      journal.listGate = g; // would block a read that (wrongly) started

      await expectLater(r.refreshState(), throwsA(isA<JournalUnbound>()));

      expect(listed, 0, reason: 'the tie is checked BEFORE the read');
      expect(g.entered.isCompleted, isFalse, reason: 'the journal was not read');
      final skips =
          logs.where((l) => l.contains('refreshState skipped (journal-auth-mismatch)'));
      expect(skips, hasLength(3), reason: 'three attempts, each logged');
      expect(logs.any(leaksUid), isFalse, reason: 'no uid in any log line');
    });

    test('watch(): the subscriber gets the JournalUnbound error and never a '
        'state holding A\'s cards', () async {
      await seedConflict('uidA', idA);
      cur = 'uidB';
      final r = build(auth: () => cur);
      final states = <ActivitySyncState>[];
      final errors = <Object>[];
      final sub = r.watch().listen(states.add, onError: errors.add);
      addTearDown(sub.cancel);
      await settle();
      expect(states, isEmpty, reason: 'no state at all, in particular not A\'s');
      expect(errors.single, isA<JournalUnbound>());
    });

    test('a supplier that returns null (signed out, journal still bound) is '
        'refused the same way', () async {
      await seedConflict('uidA', idA);
      cur = null;
      final r = build(auth: () => cur);
      await expectLater(r.refreshState(), throwsA(isA<JournalUnbound>()));
      expect(listed, 0);
      expect(logs.any((l) => l.contains('refreshState skipped (auth-null)')),
          isTrue);
    });

    test('positive control: matching uids return A\'s conflict as before',
        () async {
      await seedConflict('uidA', idA);
      cur = 'uidA';
      final s = await build(auth: () => cur).refreshState();
      expect([for (final c in s.conflicts) c.id], [idA]);
      expect(listed, 1);
      expect(logs.where((l) => l.contains('skipped')), isEmpty);
    });
  });

  group('case 2: the supplier flips from A to B while list() is gated', () {
    test('after the release refreshState does not return A\'s cards', () async {
      await seedConflict('uidA', idA);
      cur = 'uidA';
      final r = build(auth: () => cur);
      final g = Gate();
      journal.listGate = g;

      final read = r.refreshState();
      final outcome = expectLater(read, throwsA(isA<JournalUnbound>()));
      await g.entered.future; // A's list is computed and held
      cur = 'uidB'; // auth flips; the journal is still A's
      g.open();
      await outcome;

      expect(logs.where((l) => l.contains('journal-auth-mismatch')),
          isNotEmpty,
          reason: 'the retries were refused by the tie');
      expect(logs.any(leaksUid), isFalse);
    });

    test('control: no flip while gated returns A\'s conflict', () async {
      await seedConflict('uidA', idA);
      cur = 'uidA';
      final r = build(auth: () => cur);
      final g = Gate();
      journal.listGate = g;
      final read = r.refreshState();
      await g.entered.future;
      g.open();
      expect([for (final c in (await read).conflicts) c.id], [idA]);
    });
  });

  group('case 4: recovery', () {
    test('after the journal rebinds to B the next read returns B\'s entries '
        'only', () async {
      await seedConflict('uidB', idB, seed: 2);
      await seedConflict('uidA', idA); // A bound last
      cur = 'uidB';
      final r = build(auth: () => cur);
      await expectLater(r.refreshState(), throwsA(isA<JournalUnbound>()));

      expect(await journal.bindUid('uidB'), isTrue);
      final s = await r.refreshState();
      expect([for (final c in s.conflicts) c.id], [idB],
          reason: 'only B\'s entry, A\'s id is not in the state');
    });
  });

  group('case 6: controls that keep the old behaviour', () {
    test('a scoped journal with NO auth supplier is not compared', () async {
      await seedConflict('uidA', idA);
      final s = await build().refreshState();
      expect([for (final c in s.conflicts) c.id], [idA]);
    });

    test('a plain (non-scoped) journal with a supplier is not compared',
        () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.dispose);
      await h.journal.put(journalSession(idA, seed: 1, distanceM: 6000));
      await h.journal
          .updateSyncState(idA, JournalSyncState.syncConflict);
      final r = ActivitySyncRepository(
        journal: h.journal,
        backend: backend,
        authUid: () => 'uidB',
      );
      addTearDown(r.dispose);
      final s = await r.refreshState();
      expect([for (final c in s.conflicts) c.id], [idA]);
    });
  });
}
