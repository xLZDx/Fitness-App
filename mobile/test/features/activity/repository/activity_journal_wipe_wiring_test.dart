// S02 remediation B2 (test epic 9b): the journal wipe wiring and the owner
// guard. Oracles: docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md heading B2
// and S02_DESIGN.md sections 6.2, 7 and 17, not the code under test.
//
//  1. The decorator `ActivityAwareLocalDataWipe` / `activityAwareLocalDataWipe`.
//  2. The owner skip (a pending wipe of uid X never touches uid Y's journal).
//  3. `claimActivityJournal` (cross-account guard, fail closed).
//  4. `activityCloudSyncWiringProvider` (no sync and no upload unless the
//     signed-in uid owns the journal).
//
// Real file journal on the in-memory file system for every "is the data gone"
// assertion; the wrapper only counts and fails `wipe()`.
import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_journal_owner.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

/// Counts and optionally fails `wipe()`; everything the tests use otherwise
/// goes to the real journal.
class _Journal extends Fake implements ActivityJournal {
  _Journal(this.inner, [this.events]);

  final ActivityJournal inner;
  final List<String>? events;
  bool failWipe = false;
  int wipes = 0;

  @override
  Future<void> wipe() async {
    wipes++;
    events?.add('wipe');
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
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('prefs unreadable');
    return uid;
  }

  @override
  Future<void> write(String value) async {
    events?.add('write:$value');
    if (failWrite) throw StateError('prefs write refused');
    uid = value;
  }

  @override
  Future<void> clear() async {
    events?.add('clear');
    uid = null;
  }
}

/// An inner wipe that records and can fail with a given error.
class _Inner implements LocalDataWipe {
  _Inner([this.error]);

  final Object? error;
  final List<String> wiped = [];

  @override
  Future<void> wipe(String uid) async {
    wiped.add(uid);
    if (error != null) throw error!;
  }
}

class _Uploader extends Fake implements ActivityStreamUploader {
  int runs = 0;

  @override
  Future<void> runPending() async => runs++;
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  int loads = 0;

  @override
  Future<void> load() async => loads++;
}

class _Consent extends AccountScopedConsentStore {
  final List<String> signIns = [];

  @override
  Future<void> signIn(String uid) async => signIns.add(uid);
}

void main() {
  late JournalHarness h;
  late _Journal journal;

  Future<void> seed([int n = 3]) async {
    for (var i = 1; i <= n; i++) {
      await h.journal.put(journalSession(idFor(i), seed: i));
    }
  }

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    journal = _Journal(h.journal);
  });

  tearDown(() => h.dispose());

  group('1. the decorator', () {
    test('activityAwareLocalDataWipe(inner, null) returns inner itself', () {
      final inner = _Inner();
      expect(activityAwareLocalDataWipe(inner, null), same(inner));
    });

    test('with a journal it returns the decorator, not the inner object', () {
      final inner = _Inner();
      final wipe = activityAwareLocalDataWipe(inner, journal,
          ownerStore: _OwnerStore());
      expect(wipe, isNot(same(inner)));
      expect(wipe, isA<ActivityAwareLocalDataWipe>());
    });

    test('wipe(uid) runs the inner wipe, empties the journal and clears the '
        'owner', () async {
      await seed();
      final inner = _Inner();
      final owner = _OwnerStore('A');
      await ActivityAwareLocalDataWipe(
              inner: inner, journal: journal, ownerStore: owner)
          .wipe('A');
      expect(inner.wiped, ['A']);
      expect(journal.wipes, 1);
      expect(await h.listIds(), isEmpty);
      expect(owner.uid, isNull, reason: 'the marker is cleared after a wipe');
    });

    test('a journal wipe failure reports activity_journal in '
        'LocalWipeIncomplete and keeps the owner marker', () async {
      await seed();
      journal.failWipe = true;
      final owner = _OwnerStore('A');
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(), journal: journal, ownerStore: owner);
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['activity_journal'])));
      expect(owner.uid, 'A', reason: 'the owner stays while data remains');
      expect(await h.listIds(), hasLength(3), reason: 'nothing was wiped');
    });

    test('an owner store failure is also reported as activity_journal and '
        'the journal is not touched', () async {
      await seed();
      final owner = _OwnerStore('A')..failRead = true;
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(), journal: journal, ownerStore: owner);
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['activity_journal'])));
      expect(journal.wipes, 0);
      expect(await h.listIds(), hasLength(3));
    });

    test('an inner LocalWipeIncomplete still wipes the journal and is '
        'rethrown WITHOUT activity_journal when the journal wipe worked',
        () async {
      await seed();
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(LocalWipeIncomplete(['progress_photos'])),
          journal: journal,
          ownerStore: _OwnerStore('A'));
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['progress_photos'])));
      expect(journal.wipes, 1, reason: 'the inner failure did not skip it');
      expect(await h.listIds(), isEmpty);
    });

    test('an inner LocalWipeIncomplete plus a journal failure reports both, '
        'inner first', () async {
      await seed();
      journal.failWipe = true;
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(LocalWipeIncomplete(['progress_photos'])),
          journal: journal,
          ownerStore: _OwnerStore('A'));
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having((e) => e.remaining,
              'remaining', ['progress_photos', 'activity_journal'])));
    });

    test('a non-wipe inner error is rethrown as itself after the journal was '
        'wiped', () async {
      await seed();
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(StateError('boom')),
          journal: journal,
          ownerStore: _OwnerStore());
      await expectLater(wipe.wipe('A'), throwsA(isA<StateError>()));
      expect(await h.listIds(), isEmpty);
    });
  });

  group('2. relaunch path and the owner skip', () {
    test('finishInterruptedWipe with the decorator empties the journal and '
        'removes the pending marker', () async {
      await seed();
      final marker = InMemoryPendingWipeMarker()..add('A');
      final wiped = await finishInterruptedWipe(
        marker: marker,
        wipe: activityAwareLocalDataWipe(_Inner(), journal,
            ownerStore: _OwnerStore('A')),
        signedInUid: null,
      );
      expect(wiped, isTrue);
      expect(await marker.read(), isEmpty);
      expect(await h.listIds(), isEmpty);
    });

    test('a journal wipe failure keeps the pending marker; the next launch '
        'retries and finishes', () async {
      await seed();
      final marker = InMemoryPendingWipeMarker()..add('A');
      final wipe = activityAwareLocalDataWipe(_Inner(), journal,
          ownerStore: _OwnerStore('A'));

      journal.failWipe = true;
      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isFalse);
      expect(await marker.read(), {'A'}, reason: 'marker kept for the retry');
      expect(await h.listIds(), hasLength(3));
      expect(journal.wipes, 1);

      journal.failWipe = false; // the next launch
      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isTrue);
      expect(journal.wipes, 2, reason: 'the journal wipe was retried');
      expect(await marker.read(), isEmpty);
      expect(await h.listIds(), isEmpty);
    });

    test('pending wipe of X while the owner marker names Y leaves Y\'s '
        'journal and the marker alone', () async {
      await seed();
      final owner = _OwnerStore('Y');
      final inner = _Inner();
      final marker = InMemoryPendingWipeMarker()..add('X');
      final wiped = await finishInterruptedWipe(
        marker: marker,
        wipe: activityAwareLocalDataWipe(inner, journal, ownerStore: owner),
        signedInUid: 'Y',
      );
      expect(wiped, isTrue, reason: 'the wipe of X itself completed');
      expect(inner.wiped, ['X'], reason: 'the per-account wipe of X ran');
      expect(journal.wipes, 0, reason: 'Y\'s journal was not wiped');
      expect(await h.listIds(), hasLength(3));
      expect(owner.uid, 'Y');
      expect(await marker.read(), isEmpty);
    });

    test('owner marker equal to the wiped uid: journal wiped, marker cleared',
        () async {
      await seed();
      final owner = _OwnerStore('X');
      await ActivityAwareLocalDataWipe(
              inner: _Inner(), journal: journal, ownerStore: owner)
          .wipe('X');
      expect(journal.wipes, 1);
      expect(await h.listIds(), isEmpty);
      expect(owner.uid, isNull);
    });

    test('no owner marker (unclaimed journal): wiped with the deletion',
        () async {
      await seed();
      final owner = _OwnerStore();
      await ActivityAwareLocalDataWipe(
              inner: _Inner(), journal: journal, ownerStore: owner)
          .wipe('X');
      expect(journal.wipes, 1);
      expect(await h.listIds(), isEmpty);
    });
  });

  group('3. claimActivityJournal', () {
    test('another account\'s marker: wipe BEFORE the new owner is written, '
        'returns true, owner is the new uid', () async {
      await seed();
      final events = <String>[];
      final j = _Journal(h.journal, events);
      final store = _OwnerStore('A', events);
      expect(await claimActivityJournal(journal: j, store: store, uid: 'B'),
          isTrue);
      expect(events, ['wipe', 'write:B'], reason: 'wipe first, owner second');
      expect(store.uid, 'B');
      expect(await h.listIds(), isEmpty);
    });

    test('same uid: nothing is wiped, nothing is written, data stays',
        () async {
      await seed();
      final events = <String>[];
      final j = _Journal(h.journal, events);
      final store = _OwnerStore('A', events);
      expect(await claimActivityJournal(journal: j, store: store, uid: 'A'),
          isTrue);
      expect(events, isEmpty);
      expect(j.wipes, 0);
      expect(await h.listIds(), hasLength(3));
    });

    test('no marker: the journal is adopted without a wipe and the uid is '
        'recorded', () async {
      await seed();
      final events = <String>[];
      final j = _Journal(h.journal, events);
      final store = _OwnerStore(null, events);
      expect(await claimActivityJournal(journal: j, store: store, uid: 'B'),
          isTrue);
      expect(events, ['write:B']);
      expect(store.uid, 'B');
      expect(await h.listIds(), hasLength(3), reason: 'unclaimed data kept');
    });

    test('a wipe that throws returns false and the marker stays A',
        () async {
      await seed();
      final events = <String>[];
      final j = _Journal(h.journal, events)..failWipe = true;
      final store = _OwnerStore('A', events);
      expect(await claimActivityJournal(journal: j, store: store, uid: 'B'),
          isFalse);
      expect(store.uid, 'A');
      expect(events, ['wipe'], reason: 'B was never written');
      expect(await h.listIds(), hasLength(3));
    });

    test('a marker write that throws returns false', () async {
      final store = _OwnerStore(null)..failWrite = true;
      expect(
          await claimActivityJournal(journal: journal, store: store, uid: 'B'),
          isFalse);
      expect(store.uid, isNull);
    });

    test('an unreadable marker returns false and wipes nothing', () async {
      await seed();
      final store = _OwnerStore('A')..failRead = true;
      expect(
          await claimActivityJournal(journal: journal, store: store, uid: 'B'),
          isFalse);
      expect(journal.wipes, 0);
      expect(await h.listIds(), hasLength(3));
    });
  });

  group('4. the wiring provider (fail closed)', () {
    late FakeSummaryBackend backend;
    late _Uploader uploader;
    late _Settings settings;
    late _Consent consent;
    late List<String> logs;
    late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

    setUp(() {
      backend = FakeSummaryBackend();
      uploader = _Uploader();
      settings = _Settings();
      consent = _Consent();
      logs = [];
      savedDebugPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    });

    tearDown(() => debugPrint = savedDebugPrint);

    ProviderContainer container(_OwnerStore owner, String signedInUid) {
      final repo = ActivitySyncRepository(journal: journal, backend: backend);
      addTearDown(repo.dispose);
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(
            const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(journal),
        activityJournalOwnerStoreProvider.overrideWithValue(owner),
        activitySyncRepositoryProvider.overrideWithValue(repo),
        activityStreamUploaderProvider.overrideWithValue(uploader),
        activityCloudSettingsClientProvider.overrideWithValue(settings),
        activityConsentStoreProvider.overrideWithValue(consent),
        authUserProvider.overrideWith((ref) => Stream.value(AuthUser(
            uid: signedInUid,
            displayName: signedInUid,
            provider: AuthProvider.google))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    /// Waits (bounded, on a condition, no fixed sleep) until [done] holds.
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done(), isTrue, reason: 'condition was not reached');
    }

    test('owner A, signed-in B, wipe fails: no syncAll, no stream upload, '
        'the data of A is kept', () async {
      await seed();
      journal.failWipe = true;
      final owner = _OwnerStore('A');
      final c = container(owner, 'B');
      c.read(activityCloudSyncWiringProvider);

      await until((() => logs.any((l) => l.contains('owner check failed'))));
      expect(journal.wipes, 1);
      expect(backend.calls, isEmpty, reason: 'no syncAll (no backend call)');
      expect(uploader.runs, 0, reason: 'no stream upload');
      expect(settings.loads, 0);
      expect(consent.signIns, isEmpty, reason: 'no consent for B was loaded');
      expect(owner.uid, 'A');
      expect(await h.listIds(), hasLength(3));
    });

    test('owner A, signed-in B, wipe works: A\'s data is wiped, then both '
        'the sync and the upload start', () async {
      await seed();
      final owner = _OwnerStore('A');
      final c = container(owner, 'B');
      c.read(activityCloudSyncWiringProvider);

      await until(() => uploader.runs == 1);
      expect(journal.wipes, 1);
      expect(owner.uid, 'B');
      expect(await h.listIds(), isEmpty, reason: 'A\'s sessions are gone');
      expect(backend.count('listTombstoneIds'), 1, reason: 'syncAll ran');
      expect(consent.signIns, ['B']);
      expect(settings.loads, 1);
    });

    test('same uid: entries are kept, nothing wiped, sync and upload start',
        () async {
      await seed();
      final owner = _OwnerStore('A');
      final c = container(owner, 'A');
      c.read(activityCloudSyncWiringProvider);

      await until(() => uploader.runs == 1);
      expect(journal.wipes, 0);
      expect(await h.listIds(), hasLength(3));
      expect(backend.count('listTombstoneIds'), 1);
      expect(consent.signIns, ['A']);
    });

    test('unclaimed journal: adopted by the signed-in uid without a wipe',
        () async {
      await seed();
      final owner = _OwnerStore();
      final c = container(owner, 'B');
      c.read(activityCloudSyncWiringProvider);

      await until(() => uploader.runs == 1);
      expect(journal.wipes, 0);
      expect(owner.uid, 'B');
      expect(await h.listIds(), hasLength(3));
    });

    test('an unreadable owner marker fails closed as well', () async {
      await seed();
      final owner = _OwnerStore('A')..failRead = true;
      final c = container(owner, 'B');
      c.read(activityCloudSyncWiringProvider);

      await until((() => logs.any((l) => l.contains('owner check failed'))));
      expect(journal.wipes, 0);
      expect(backend.calls, isEmpty);
      expect(uploader.runs, 0);
      expect(await h.listIds(), hasLength(3));
    });
  });
}
