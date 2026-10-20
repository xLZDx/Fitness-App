// S02 remediation E1 (test epic 11a, replaces the owner-marker version of epic
// 10b). Oracles: docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md (FL5, FL6),
// S02_REMEDIATION_E_TEST_NOTES.md heading E1 and S02_DESIGN.md 5.2 item 4, 6.2,
// 7, not the wiring code.
//
// `activityCloudSyncWiringProvider` listens to the auth user:
//  - uid A -> B, A -> null, A -> guest: `cancelQueued()` on the uploader;
//  - `resume()` only after `bindUid(newUid)` succeeded and the auth uid is still
//    that uid; a failed bind calls neither `resume`, `syncAll` nor `runPending`;
//  - nothing thrown inside the unawaited closure escapes.
// `activityJournalBindingProvider` (always on with a journal flag) binds the
// signed-in uid (anonymous included), unbinds on sign-out and deletes nothing.
//
// The journal is the REAL scoped journal over real files (ScopedJournalWorld).
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
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

class _Uploader extends Fake implements ActivityStreamUploader {
  _Uploader(this.events, this.journal);
  final List<String> events;
  final UidScopedActivityJournal journal;
  Object? resumeError;

  @override
  void cancelQueued() => events.add('cancel');

  @override
  void resume() {
    events.add('resume:${journal.boundUid}');
    if (resumeError != null) throw resumeError!;
  }

  @override
  Future<void> runPending() async => events.add('run');
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  _Settings(this.events);
  final List<String> events;
  Object? loadError;
  int resets = 0;

  @override
  void reset() => resets++;

  @override
  Future<void> load() async {
    events.add('load');
    if (loadError != null) throw loadError!;
  }
}

class _Consent extends AccountScopedConsentStore {
  _Consent(this.events);
  final List<String> events;

  @override
  Future<void> signIn(String uid) async => events.add('signIn:$uid');
}

/// A sync repository whose `syncAll` throws.
class _ThrowingSyncRepo extends Fake implements ActivitySyncRepository {
  _ThrowingSyncRepo(this.events);
  final List<String> events;

  @override
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) async {
    events.add('syncAll');
    throw StateError('sync exploded');
  }

  @override
  void onAccountChanged() {
    events.add('onAccountChanged');
  }

  @override
  void onJournalBindingChanged() {
    events.add('onJournalBindingChanged');
  }

  @override
  Future<void> dispose() async {}
}

AuthUser user(String uid, {AuthProvider p = AuthProvider.google, String? n}) =>
    AuthUser(uid: uid, displayName: n ?? uid, provider: p);

void main() {
  late ScopedJournalWorld w;
  late List<String> events;
  late _Uploader uploader;
  late _Settings settings;
  late _Consent consent;
  late FakeSummaryBackend backend;
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() async {
    w = await ScopedJournalWorld.create();
    events = [];
    uploader = _Uploader(events, w.journal);
    settings = _Settings(events);
    consent = _Consent(events);
    backend = FakeSummaryBackend();
    auth = StreamController<AuthUser?>();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
    await w.dispose();
  });

  ProviderContainer container({
    ActivityFlags flags = const ActivityFlags(cloudSync: true),
    ActivitySyncRepository? repo,
    bool cloud = true,
    ActivityJournal? journal,
  }) {
    final overrides = <Override>[
      activityFlagsProvider.overrideWithValue(flags),
      activityJournalProvider.overrideWithValue(journal ?? w.journal),
      authUserProvider.overrideWith((ref) => auth.stream),
    ];
    if (cloud) {
      final syncRepo =
          repo ?? ActivitySyncRepository(journal: w.journal, backend: backend);
      addTearDown(syncRepo.dispose);
      overrides.addAll([
        activitySyncRepositoryProvider.overrideWithValue(syncRepo),
        activityStreamUploaderProvider.overrideWithValue(uploader),
        activityCloudSettingsClientProvider.overrideWithValue(settings),
        activityConsentStoreProvider.overrideWithValue(consent),
      ]);
    }
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'condition was not reached: $events $logs');
  }

  /// Real time for every pending microtask, timer and file operation, for the
  /// "nothing further happens" assertions (each has a positive control).
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  int count(String e) => events.where((x) => x == e).length;
  int runs() => count('run');

  group('cancelQueued on an account change', () {
    test('A -> B: cancel is called, and only then resume for B', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      expect(count('cancel'), 0, reason: 'first sign-in cancels nothing');
      expect(events.indexOf('resume:A'), lessThan(events.indexOf('run')));

      events.clear();
      await emit(user('B'));
      await until(() => runs() == 1);
      expect(events.first, 'cancel', reason: 'cancel before anything else');
      expect(count('cancel'), 1);
      expect(events.indexOf('cancel'), lessThan(events.indexOf('resume:B')),
          reason: 'resumed only with B\'s journal bound');
      expect(events, contains('signIn:B'));
    });

    test('A -> null: cancel is called, nothing resumes, no new run', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);

      events.clear();
      await emit(null);
      await settle();
      expect(events, ['cancel']);
    });

    test('A -> guest: cancel is called, nothing resumes, no new run',
        () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);

      events.clear();
      await emit(user('G', p: AuthProvider.anonymous));
      await settle();
      expect(events, ['cancel']);
    });

    test('a guest is never synced and cancels nothing on its own', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('G', p: AuthProvider.anonymous));
      await settle();
      expect(events, isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('first sign-in (no previous account): no cancel', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      expect(count('cancel'), 0);
    });

    test('same uid re-emitted (profile change): no cancel, no second run',
        () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      events.clear();
      await emit(user('A', n: 'Renamed'));
      await settle();
      expect(events, isEmpty);
    });

    test('A -> B -> A: cancel on each leave, a fresh run each time, and each '
        'resume sees the matching journal bound', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      await emit(user('B'));
      await until(() => runs() == 2);
      await emit(user('A'));
      await until(() => runs() == 3);
      expect(count('cancel'), 2);
      expect(events.where((e) => e.startsWith('resume')),
          ['resume:A', 'resume:B', 'resume:A']);
    });
  });

  group('resume only after a successful bind', () {
    test('successful bind: the uid is bound before resume, then sync, then '
        'run', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => runs() == 1);
      expect(events.indexOf('resume:B'), isNonNegative,
          reason: 'B was bound when the uploader resumed');
      expect(events.indexOf('resume:B'), lessThan(events.indexOf('run')));
      expect(backend.count('listTombstoneIds'), 1, reason: 'syncAll ran');
      expect(w.journal.boundUid, 'B');
    });

    test('the bind fails: no resume, no syncAll, no run; the consent is still '
        'loaded (remediation I2); A\'s data kept', () async {
      await w.journal.bindUid('A');
      await w.journal.put(journalSession(idFor(1), seed: 1));
      await w.journal.bindUid(null);
      final a = await w.snapshot('A');
      w.failOpen.add(activityJournalScopeId('B'));
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('journal bind failed')));
      await settle();
      expect(events.where((e) => e.startsWith('resume')), isEmpty);
      expect(runs(), 0);
      expect(count('signIn:B'), 1, reason: 'consent is bound before the bind');
      expect(count('load'), 1);
      expect(backend.calls, isEmpty, reason: 'no syncAll');
      expect(await w.snapshot('A'), a);
      expect(w.journal.boundUid, isNull);
    });

    test('A -> B with a failed bind keeps the uploader cancelled', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);

      w.failOpen.add(activityJournalScopeId('B'));
      events.clear();
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('journal bind failed')));
      await settle();
      expect(events, ['cancel', 'signIn:B', 'load'],
          reason: 'cancelled, B consent loaded (I2), and never resumed');
    });

    test('the uid changed to null while the bind ran: no resume, no sync, no '
        'run', () async {
      final gate = w.gate = Completer<void>();
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => w.opened.isNotEmpty);

      await emit(null); // the account goes away mid-bind
      gate.complete();
      await settle();
      expect(events.where((e) => e.startsWith('resume')), isEmpty);
      expect(runs(), 0);
      expect(count('load'), 1, reason: 'B consent loaded before the bind (I2)');
      expect(backend.calls, isEmpty);
      expect(count('cancel'), 1);
    });

    test('the uid changed to a guest while the bind ran: no resume', () async {
      final gate = w.gate = Completer<void>();
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => w.opened.isNotEmpty);
      await emit(user('G', p: AuthProvider.anonymous));
      gate.complete();
      await settle();
      expect(events.where((e) => e.startsWith('resume')), isEmpty);
      expect(runs(), 0);
    });

    test('with the always-on binding too: signing out mid-bind ends UNbound '
        '(the queued unbind runs after the slow bind) and B\'s data stays',
        () async {
      final gate = w.gate = Completer<void>();
      final c = container();
      c.read(activityJournalBindingProvider);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => w.opened.isNotEmpty);
      await emit(null);
      gate.complete();
      await until(() => w.journal.boundUid == null && w.opened.isNotEmpty);
      await settle();
      expect(w.journal.boundUid, isNull);
      expect(events.where((e) => e.startsWith('resume')), isEmpty);
      expect(runs(), 0);
    });
  });

  group('FL6: nothing escapes the unawaited closure', () {
    test('resume() throws: logged, nothing escapes, no sync or run', () async {
      uploader.resumeError = StateError('resume exploded');
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      // Remediation H: resume runs inside the stream-upload step, so the
      // failure is logged there (the outer defensive catch is not reached).
      await until(
          () => logs.any((l) => l.contains('start stream upload failed')));
      expect(logs.any((l) => l.contains('StateError')), isTrue);
      expect(runs(), 0);
      // The summary sync now runs BEFORE the resume (remediation H): it read
      // the tombstone list but wrote nothing.
      expect(backend.calls, ['listTombstoneIds']);
    });

    test('syncAll throws: logged, the stream upload still runs', () async {
      final c = container(repo: _ThrowingSyncRepo(events));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => runs() == 1);
      expect(count('syncAll'), 1);
      expect(logs.any((l) => l.contains('start sync failed')), isTrue);
    });

    test('settings.load throws (remediation I2): logged, nothing escapes, the '
        'bind and the sync still run; the real uploader gates on the unknown '
        'consent', () async {
      settings.loadError = StateError('offline');
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => runs() == 1);
      expect(logs.any((l) => l.contains('consent load failed (StateError)')),
          isTrue);
      expect(w.journal.boundUid, 'B');
      expect(backend.count('listTombstoneIds'), 1, reason: 'syncAll ran');
    });

    test('the journal cannot be opened: fails closed with a log line, '
        'nothing escapes', () async {
      w.failOpen.add(activityJournalScopeId('B'));
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.isNotEmpty);
      expect(logs.any((l) => l.contains('journal bind failed')), isTrue);
      expect(runs(), 0);
    });
  });

  group('flag off: no wiring side effects', () {
    for (final flags in const [
      ActivityFlags(),
      ActivityFlags(localJournal: true),
    ]) {
      test('$flags: sign-in and account switch trigger no sync wiring',
          () async {
        final c = container(flags: flags);
        c.read(activityCloudSyncWiringProvider);
        await emit(user('A'));
        await emit(user('B'));
        await emit(null);
        await settle();
        expect(events, isEmpty);
        expect(backend.calls, isEmpty);
        expect(w.opened, isEmpty,
            reason: 'the sync wiring opens nothing; binding is its own provider');
      });
    }

    test('control: the same sequence with cloudSync ON does act', () async {
      final c = container();
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      expect(events, isNotEmpty);
    });
  });

  group('always-on binding listener (activityJournalBindingProvider)', () {
    const local = ActivityFlags(localJournal: true);

    test('localJournal only: binds on sign-in (anonymous included), unbinds '
        'on sign-out, deletes nothing, constructs no network objects',
        () async {
      // No sync repository, uploader, settings or consent override: reading
      // any of them would throw or build a network object.
      final c = container(flags: local, cloud: false);
      c.read(activityJournalBindingProvider);

      await emit(user('A'));
      await until(() => w.journal.boundUid == 'A');
      await w.journal.put(journalSession(idFor(1), seed: 1));

      await emit(user('G', p: AuthProvider.anonymous));
      await until(() => w.journal.boundUid == 'G');
      expect([for (final e in await w.journal.list()) e.id], isEmpty,
          reason: 'the guest does not see A');
      await w.journal.put(journalSession(idFor(2), seed: 2));

      final snapA = await w.snapshot('A');
      final snapG = await w.snapshot('G');
      await emit(null);
      await until(() => w.journal.boundUid == null);
      expect(await w.snapshot('A'), snapA, reason: 'sign-out deleted nothing');
      expect(await w.snapshot('G'), snapG);
      expect(await w.journal.list(), isEmpty);

      await emit(user('A'));
      await until(() => w.journal.boundUid == 'A');
      expect([for (final e in await w.journal.list()) e.id], [idFor(1)]);
      expect(c.read(activityStreamUploaderProvider), isNull);
      expect(() => c.read(activitySyncRepositoryProvider), throwsA(anything));
      expect(w.storage.deletes, 0);
    });

    test('rapid A -> B -> null ends unbound; A -> B -> A ends on A', () async {
      final c = container(flags: local, cloud: false);
      c.read(activityJournalBindingProvider);
      await emit(user('A'));
      await emit(user('B'));
      await emit(null);
      await until(() => w.opened.length >= 2);
      await settle();
      expect(w.journal.boundUid, isNull);

      await emit(user('A'));
      await emit(user('B'));
      await emit(user('A'));
      await until(() => w.journal.boundUid == 'A');
      await settle();
      expect(w.journal.boundUid, 'A');
    });

    test('a loading or error auth state changes nothing', () async {
      final c = container(flags: local, cloud: false);
      c.read(activityJournalBindingProvider);
      await settle();
      expect(w.journal.boundUid, isNull, reason: 'loading: nothing bound');
      expect(w.opened, isEmpty);

      await emit(user('A'));
      await until(() => w.journal.boundUid == 'A');
      auth.addError(StateError('auth stream failed'));
      await settle();
      expect(w.journal.boundUid, 'A', reason: 'an error keeps the binding');
    });

    test('both flags off: nothing is bound or opened', () async {
      final c = container(flags: const ActivityFlags(), cloud: false);
      c.read(activityJournalBindingProvider);
      await emit(user('A'));
      await settle();
      expect(w.opened, isEmpty);
      expect(w.journal.boundUid, isNull);
    });

    test('no journal (null): the listener is a no-op',
        () async {
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(local),
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(c.dispose);
      c.read(activityJournalBindingProvider);
      await emit(user('A'));
      await settle();
      expect(w.opened, isEmpty);
    });

    test('cloud + binding: the sync wiring finds the uid already bound and '
        'the journal opens once (idempotent)', () async {
      final c = container(flags: const ActivityFlags(cloudSync: true, localJournal: true));
      c.read(activityJournalBindingProvider);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => runs() == 1);
      expect(w.journal.boundUid, 'A');
      expect(w.opened, [activityJournalScopeId('A')]);
    });
  });
}
