// S02 test epic 14b: remediation H6, the sheet never shows the previous
// account's cards. Oracles: S02_REMEDIATION_H_TEST_NOTES.md H-B items 2 and 3,
// design 17 item 24 (c): cards only for a loaded, non-failed state; after an A
// to B switch with B's bind failing the sheet shows the error and retry and
// none of A's keys. Real presenter and sheet; the repository stream is scripted.
import 'dart:async';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart'
    show CandidateChoice;
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/activity/widgets/sync_conflict_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_app.dart';
import '../../../support/journal_harness.dart';
import '../../../support/stale_view_world.dart';

class _ScriptedRepo extends ActivitySyncRepository {
  _ScriptedRepo(JournalHarness h)
      : super(journal: h.journal, backend: RecBackend());
  final List<StreamController<ActivitySyncState>> controllers = [];
  StreamController<ActivitySyncState> get current => controllers.last;

  @override
  Stream<ActivitySyncState> watch() {
    final c = StreamController<ActivitySyncState>();
    controllers.add(c);
    return c.stream;
  }
}

/// A presenter whose state is fixed, to test the sheet rule on its own.
class _Fixed extends SyncConflictPresenter {
  _Fixed(this._v);
  final SyncConflictViewState _v;
  @override
  SyncConflictViewState build() => _v;
}

final _uid = StateProvider<String?>((_) => 'A');

const _idA = 'act_00000000000000000000000000000000000000a1';
const _idA2 = 'act_00000000000000000000000000000000000000a2';

SyncConflict _conflict(String id) => SyncConflict(
      id: id,
      sport: SportType.running,
      startUtc: DateTime.utc(2026, 10, 1, 6),
      fields: const [],
      cloudKnown: false,
    );

SyncCandidate _candidate(String id) => SyncCandidate(
      id: id,
      sport: SportType.running,
      startUtc: DateTime.utc(2026, 10, 1, 6),
      field: 'distanceM',
      reason: CandidateReason.recalculation,
      choices: const {CandidateChoice.useComputed, CandidateChoice.keepMine},
      computedValue: 5000,
    );

ActivitySyncState _stateA() => ActivitySyncState(
    conflicts: [_conflict(_idA)], candidates: [_candidate(_idA2)]);

const _loading = Key('activitySync.loading');
const _error = Key('activitySync.error');
const _retry = Key('activitySync.retry');
final _conflictKeyA = Key('activitySync.conflict.$_idA');
final _candidateKeyA = Key('activitySync.candidate.$_idA2.distanceM');

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

void main() {
  late JournalHarness h;
  late _ScriptedRepo repo;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    repo = _ScriptedRepo(h);
    addTearDown(h.dispose);
  });

  group('account switch', () {
    testWidgets('A to B: the first frame is loading and then, with B\'s bind '
        'failing, the sheet shows the error and retry and none of A\'s keys',
        (tester) async {
      await tester.pumpWidget(_app([
        activitySyncRepositoryProvider.overrideWithValue(repo),
        syncConflictUidProvider.overrideWith((ref) => ref.watch(_uid)),
      ]));
      await tester.pump();
      repo.current.add(_stateA());
      await tester.pump();
      await tester.pump();
      // positive control: A's cards are drawn
      expect(find.byKey(_conflictKeyA), findsOneWidget);
      expect(find.byKey(_candidateKeyA), findsOneWidget);

      final container = ProviderScope.containerOf(
          tester.element(find.byType(SyncConflictSheet)));
      container.read(_uid.notifier).state = 'B';
      await tester.pump();
      await tester.pump();

      // first frame of B
      expect(find.byKey(_loading), findsOneWidget);
      expect(find.byKey(_conflictKeyA), findsNothing);
      expect(find.byKey(_candidateKeyA), findsNothing);

      // B's bind fails: the stream errors
      repo.current.addError(StateError('journal unbound'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_error), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(find.byKey(_conflictKeyA), findsNothing);
      expect(find.byKey(_candidateKeyA), findsNothing);
      expect(find.byKey(_loading), findsNothing);
    });
  });

  group('cards only when loaded and not failed', () {
    Future<void> pumpFixed(WidgetTester tester, SyncConflictViewState v) async {
      await tester.pumpWidget(_app([
        activitySyncRepositoryProvider.overrideWithValue(repo),
        syncConflictUidProvider.overrideWithValue('A'),
        syncConflictPresenterProvider.overrideWith(() => _Fixed(v)),
      ]));
      await tester.pump();
    }

    testWidgets('positive control: loaded and not failed shows both cards',
        (tester) async {
      await pumpFixed(
          tester, SyncConflictViewState(sync: _stateA(), loaded: true));
      expect(find.byKey(_conflictKeyA), findsOneWidget);
      expect(find.byKey(_candidateKeyA), findsOneWidget);
      expect(find.byKey(_error), findsNothing);
    });

    testWidgets('loaded but loadFailed: error and retry, no card',
        (tester) async {
      await pumpFixed(tester,
          SyncConflictViewState(sync: _stateA(), loaded: true, loadFailed: true));
      expect(find.byKey(_error), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(find.byKey(_conflictKeyA), findsNothing);
      expect(find.byKey(_candidateKeyA), findsNothing);
    });

    testWidgets('not loaded (first frame) with items in the state: spinner, '
        'no card', (tester) async {
      await pumpFixed(tester, SyncConflictViewState(sync: _stateA()));
      expect(find.byKey(_loading), findsOneWidget);
      expect(find.byKey(_conflictKeyA), findsNothing);
      expect(find.byKey(_candidateKeyA), findsNothing);
    });
  });
}
