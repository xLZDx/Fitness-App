// S02 remediation C (test epic 10a): FL2 sheet states (loading / empty / error
// with retry) and the entry card on a load failure. Oracles:
// docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md item FL2 and the Flutter
// review (the user must always be able to reach the retry action).
//
// The repository is a scripted subclass whose watch() hands out a stream the
// test controls; the presenter and widgets are the real ones.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/activity/widgets/activity_sync_entry_card.dart';
import 'package:fitness_app/features/activity/widgets/sync_conflict_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_app.dart';
import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

class _NoJournalRepo extends ActivitySyncRepository {
  _NoJournalRepo(JournalHarness h)
      : super(journal: h.journal, backend: FakeSummaryBackend());

  final List<StreamController<ActivitySyncState>> controllers = [];

  int get watchCalls => controllers.length;
  StreamController<ActivitySyncState> get current => controllers.last;

  @override
  Stream<ActivitySyncState> watch() {
    final c = StreamController<ActivitySyncState>();
    controllers.add(c);
    return c.stream;
  }
}

const _id = 'act_00000000000000000000000000000000000000d1';

SyncConflict _conflict() => SyncConflict(
      id: _id,
      sport: SportType.running,
      startUtc: DateTime.utc(2026, 10, 1, 6),
      fields: const [],
      cloudKnown: false,
    );

const _loading = Key('activitySync.loading');
const _empty = Key('activitySync.empty');
const _error = Key('activitySync.error');
const _retry = Key('activitySync.retry');
const _card = Key('activitySync.entryCard');

Widget _app(_NoJournalRepo repo, Widget home,
        {ActivityFlags flags = const ActivityFlags(cloudSync: true)}) =>
    ProviderScope(
      overrides: [
        activitySyncRepositoryProvider.overrideWithValue(repo),
        activityFlagsProvider.overrideWithValue(flags),
      ],
      child: MaterialApp(
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: Scaffold(body: home),
      ),
    );

void main() {
  late JournalHarness h;
  late _NoJournalRepo repo;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    repo = _NoJournalRepo(h);
    addTearDown(h.dispose);
  });

  group('FL2 sheet states', () {
    testWidgets('before the first emission: progress indicator, never the '
        '"all in sync" text; a loaded empty state then shows the empty text',
        (tester) async {
      await tester.pumpWidget(_app(repo, const SyncConflictSheet()));
      await tester.pump();

      expect(find.byKey(_loading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(_empty), findsNothing);
      expect(find.byKey(_error), findsNothing);

      repo.current.add(ActivitySyncState.empty);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_empty), findsOneWidget);
      expect(find.byKey(_loading), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(_error), findsNothing);
    });

    testWidgets('after a stream error: error text and retry, no empty text and '
        'no spinner', (tester) async {
      await tester.pumpWidget(_app(repo, const SyncConflictSheet()));
      await tester.pump();
      repo.current.addError(StateError('journal unreadable'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_error), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(_empty), findsNothing);
      expect(find.byKey(_loading), findsNothing);
    });

    testWidgets('tapping retry re-subscribes, clears the error and a following '
        'emission shows the conflict', (tester) async {
      await tester.pumpWidget(_app(repo, const SyncConflictSheet()));
      await tester.pump();
      expect(repo.watchCalls, 1);
      repo.current.addError(StateError('journal unreadable'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_retry), findsOneWidget);

      await tester.tap(find.byKey(_retry));
      await tester.pump();

      expect(repo.watchCalls, 2, reason: 'retry subscribes again');
      expect(find.byKey(_error), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_loading), findsOneWidget,
          reason: 'back to loading until the new emission');
      expect(find.byKey(_empty), findsNothing);

      repo.current.add(ActivitySyncState(conflicts: [_conflict()]));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(Key('activitySync.conflict.$_id')), findsOneWidget);
      expect(find.byKey(_loading), findsNothing);
      expect(find.byKey(_error), findsNothing);
      expect(find.byKey(_empty), findsNothing);
    });

    testWidgets('a retry that fails again shows the error again',
        (tester) async {
      await tester.pumpWidget(_app(repo, const SyncConflictSheet()));
      await tester.pump();
      repo.current.addError(StateError('x'));
      await tester.pump();
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      repo.current.addError(StateError('y'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_error), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(repo.watchCalls, 2);
    });
  });

  group('entry card reachability', () {
    testWidgets('hidden while loading and for a loaded empty state',
        (tester) async {
      await tester.pumpWidget(_app(repo, const ActivitySyncEntryCard()));
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
      repo.current.add(ActivitySyncState.empty);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('visible when there are items', (tester) async {
      await tester.pumpWidget(_app(repo, const ActivitySyncEntryCard()));
      await tester.pump();
      repo.current.add(ActivitySyncState(conflicts: [_conflict()]));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_card), findsOneWidget);
    });

    testWidgets('visible when the load failed, so the user can reach retry; '
        'tapping it opens the sheet with the error and retry', (tester) async {
      await tester.pumpWidget(_app(repo, const ActivitySyncEntryCard()));
      await tester.pump();
      repo.current.addError(StateError('journal unreadable'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_card), findsOneWidget,
          reason: 'a hidden card on a load failure makes retry unreachable');

      await tester.tap(find.byKey(_card));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(_error), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('flag off: nothing is built and the repository is never '
        'watched', (tester) async {
      await tester.pumpWidget(_app(repo, const ActivitySyncEntryCard(),
          flags: const ActivityFlags()));
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
      expect(repo.watchCalls, 0);
    });
  });
}
