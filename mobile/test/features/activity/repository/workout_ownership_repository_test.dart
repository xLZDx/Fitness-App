// S02-02 I29 (design 3.6): no dual write between `activities` and the old
// workout collections. S02 has no repository that routes a save by sport, so
// the contract is proved where it can be: the journal/sync path only ever
// writes the activities side, no S02 source references the old collections,
// and a sync pass over seeded old records writes nothing for them.
import 'dart:io';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/workout_model_ownership.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

class _OldStores {
  int workoutSessionsWrites = 0;
  int workoutLogsWrites = 0;
  final seeded = ['old-1', 'old-2', 'old-3'];
}

String _code(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('no S02 activity source reads or writes the old workout collections',
      () {
    final files = Directory('lib/features/activity')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    final forbidden = [
      "'workout_sessions'",
      "'workout_logs'",
      'WorkoutSession',
      'WorkoutLogEntry',
      'workout_session_repository',
    ];
    for (final f in files) {
      final code = _code(f);
      for (final w in forbidden) {
        expect(code.contains(w), isFalse, reason: '${f.path} mentions $w');
      }
    }
    // The firebase collection used by the S02 backend is `activities` only.
    final backend =
        _code(File('lib/features/activity/repository/firestore_activity_summary_backend.dart'));
    expect(backend.contains("'activities'"), isTrue);
  });

  test('every sport has exactly one owning model; only activitySession sports '
      'are stored by the S02 journal path', () {
    final owners = {for (final s in SportType.values) s: modelForSport(s.name)};
    expect(owners.length, SportType.values.length);
    final activitySports = [
      for (final e in owners.entries)
        if (e.value == ActivityStoreModel.activitySession) e.key
    ];
    final workoutSports = [
      for (final e in owners.entries)
        if (e.value == ActivityStoreModel.workoutSession) e.key
    ];
    expect(activitySports.length + workoutSports.length, SportType.values.length);
    expect(activitySports.toSet().intersection(workoutSports.toSet()), isEmpty);
    expect(workoutSports, [SportType.strength]);
  });

  test('saving one session of each activity sport writes exactly one journal '
      'entry and one server row, and nothing to the old stores', () async {
    final h = JournalHarness.memory();
    final backend = FakeSummaryBackend();
    final old = _OldStores();
    await h.open();
    final repo = ActivitySyncRepository(
        journal: h.journal, backend: backend, clock: h.clock.call);
    try {
      var n = 0;
      for (final s in SportType.values) {
        if (modelForSport(s.name) != ActivityStoreModel.activitySession) continue;
        n++;
        await repo.saveSession(journalSession(idFor(n), seed: n, sport: s));
      }
      expect(await h.listIds(), hasLength(n));
      expect(backend.applied, n, reason: 'one server row per saved session');
      expect(backend.docs.length, n);
      expect(old.workoutSessionsWrites + old.workoutLogsWrites, 0);
    } finally {
      await repo.dispose();
      await h.dispose();
    }
  });

  test('seeded old records are never copied into activities by a sync pass',
      () async {
    final h = JournalHarness.memory();
    final backend = FakeSummaryBackend();
    final old = _OldStores();
    await h.open();
    final repo = ActivitySyncRepository(
        journal: h.journal, backend: backend, clock: h.clock.call);
    try {
      expect(old.seeded, hasLength(3));
      await repo.syncAll(retryConflicts: true);
      expect(backend.applied, 0, reason: 'nothing to write for old records');
      expect(backend.docs, isEmpty);
      expect(await h.listIds(), isEmpty);
      // Control: with ONE real journal entry the same pass writes exactly one row.
      await h.journal.put(journalSession(idFor(1)));
      await repo.syncAll();
      expect(backend.applied, 1);
    } finally {
      await repo.dispose();
      await h.dispose();
    }
  });
}
