// S02 test epic 13a: remediation G2 (republish on account or binding change),
// G3 (raw-uid account change in the cloud sync listener) and G4 (wipe marker in
// the unbound branch, deleting account skipped). Oracles:
// docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md headings G2, G3, G4 and the
// promise "a screen never keeps showing the previous account's conflicts",
// NOT the code under test.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/summary_codec.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

final DateTime _t0 = DateTime.utc(2026, 10, 16, 12);

/// Scripted account-scoped journal: results come from [script] (true when
/// empty; an Exception is thrown); [gate] blocks the next bind.
class _J extends Fake implements ActivityJournal, AccountScopedJournal {
  final List<String?> calls = [];
  final List<Object> script = [];
  Completer<void>? gate;
  String? _uid;

  @override
  Future<bool> bindUid(String? uid) async {
    calls.add(uid);
    final g = gate;
    gate = null;
    if (g != null) await g.future;
    final r = script.isEmpty ? true : script.removeAt(0);
    if (r is Exception) throw r;
    if (r == true) _uid = uid;
    return r as bool;
  }

  @override
  String? get boundUid => _uid;

  @override
  bool get isBound => _uid != null;
}

class _RecRepo extends Fake implements ActivitySyncRepository {
  _RecRepo(this.events);
  final List<String> events;

  @override
  void onAccountChanged() => events.add('onAccountChanged');

  @override
  void onJournalBindingChanged() => events.add('onJournalBindingChanged');

  @override
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) async {
    events.add('syncAll');
    return {};
  }

  @override
  Future<void> dispose() async {}
}

class _Uploader extends Fake implements ActivityStreamUploader {
  _Uploader(this.events);
  final List<String> events;
  @override
  void cancelQueued() => events.add('cancelQueued');
  @override
  void resume() => events.add('resume');
  @override
  Future<void> runPending() async => events.add('run');
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  @override
  Future<void> load() async {}
}

class _Consent extends AccountScopedConsentStore {
  @override
  Future<void> signIn(String uid) async {}
}

class _FakeTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

AuthUser _user(String uid, {AuthProvider p = AuthProvider.google}) =>
    AuthUser(uid: uid, displayName: uid, provider: p);

void main() {
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late DebugPrintCallback savedDebugPrint;

  setUp(() {
    auth = StreamController<AuthUser?>();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
  });

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await pumpEventQueue();
  }

  // ---- G2: live presenter --------------------------------------------------

  group('G2: live conflict presenter without any tap', () {
    late ScopedJournalWorld w;
    late FakeSummaryBackend backend;
    late ActivitySyncRepository repo;

    setUp(() async {
      w = await ScopedJournalWorld.create();
      backend = FakeSummaryBackend();
      repo = ActivitySyncRepository(
          journal: w.journal, backend: backend, clock: () => _t0);
    });
    tearDown(() async {
      await repo.dispose();
      await w.dispose();
    });

    Future<void> putConflict(int n) async {
      final id = idFor(n);
      final base = ActivityCloudSummary.fromSession(
          journalSession(id, seed: n, distanceM: 4000),
          updatedAt: _t0)
        ..['rev'] = 1;
      await w.journal.put(journalSession(id, seed: n, distanceM: 4800),
          syncState: JournalSyncState.syncConflict,
          baseRev: 1,
          baseSummary: encodeSummary(base));
    }

    ProviderContainer presenterContainer({List<Override> extra = const []}) {
      final c = ProviderContainer(overrides: [
        activitySyncRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ]);
      addTearDown(c.dispose);
      c.listen(syncConflictPresenterProvider, (_, __) {});
      return c;
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 400 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue, reason: 'condition not reached');
    }

    test('unbind then onAccountChanged: loadFailed, A\'s conflicts are not '
        'presented as live', () async {
      expect(await w.journal.bindUid('A'), isTrue);
      await putConflict(1);
      final c = presenterContainer();
      await until(() => c.read(syncConflictPresenterProvider).loaded);
      expect(c.read(syncConflictPresenterProvider).conflicts, hasLength(1));
      expect(c.read(syncConflictPresenterProvider).loadFailed, isFalse);

      expect(await w.journal.bindUid(null), isTrue);
      repo.onAccountChanged();
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
    });

    test('onAccountChanged, then unbind, then onJournalBindingChanged '
        '(the wiring order): loadFailed without a tap', () async {
      expect(await w.journal.bindUid('A'), isTrue);
      await putConflict(1);
      final c = presenterContainer();
      await until(() => c.read(syncConflictPresenterProvider).loaded);

      repo.onAccountChanged();
      expect(await w.journal.bindUid(null), isTrue);
      repo.onJournalBindingChanged();
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
    });

    test('bind of B succeeds then onJournalBindingChanged: B\'s state, no tap',
        () async {
      expect(await w.journal.bindUid('A'), isTrue);
      await putConflict(1);
      expect(await w.journal.bindUid('B'), isTrue);
      await putConflict(2);
      expect(await w.journal.bindUid('A'), isTrue);
      final c = presenterContainer();
      await until(() => c.read(syncConflictPresenterProvider).loaded);
      expect([for (final x in c.read(syncConflictPresenterProvider).conflicts) x.id],
          [idFor(1)]);

      repo.onAccountChanged();
      expect(await w.journal.bindUid('B'), isTrue);
      repo.onJournalBindingChanged();
      await until(() => [
            for (final x in c.read(syncConflictPresenterProvider).conflicts)
              x.id
          ].contains(idFor(2)));
      final s = c.read(syncConflictPresenterProvider);
      expect([for (final x in s.conflicts) x.id], [idFor(2)],
          reason: 'A\'s conflict is gone');
      expect(s.loadFailed, isFalse);
    });

    test('end to end: the binding provider fails to bind B -> the presenter '
        'shows loadFailed although syncAll never ran', () async {
      expect(await w.journal.bindUid('A'), isTrue);
      await putConflict(1);
      w.failOpen.add(activityJournalScopeId('B'));
      final c = presenterContainer(extra: [
        activityFlagsProvider.overrideWithValue(
            const ActivityFlags(localJournal: true, cloudSync: true)),
        activityJournalProvider.overrideWithValue(w.journal),
        authUserProvider.overrideWith((ref) => auth.stream),
        activityBindRetryTimerFactoryProvider
            .overrideWithValue((d, cb) => _FakeTimer()),
      ]);
      c.read(activityJournalBindingProvider);
      await emit(_user('A'));
      await until(() => c.read(syncConflictPresenterProvider).loaded);
      expect(c.read(syncConflictPresenterProvider).loadFailed, isFalse);

      await emit(_user('B'));
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
      expect(w.journal.isBound, isFalse);
      expect(backend.calls.where((x) => x == 'listTombstoneIds'), isEmpty,
          reason: 'no sync pass ran');
    });
  });

  group('G2: onJournalBindingChanged robustness', () {
    test('after dispose: no throw, nothing emitted', () async {
      final w = await ScopedJournalWorld.create();
      addTearDown(w.dispose);
      final repo = ActivitySyncRepository(
          journal: w.journal, backend: FakeSummaryBackend());
      await repo.dispose();
      repo.onJournalBindingChanged();
      repo.onAccountChanged();
      await pumpEventQueue();
    });

    test('a refresh that fails with a non-JournalUnbound error: nothing '
        'escapes and nothing is added to the stream', () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.journal.close);
      final j = _ListJournal(h.journal);
      final repo = ActivitySyncRepository(
          journal: j, backend: FakeSummaryBackend());
      addTearDown(repo.dispose);
      final seen = <Object>[];
      final sub = repo.watch().listen(seen.add, onError: seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      final before = seen.length;
      expect(before, 1);
      j.fail = true;
      repo.onJournalBindingChanged();
      repo.onAccountChanged();
      await pumpEventQueue();
      expect(seen.length, before);
    });

    test('onAccountChanged never throws, unbound and bound', () async {
      final w = await ScopedJournalWorld.create();
      addTearDown(w.dispose);
      final repo = ActivitySyncRepository(
          journal: w.journal, backend: FakeSummaryBackend());
      addTearDown(repo.dispose);
      repo.onAccountChanged();
      await w.journal.bindUid('A');
      repo.onAccountChanged();
      await pumpEventQueue();
    });
  });

  // ---- G2: wiring -----------------------------------------------------------

  group('G2: the wiring publishes after every bindUid completion', () {
    late _J journal;
    late List<String> events;

    ProviderContainer binding({bool cloudSync = true, _RecRepo? repo}) {
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(
            ActivityFlags(localJournal: true, cloudSync: cloudSync)),
        activityJournalProvider.overrideWithValue(journal),
        authUserProvider.overrideWith((ref) => auth.stream),
        activityBindRetryTimerFactoryProvider
            .overrideWithValue((d, cb) => _FakeTimer()),
        if (cloudSync)
          activitySyncRepositoryProvider
              .overrideWithValue(repo ?? _RecRepo(events)),
      ]);
      addTearDown(c.dispose);
      c.read(activityJournalBindingProvider);
      return c;
    }

    setUp(() {
      journal = _J();
      events = [];
    });

    test('binding provider: success, false and exception -> one publish each',
        () async {
      binding();
      await emit(_user('A'));
      expect(journal.calls, ['A']);
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1));

      events.clear();
      journal.script.add(false);
      await emit(_user('B'));
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1),
          reason: 'false result');

      events.clear();
      journal.script.add(StateError('boom'));
      await emit(_user('C'));
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1),
          reason: 'exception');
    });

    test('cloudSync off: the repository provider is never read', () async {
      binding(cloudSync: false);
      await emit(_user('A'));
      expect(journal.calls, ['A']);
      expect(logs.where((l) => l.contains('not published')), isEmpty,
          reason: 'a read of the unset repository provider would be logged');
    });

    test('provider disposed while a bind is pending: no publish', () async {
      final c = binding();
      journal.gate = Completer<void>();
      final g = journal.gate!;
      await emit(_user('A'));
      expect(journal.calls, ['A']);
      c.dispose();
      g.complete();
      await pumpEventQueue();
      expect(events, isEmpty);
    });

    ProviderContainer cloud({String? deleting}) {
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(
            const ActivityFlags(localJournal: true, cloudSync: true)),
        activityJournalProvider.overrideWithValue(journal),
        authUserProvider.overrideWith((ref) => auth.stream),
        activitySyncRepositoryProvider.overrideWithValue(_RecRepo(events)),
        activityStreamUploaderProvider.overrideWithValue(_Uploader(events)),
        activityCloudSettingsClientProvider.overrideWithValue(_Settings()),
        activityConsentStoreProvider.overrideWithValue(_Consent()),
        if (deleting != null)
          accountBeingDeletedUidProvider.overrideWith((ref) => deleting),
      ]);
      addTearDown(c.dispose);
      c.read(activityCloudSyncWiringProvider);
      return c;
    }

    test('cloud sync wiring: success, false and exception -> one publish each',
        () async {
      cloud();
      await emit(_user('A'));
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1));
      expect(events, contains('syncAll'));

      events.clear();
      journal.script.add(false);
      await emit(_user('B'));
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1));
      expect(events, isNot(contains('syncAll')), reason: 'failed bind: no sync');

      events.clear();
      journal.script.add(StateError('boom'));
      await emit(_user('C'));
      expect(events.where((e) => e == 'onJournalBindingChanged'), hasLength(1));
      expect(events, isNot(contains('syncAll')));
    });

    // ---- G4 wiring ----------------------------------------------------------

    test('G4: the account being deleted is not bound and not synced',
        () async {
      cloud(deleting: 'B');
      await emit(_user('B'));
      expect(journal.calls, isEmpty, reason: 'bindUid is not called');
      expect(events, isNot(contains('syncAll')));
      expect(logs.any((l) => l.contains('account is being deleted')), isTrue);
    });

    test('G4 control: with no account being deleted the same emission binds '
        'and syncs', () async {
      cloud();
      await emit(_user('B'));
      expect(journal.calls, ['B']);
      expect(events, contains('syncAll'));
    });

    // ---- G3 -----------------------------------------------------------------

    test('G3: anonymous X then real B: onAccountChanged and cancelQueued once; '
        'no sync for X, B binds and syncs once', () async {
      cloud();
      await emit(_user('X', p: AuthProvider.anonymous));
      expect(events, isEmpty, reason: 'anonymous alone: nothing');
      expect(journal.calls, isEmpty);

      await emit(_user('B'));
      expect(events.where((e) => e == 'onAccountChanged'), hasLength(1));
      expect(events.where((e) => e == 'cancelQueued'), hasLength(1));
      expect(journal.calls, ['B']);
      expect(events.where((e) => e == 'syncAll'), hasLength(1));
    });

    test('G3: real A to anonymous Y and real A to null each cancel once',
        () async {
      cloud();
      await emit(_user('A'));
      events.clear();
      await emit(_user('Y', p: AuthProvider.anonymous));
      expect(events.where((e) => e == 'onAccountChanged'), hasLength(1));
      expect(events.where((e) => e == 'cancelQueued'), hasLength(1));

      events.clear();
      await emit(_user('A'));
      events.clear();
      await emit(null);
      expect(events.where((e) => e == 'onAccountChanged'), hasLength(1));
      expect(events.where((e) => e == 'cancelQueued'), hasLength(1));
    });

    test('G3: null to A and A to A (same raw uid) do not reset', () async {
      cloud();
      await emit(_user('A'));
      expect(events.where((e) => e == 'onAccountChanged'), isEmpty);
      expect(events.where((e) => e == 'cancelQueued'), isEmpty);
      await emit(AuthUser(
          uid: 'A', displayName: 'Renamed', provider: AuthProvider.google));
      expect(events.where((e) => e == 'onAccountChanged'), isEmpty);
      expect(events.where((e) => e == 'cancelQueued'), isEmpty);
    });
  });

  // ---- G4: journal -----------------------------------------------------------

  group('G4: wipe marker in the unbound branch', () {
    late ScopedJournalWorld w;
    setUp(() async => w = await ScopedJournalWorld.create());
    tearDown(() async => w.dispose());

    test('wipeForUid(U) while nothing is bound, then bindUid(U): false, no '
        'directory, no key, factory never asked', () async {
      await w.journal.wipeForUid('U');
      // The wipe itself opens the scope once to delete it; the bind must not.
      final openedByWipe = List.of(w.opened);
      final dirsAfterWipe = await w.scopeDirs();
      expect(await w.journal.bindUid('U'), isFalse);
      expect(w.opened, openedByWipe, reason: 'bindUid never asked the factory');
      expect(await w.scopeDirs(), dirsAfterWipe, reason: 'no directory created');
      expect(await w.snapshot('U'), isEmpty, reason: 'no file');
      expect(w.storage.values, isEmpty, reason: 'no key');
      expect(w.journal.isBound, isFalse);
    });

    test('bindUid(null) clears the marker: bindUid(U) succeeds again',
        () async {
      await w.journal.wipeForUid('U');
      expect(await w.journal.bindUid('U'), isFalse);
      expect(await w.journal.bindUid(null), isTrue);
      final openedBefore = w.opened.length;
      expect(await w.journal.bindUid('U'), isTrue);
      expect(w.opened.length, openedBefore + 1, reason: 'now the scope opens');
      expect(w.journal.boundUid, 'U');
    });

    test('another uid clears the marker too', () async {
      await w.journal.wipeForUid('U');
      expect(await w.journal.bindUid('V'), isTrue);
      expect(await w.journal.bindUid('U'), isTrue);
    });

    test('queued: bindUid(U) blocked in the factory, wipeForUid(U) behind it: '
        'afterwards U is refused', () async {
      w.gate = Completer<void>();
      final gate = w.gate!;
      final bind = w.journal.bindUid('U');
      final wipe = w.journal.wipeForUid('U');
      await pumpEventQueue();
      gate.complete();
      await bind;
      await wipe;
      expect(w.journal.isBound, isFalse);
      expect(await w.journal.bindUid('U'), isFalse);
      expect(w.storage.values, isEmpty, reason: 'no key remains for U');
    });

    test('queued the other way: wipeForUid(U) first, then bindUid(U): refused '
        'and nothing created', () async {
      final wipe = w.journal.wipeForUid('U');
      final bind = w.journal.bindUid('U');
      await wipe;
      expect(await bind, isFalse);
      expect(w.opened.length, 1, reason: 'only the wipe opened the scope');
      expect(w.journal.isBound, isFalse);
      expect(await w.snapshot('U'), isEmpty);
      expect(w.storage.values, isEmpty);
    });
  });
}

/// Delegates to a real journal; `list()` can be made to fail.
class _ListJournal extends Fake implements ActivityJournal {
  _ListJournal(this._inner);
  final ActivityJournal _inner;
  bool fail = false;

  @override
  Future<List<JournalEntry>> list() async {
    if (fail) throw StateError('list failed');
    return _inner.list();
  }

  @override
  Future<List<JournalEntry>> listTombstones() => _inner.listTombstones();
}
