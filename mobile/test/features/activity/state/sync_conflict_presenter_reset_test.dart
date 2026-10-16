// S02 test epic 14b: remediation H6, the conflict presenter is reset per
// account. Oracles: S02_REMEDIATION_H_TEST_NOTES.md H-B items 2 and 4 (presenter
// part), design 17 item 24 (c), and the promise "after I switch accounts I never
// see or act on the previous account's conflicts". Real ProviderContainer, a
// fake auth stream, the real repository over an in-memory journal.
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stale_view_world.dart';

AuthUser _user(String uid) => AuthUser(uid: uid, displayName: uid);

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 400; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not reached');
}

class _FlakyRepo extends ActivitySyncRepository {
  _FlakyRepo(JournalHarness h)
      : super(journal: h.journal, backend: RecBackend());
  bool fail = false;
  @override
  Stream<ActivitySyncState> watch() => fail
      ? Stream<ActivitySyncState>.error(StateError('unreadable'))
      : super.watch();
}

void main() {
  late JournalHarness h;
  late RecBackend backend;
  late ActivitySyncRepository repo;
  late StreamController<AuthUser?> auth;
  late ProviderContainer c;
  late List<SyncConflictViewState> states;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    backend = RecBackend();
    repo = ActivitySyncRepository(journal: h.journal, backend: backend);
    await h.journal.put(journalSession(idFor(1), seed: 1));
    await h.journal
        .updateSyncState(idFor(1), JournalSyncState.syncConflict);
    auth = StreamController<AuthUser?>();
    states = [];
    c = ProviderContainer(overrides: [
      activitySyncRepositoryProvider.overrideWithValue(repo),
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    c.listen(syncConflictPresenterProvider, (_, n) => states.add(n),
        fireImmediately: false);
  });
  tearDown(() async {
    c.dispose();
    await auth.close();
    await repo.dispose();
    await h.dispose();
  });

  final key = SyncConflictPresenter.conflictKey(idFor(1));

  test('uid A to B: the first frame of B is loading, with no conflicts, no '
      'busy key and no failure flag; an action of A that ends later does not '
      'touch B', () async {
    auth.add(_user('A'));
    await until(() => c.read(syncConflictPresenterProvider).loaded);
    expect(c.read(syncConflictPresenterProvider).conflicts.single.id, idFor(1),
        reason: 'precondition: A sees its conflict');

    // A's tap, blocked in the backend and ending as "unavailable".
    final g = Gate();
    backend.readGate = g;
    backend.readError = const SummaryBackendUnavailable('offline');
    final tap =
        c.read(syncConflictPresenterProvider.notifier).keepDevice(idFor(1));
    await g.entered.future;
    expect(c.read(syncConflictPresenterProvider).busy, {key},
        reason: 'precondition: A has a busy key');

    states.clear();
    auth.add(_user('B'));
    await until(() => states.isNotEmpty);
    final first = states.first;
    expect(first.loaded, isFalse, reason: 'first frame of B is loading');
    expect(first.loadFailed, isFalse);
    expect(first.sync.conflicts, isEmpty);
    expect(first.sync.candidates, isEmpty);
    expect(first.busy, isEmpty, reason: "A's busy key must not survive");
    expect(first.lastFailed, isFalse);

    backend.readError = null;
    g.open();
    await tap;
    await settle();
    final now = c.read(syncConflictPresenterProvider);
    expect(now.lastFailed, isFalse,
        reason: "A's failed action must not mark B's state as failed");
    expect(now.busy, isEmpty);
    expect(states.any((s) => s.lastFailed), isFalse);
  });

  test('a refresh error clears the previous list instead of keeping it',
      () async {
    final flaky = _FlakyRepo(h);
    addTearDown(flaky.dispose);
    final c2 = ProviderContainer(overrides: [
      activitySyncRepositoryProvider.overrideWithValue(flaky),
      syncConflictUidProvider.overrideWithValue('A'),
    ]);
    addTearDown(c2.dispose);
    c2.listen(syncConflictPresenterProvider, (_, __) {});
    await until(() => c2.read(syncConflictPresenterProvider).loaded);
    expect(c2.read(syncConflictPresenterProvider).hasItems, isTrue);
    // The next subscription (retry) errors: the old list must be gone.
    flaky.fail = true;
    c2.read(syncConflictPresenterProvider.notifier).retry();
    await until(() => c2.read(syncConflictPresenterProvider).loadFailed);
    final v = c2.read(syncConflictPresenterProvider);
    expect(v.sync.conflicts, isEmpty);
    expect(v.sync.candidates, isEmpty);
  });

  test('same uid re-emitted: the state is not reset (control)', () async {
    auth.add(_user('A'));
    await until(() => c.read(syncConflictPresenterProvider).loaded);
    states.clear();
    auth.add(_user('A'));
    await settle();
    expect(states.any((s) => !s.loaded), isFalse,
        reason: 'select() on the uid: an equal uid does not rebuild');
    expect(c.read(syncConflictPresenterProvider).conflicts, hasLength(1));
  });
}
