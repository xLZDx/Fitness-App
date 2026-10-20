// S02 test epic 15: remediation I1 at the widget layer. Oracle:
// S02_REMEDIATION_H_TEST_NOTES.md I1 case 5: the sheet fed by the REAL
// repository (scoped journal bound to A, signed-in uid B) never draws A's
// cards; it shows the error state. Positive control: matching uids draw them.
// The scoped journal runs over an in-memory file system, so fake async works.
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/activity/widgets/sync_conflict_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_app.dart';
import '../../../support/journal_harness.dart';
import '../../../support/stale_view_world.dart';

Widget _app(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncConflictSheet()),
      ),
    );

/// Lets the real asynchronous journal read finish, then rebuilds.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final idA = idFor(1);
  final conflictKeyA = Key('activitySync.conflict.$idA');
  const errorKey = Key('activitySync.error');

  Future<ActivitySyncRepository> repoFor(
      WidgetTester tester, String? Function() auth) async {
    final fs = JournalHarness.memory().mem!;
    final journal = UidScopedActivityJournal(
      fileSystem: fs,
      scopesRoot: () async => '/tie',
      factory: (scopeId) async => FileActivityJournal(
        rootPath: '/tie/$scopeId',
        fileSystem: fs,
        keyProvider: InMemoryJournalKeyProvider(fixedJournalKey()),
      ),
    );
    await tester.runAsync(() async {
      expect(await journal.bindUid('uidA'), isTrue);
      await journal.put(journalSession(idA, seed: 1, distanceM: 6000));
      await journal.updateSyncState(idA, JournalSyncState.syncConflict);
    });
    final repo = ActivitySyncRepository(
        journal: journal, backend: RecBackend(), authUid: auth);
    addTearDown(() => tester.runAsync(() async {
          await repo.dispose();
          await journal.close();
        }));
    return repo;
  }

  testWidgets('journal bound to A, signed-in uid B: the sheet shows the error '
      'and no card of A', (tester) async {
    final repo = await repoFor(tester, () => 'uidB');
    await tester.pumpWidget(_app([
      activitySyncRepositoryProvider.overrideWithValue(repo),
      syncConflictUidProvider.overrideWithValue('uidB'),
    ]));
    await _drain(tester);
    expect(find.byKey(conflictKeyA), findsNothing);
    expect(find.byKey(errorKey), findsOneWidget);
  });

  // The matching-uid control runs on the presenter in a plain test (real
  // asynchronous journal reads; a widget test with a loaded real state hangs
  // the fake-async binding, see the epic 15 findings).
  for (final matching in [true, false]) {
    test('presenter fed by the real repository, journal bound to A, '
        'matching uids: $matching',
        () async {
      final fs = JournalHarness.memory().mem!;
      final journal = UidScopedActivityJournal(
        fileSystem: fs,
        scopesRoot: () async => '/tie2',
        factory: (scopeId) async => FileActivityJournal(
          rootPath: '/tie2/$scopeId',
          fileSystem: fs,
          keyProvider: InMemoryJournalKeyProvider(fixedJournalKey()),
        ),
      );
      expect(await journal.bindUid('uidA'), isTrue);
      await journal.put(journalSession(idA, seed: 1, distanceM: 6000));
      await journal.updateSyncState(idA, JournalSyncState.syncConflict);
      final uid = matching ? 'uidA' : 'uidB';
      final repo = ActivitySyncRepository(
          journal: journal, backend: RecBackend(), authUid: () => uid);
      final c = ProviderContainer(overrides: [
        activitySyncRepositoryProvider.overrideWithValue(repo),
        syncConflictUidProvider.overrideWithValue(uid),
      ]);
      addTearDown(() async {
        c.dispose();
        await repo.dispose();
        await journal.close();
      });
      c.listen(syncConflictPresenterProvider, (_, __) {});
      for (var i = 0;
          i < 400 &&
              !(c.read(syncConflictPresenterProvider).loaded ||
                  c.read(syncConflictPresenterProvider).loadFailed);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final v = c.read(syncConflictPresenterProvider);
      if (matching) {
        expect(v.loaded, isTrue);
        expect(v.loadFailed, isFalse);
        expect([for (final x in v.sync.conflicts) x.id], [idA]);
      } else {
        expect(v.loadFailed, isTrue, reason: 'the JournalUnbound error state');
        expect(v.sync.conflicts, isEmpty);
        expect(v.sync.candidates, isEmpty);
      }
    });
  }
}
