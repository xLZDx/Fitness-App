// S02 test epic 10b: remediation C item FL5 (wiring) and FL6. Oracle:
// docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md (FL5 wiring, FL6) and
// S02_DESIGN.md 5.2 item 4, not the wiring code.
//
// `activityCloudSyncWiringProvider` listens to the auth user:
//  - uid A -> B, A -> null, A -> guest: `cancelQueued()` on the uploader;
//  - `resume()` only after `claimActivityJournal` succeeded for the new uid and
//    the auth uid is still that uid;
//  - a failed claim calls neither `resume`, `syncAll` nor `runPending`;
//  - nothing thrown inside the unawaited closure escapes (a thrown error that
//    escaped would be an uncaught zone error and fail the test); a debugPrint
//    line is produced instead.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_journal_owner.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

/// Real journal underneath; `wipe()` can fail.
class _Journal extends Fake implements ActivityJournal {
  _Journal(this.inner);
  final ActivityJournal inner;
  bool failWipe = false;

  @override
  Future<void> wipe() async {
    if (failWipe) throw StateError('disk error');
    await inner.wipe();
  }

  @override
  Future<List<JournalEntry>> list() => inner.list();

  @override
  Future<List<JournalEntry>> listTombstones() => inner.listTombstones();
}

class _OwnerStore implements ActivityJournalOwnerStore {
  _OwnerStore([this.uid, this.events]);
  String? uid;
  final List<String>? events;
  bool failWrite = false;

  /// When set, `write` waits for it (the claim is "running").
  Completer<void>? gate;

  @override
  Future<String?> read() async => uid;

  @override
  Future<void> write(String value) async {
    events?.add('write:$value');
    if (gate != null) await gate!.future;
    if (failWrite) throw StateError('prefs write refused');
    uid = value;
  }

  @override
  Future<void> clear() async => uid = null;
}

class _Uploader extends Fake implements ActivityStreamUploader {
  _Uploader(this.events);
  final List<String> events;
  Object? resumeError;

  @override
  void cancelQueued() => events.add('cancel');

  @override
  void resume() {
    events.add('resume');
    if (resumeError != null) throw resumeError!;
  }

  @override
  Future<void> runPending() async => events.add('run');
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  _Settings(this.events);
  final List<String> events;
  Object? loadError;

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

/// A backend whose reads throw (a failing `syncAll`).
class _ThrowingSyncRepo extends Fake implements ActivitySyncRepository {
  _ThrowingSyncRepo(this.events);
  final List<String> events;

  @override
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) async {
    events.add('syncAll');
    throw StateError('sync exploded');
  }

  @override
  Future<void> dispose() async {}
}

AuthUser user(String uid, {AuthProvider p = AuthProvider.google, String? n}) =>
    AuthUser(uid: uid, displayName: n ?? uid, provider: p);

void main() {
  late JournalHarness h;
  late _Journal journal;
  late List<String> events;
  late _Uploader uploader;
  late _Settings settings;
  late _Consent consent;
  late FakeSummaryBackend backend;
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    journal = _Journal(h.journal);
    events = [];
    uploader = _Uploader(events);
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
    // Not awaited: with no listener (flag off) close() would wait for one.
    unawaited(auth.close());
    await h.dispose();
  });

  ProviderContainer container(
    _OwnerStore owner, {
    ActivityFlags flags = const ActivityFlags(cloudSync: true),
    ActivitySyncRepository? repo,
  }) {
    final syncRepo = repo ?? ActivitySyncRepository(journal: journal, backend: backend);
    addTearDown(syncRepo.dispose);
    final c = ProviderContainer(overrides: [
      activityFlagsProvider.overrideWithValue(flags),
      activityJournalProvider.overrideWithValue(journal),
      activityJournalOwnerStoreProvider.overrideWithValue(owner),
      activitySyncRepositoryProvider.overrideWithValue(syncRepo),
      activityStreamUploaderProvider.overrideWithValue(uploader),
      activityCloudSettingsClientProvider.overrideWithValue(settings),
      activityConsentStoreProvider.overrideWithValue(consent),
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(done(), isTrue, reason: 'condition was not reached: $events $logs');
  }

  /// Lets every pending microtask and zero-delay timer run, for the "nothing
  /// further happens" assertions (each has a positive control in this file).
  Future<void> settle() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  int count(String e) => events.where((x) => x == e).length;

  group('cancelQueued on an account change', () {
    test('A -> B: cancel is called, and only then resume for B', () async {
      final c = container(_OwnerStore('A'));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);
      expect(count('cancel'), 0, reason: 'first sign-in cancels nothing');
      expect(events.indexOf('resume'), lessThan(events.indexOf('run')));

      events.clear();
      await emit(user('B'));
      await until(() => count('run') == 1);
      expect(events.first, 'cancel', reason: 'cancel before anything else');
      expect(count('cancel'), 1);
      expect(events.indexOf('cancel'), lessThan(events.indexOf('resume')));
      expect(events, contains('signIn:B'));
    });

    test('A -> null: cancel is called, nothing resumes, no new run',
        () async {
      final c = container(_OwnerStore('A'));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);

      events.clear();
      await emit(null);
      await settle();
      expect(events, ['cancel']);
    });

    test('A -> guest: cancel is called, nothing resumes, no new run',
        () async {
      final c = container(_OwnerStore('A'));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);

      events.clear();
      await emit(user('G', p: AuthProvider.anonymous));
      await settle();
      expect(events, ['cancel']);
    });

    test('a guest is never synced and cancels nothing on its own', () async {
      final c = container(_OwnerStore());
      c.read(activityCloudSyncWiringProvider);
      await emit(user('G', p: AuthProvider.anonymous));
      await settle();
      expect(events, isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('first sign-in (no previous account): no cancel', () async {
      final c = container(_OwnerStore());
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);
      expect(count('cancel'), 0);
    });

    test('same uid re-emitted (profile change): no cancel, no second run',
        () async {
      final c = container(_OwnerStore('A'));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);
      events.clear();
      await emit(user('A', n: 'Renamed'));
      await settle();
      expect(events, isEmpty);
    });

    test('A -> B -> A: cancel on each leave, a fresh run each time', () async {
      final c = container(_OwnerStore('A'));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);
      await emit(user('B'));
      await until(() => count('run') == 2);
      await emit(user('A'));
      await until(() => count('run') == 3);
      expect(count('cancel'), 2);
      expect(count('resume'), 3);
    });
  });

  group('resume only after a successful claim', () {
    test('successful claim: write happens before resume, then sync, then run',
        () async {
      final owner = _OwnerStore(null, events);
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => count('run') == 1);
      expect(events.indexOf('write:B'), lessThan(events.indexOf('resume')));
      expect(events.indexOf('resume'), lessThan(events.indexOf('run')));
      expect(backend.count('listTombstoneIds'), 1, reason: 'syncAll ran');
    });

    test('claim fails (marker write refused): no resume, no syncAll, no run',
        () async {
      final owner = _OwnerStore(null, events)..failWrite = true;
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('owner check failed')));
      await settle();
      expect(count('resume'), 0);
      expect(count('run'), 0);
      expect(count('load'), 0);
      expect(backend.calls, isEmpty, reason: 'no syncAll');
    });

    test('claim fails (wipe of the previous owner fails): no resume, no '
        'syncAll, no run', () async {
      await h.journal.put(journalSession(idFor(1), seed: 1));
      journal.failWipe = true;
      final c = container(_OwnerStore('A', events));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('owner check failed')));
      await settle();
      expect(count('resume'), 0);
      expect(count('run'), 0);
      expect(backend.calls, isEmpty);
      expect(await h.listIds(), hasLength(1), reason: 'A\'s data is kept');
    });

    test('A -> B with a failed claim keeps the uploader cancelled', () async {
      final owner = _OwnerStore('A', events);
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);

      owner.failWrite = true;
      journal.failWipe = true;
      events.clear();
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('owner check failed')));
      await settle();
      expect(events.where((e) => e != 'write:B'), ['cancel'],
          reason: 'cancelled, and never resumed');
    });

    test('the uid changed to null while the claim ran: no resume, no sync, '
        'no run', () async {
      final owner = _OwnerStore(null, events)..gate = Completer<void>();
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => events.contains('write:B'));

      await emit(null); // the account goes away mid-claim
      owner.gate!.complete();
      await settle();
      expect(count('resume'), 0);
      expect(count('run'), 0);
      expect(count('load'), 0);
      expect(backend.calls, isEmpty);
      expect(count('cancel'), 1);
    });

    test('the uid changed to a guest while the claim ran: no resume', () async {
      final owner = _OwnerStore(null, events)..gate = Completer<void>();
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => events.contains('write:B'));
      await emit(user('G', p: AuthProvider.anonymous));
      owner.gate!.complete();
      await settle();
      expect(count('resume'), 0);
      expect(count('run'), 0);
    });

  });

  group('FL6: nothing escapes the unawaited closure', () {
    test('resume() throws: logged, nothing escapes, no sync or run',
        () async {
      uploader.resumeError = StateError('resume exploded');
      final c = container(_OwnerStore());
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('start wiring failed')));
      expect(logs.any((l) => l.contains('StateError')), isTrue);
      expect(count('run'), 0);
      expect(backend.calls, isEmpty);
    });

    test('syncAll throws: logged, the stream upload still runs', () async {
      final c = container(_OwnerStore(),
          repo: _ThrowingSyncRepo(events));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => count('run') == 1);
      expect(count('syncAll'), 1);
      expect(logs.any((l) => l.contains('start sync failed')), isTrue);
    });

    test('settings.load throws: logged, nothing escapes, no run', () async {
      settings.loadError = StateError('offline');
      final c = container(_OwnerStore());
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.any((l) => l.contains('start stream upload failed')));
      expect(count('run'), 0);
    });

    test('claim throws inside the closure (journal unusable): fails closed '
        'with a log line, nothing escapes', () async {
      final owner = _OwnerStore('A')..failWrite = true;
      journal.failWipe = true;
      final c = container(owner);
      c.read(activityCloudSyncWiringProvider);
      await emit(user('B'));
      await until(() => logs.isNotEmpty);
      expect(logs.any((l) => l.contains('owner check failed')), isTrue);
      expect(count('run'), 0);
    });
  });

  group('flag off: no listener side effects', () {
    for (final flags in const [
      ActivityFlags(),
      ActivityFlags(localJournal: true),
    ]) {
      test('$flags: sign-in and account switch touch nothing', () async {
        final owner = _OwnerStore('A', events);
        final c = container(owner, flags: flags);
        c.read(activityCloudSyncWiringProvider);
        await emit(user('A'));
        await emit(user('B'));
        await emit(null);
        await settle();
        expect(events, isEmpty);
        expect(backend.calls, isEmpty);
        expect(owner.uid, 'A', reason: 'no claim happened');
      });
    }

    test('control: the same sequence with cloudSync ON does act', () async {
      final c = container(_OwnerStore('A', events));
      c.read(activityCloudSyncWiringProvider);
      await emit(user('A'));
      await until(() => count('run') == 1);
      expect(events, isNotEmpty);
    });
  });
}
