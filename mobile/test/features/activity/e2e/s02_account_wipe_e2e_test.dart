// S02 E02 (085): delete account, kill, relaunch. Acceptance criterion of 085:
// after a relaunch with an auth failure, the journal directory and the caches
// hold no data and the key is gone.
//
// Three groups:
//  1. The journal wipe SEAM end to end (runs): real files on disk, the secure
//     key store, a kill, a relaunch with an auth failure, a kill in the middle
//     of the wipe at every file-system operation, the stale repository after the
//     wipe, the sign-out export offer.
//  2. The Dart half of E05 (runs): a queued offline summary put replayed against
//     the account-deletion fence is refused, never read as deletion, keeps the
//     local data until the wipe removes it.
//  3. The REAL APP FLOW: `AccountDeletionAction` and the pending-wipe relaunch
//     must empty the journal. The wipe object is built exactly as `main.dart`
//     builds it (`activityAwareLocalDataWipe` around `DeviceLocalDataWipe`).
//     These two tests were skipped as NOT WIRED in epic 7a (see
//     S02_TEST_FINDINGS_EPIC7.md); the wiring landed in remediation B2 and the
//     skip is gone.
import 'dart:io';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_journal_owner.dart';
import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_local_export.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart';

/// True when no activity data remains in journal, sources or quarantine. The
/// EMPTY `index.jsonl` written by the start-up recovery pass is not data.
Future<bool> noDataLeft(JournalHarness h) async {
  const emptySha =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  for (final d in ['journal', 'sources', 'quarantine']) {
    for (final e in (await h.snapshot(d)).entries) {
      if (e.key == 'journal/index.jsonl' && e.value == emptySha) continue;
      return false;
    }
    for (final n in await h.names(d)) {
      if (n != 'index.jsonl') return false;
    }
  }
  return true;
}

Future<void> seedSideFiles(JournalHarness h) async {
  await h.writeText('sources/garmin.cursor.json', '{"cursor":1}');
  await h.writeText('sources/queue-1.json', '{"queued":true}');
  await h.writeText('quarantine/rejected-1.json', '{"raw":1}');
}

/// A journal with [n] sessions, the first half synced, side files, tombstone.
Future<void> seed(JournalHarness h, {int n = 12}) async {
  for (var i = 1; i <= n; i++) {
    await h.journal.put(journalSession(idFor(i), seed: i),
        syncState: i <= n ~/ 2 ? JournalSyncState.synced : null);
  }
  await h.journal.delete(idFor(n));
  await seedSideFiles(h);
}

class _Hooks implements ActivitySignOutHooks {
  _Hooks(this.confirm, {this.export});

  final bool confirm;
  final ActivityLocalExport? export;
  final List<String> calls = [];
  List<ActivityExportResult> offered = const [];

  @override
  Future<void> offerExport(SignOutAssessment a) async {
    calls.add('offerExport');
    offered = await export?.exportAll(ActivityExportFormat.json) ?? const [];
  }

  @override
  Future<bool> confirmWipe(SignOutAssessment a) async {
    calls.add('confirmWipe');
    return confirm;
  }
}

class _AuthRepo implements AuthRepository {
  _AuthRepo(this.uid);
  final String uid;
  int signOuts = 0;
  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(AuthUser(uid: uid, displayName: uid));
  @override
  AuthUser? get currentUser => AuthUser(uid: uid, displayName: uid);
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  group('1. journal wipe seam, end to end', () {
    late JournalHarness h;
    late FakeJournalSecureStorage storage;

    setUp(() async {
      storage = FakeJournalSecureStorage();
      h = JournalHarness.memory();
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      await h.open();
    });

    tearDown(() => h.dispose());

    test('delete account, kill, relaunch with an auth failure: journal, '
        'sources, quarantine, queue files and the key are gone, and stay gone '
        'over further relaunches', () async {
      await seed(h);
      expect(await noDataLeft(h), isFalse, reason: 'precondition');
      expect(storage.values, isNotEmpty, reason: 'precondition: a key exists');
      final oldKey = await h.keys.loadKey();

      await h.restart(); // the kill: the process dies, nothing was wiped
      expect(await h.listIds(), hasLength(11), reason: 'data survives the kill');

      await ActivityWipeCoordinator(h.journal).onAuthFailureAtLaunch();

      expect(await noDataLeft(h), isTrue);
      expect(await h.journal.list(), isEmpty);
      expect(await h.journal.listTombstones(), isEmpty);
      expect(storage.values, isEmpty, reason: 'the key left the secure store');
      expect(await h.keys.loadKey(), isNull);
      expect((await h.journal.assessSignOut()).entryCount, 0);

      for (var i = 0; i < 2; i++) {
        await h.restart();
        expect(await h.listIds(), isEmpty, reason: 'relaunch ${i + 1}');
        expect(await noDataLeft(h), isTrue, reason: 'relaunch ${i + 1}');
      }
      // The journal is usable again, with a NEW key.
      await h.journal.put(journalSession(idFor(50), seed: 50));
      expect((await h.journal.read(idFor(50)))!.streamLost, isFalse);
      expect(await h.keys.loadKey(), isNot(oldKey));
    });

    test('control: a relaunch WITHOUT an auth failure keeps everything',
        () async {
      await seed(h);
      Future<Map<String, String>> entries() async => {
            for (final e in (await h.snapshot('journal')).entries)
              if (e.key != 'journal/index.jsonl' && !e.key.contains(idFor(12)))
                e.key: e.value,
          };
      final before = await entries();
      await h.restart();
      await h.restart();
      expect(await h.listIds(), hasLength(11));
      expect(await noDataLeft(h), isFalse);
      expect(storage.values, isNotEmpty);
      expect(await entries(), before, reason: 'no file of a live activity changed');
    });

    test('the wipe is killed at EVERY file-system operation; the next '
        'relaunch with the auth failure always finishes it', () async {
      // Count the operations of one complete wipe.
      await seed(h, n: 4);
      h.fs.clearLog();
      await ActivityWipeCoordinator(h.journal).onAccountDeleted();
      final total = h.fs.opCount;
      expect(total, greaterThan(3), reason: 'the wipe must do real work');
      await h.dispose();

      for (var op = 0; op < total; op++) {
        final storage2 = FakeJournalSecureStorage();
        final hh = JournalHarness.memory();
        hh.keys = SecureStorageJournalKeyProvider(storage: storage2);
        await hh.open();
        await seed(hh, n: 4);
        hh.fs.arm(FaultPlan(op, FaultMode.crashAfter));
        Object? crash;
        try {
          await ActivityWipeCoordinator(hh.journal).onAccountDeleted();
        } catch (e) {
          crash = e;
        }
        expect(hh.fs.fired, isTrue, reason: 'op $op was reached');
        expect(crash, isA<SimulatedCrash>(), reason: 'op $op');

        await hh.restart(); // relaunch after the kill: must open, not throw
        await ActivityWipeCoordinator(hh.journal).onAuthFailureAtLaunch();
        expect(await noDataLeft(hh), isTrue, reason: 'after kill at op $op');
        expect(storage2.values, isEmpty, reason: 'key after kill at op $op');
        await hh.restart();
        expect(await hh.listIds(), isEmpty, reason: 'op $op');
        await hh.dispose();
      }
    });

    test('a repository that outlives the wipe finds nothing to push and the '
        'cloud copy is not touched by the device wipe', () async {
      final server = FakeFirestoreServer();
      final backend = DeviceBackend('A', server);
      final repo = ActivitySyncRepository(
          journal: h.journal, backend: backend, clock: h.clock.call);
      addTearDown(repo.dispose);
      for (var i = 1; i <= 5; i++) {
        expect(await repo.saveSession(journalSession(idFor(i), seed: i)),
            SyncOutcome.synced);
      }
      expect(server.docs, hasLength(5));
      await ActivityWipeCoordinator(h.journal).onAccountDeleted();

      expect(await repo.syncAll(), isEmpty);
      expect((await repo.refreshState()).conflicts, isEmpty);
      expect(server.accepted, hasLength(5), reason: 'no write after the wipe');
      expect(server.refused, isEmpty);
      expect(server.docs, hasLength(5),
          reason: 'the server rows are removed by the deleteAccount function, '
              'not by the device wipe');
    });

    test('confirmed sign-out: the export is offered first with every live '
        'activity, then the wipe empties everything', () async {
      await seed(h);
      final hooks = _Hooks(true, export: JournalActivityLocalExport(h.journal));
      expect(await ActivityWipeCoordinator(h.journal).onSignOut(hooks), isTrue);
      expect(hooks.calls, ['offerExport', 'confirmWipe']);
      expect(hooks.offered.whereType<ActivityExportFile>(), hasLength(11),
          reason: 'all 11 live activities were exported before the wipe');
      expect(await noDataLeft(h), isTrue);
      expect(storage.values, isEmpty);
    });

    test('declined sign-out keeps everything, also over a relaunch', () async {
      await seed(h);
      final hooks = _Hooks(false);
      expect(await ActivityWipeCoordinator(h.journal).onSignOut(hooks), isFalse);
      await h.restart();
      expect(await h.listIds(), hasLength(11));
      expect((await h.journal.read(idFor(1)))!.streamLost, isFalse);
    });
  });

  group('2. offline replay against the deletion fence (Dart half of E05)', () {
    late World w;

    setUp(() async => w = await World.open());
    tearDown(() => w.dispose());

    test('a queued offline put replayed while the fence exists is refused, is '
        'not read as deletion, no hot loop; the wipe then removes the data',
        () async {
      final id = await w.bothSynced();
      await w.a.changeOffline(id, distanceM: 5000); // the queued put
      expect(await w.a.syncState(id), isNot(JournalSyncState.synced));
      final accepted = w.server.accepted.length;

      // (a) fence written, (b) Auth user deleted, (c) late sweep done: from the
      // client the fence is the same refusal each time.
      w.server.accountFence = true;
      for (final stage in ['between step 1 and the first sweep',
        'after Auth deletion', 'after lateSweepDone']) {
        final before = w.a.backend.count('writeSummary');
        final out = await w.a.repo.syncEntry(id);
        expect(out, isNot(SyncOutcome.synced), reason: stage);
        expect(out, isNot(SyncOutcome.deletedLocal),
            reason: '$stage: a fence refusal is not a tombstone');
        expect(w.server.accepted, hasLength(accepted),
            reason: '$stage: nothing was accepted');
        expect(w.server.refused.last.reason, 'fence', reason: stage);
        expect(w.a.backend.count('writeSummary') - before, lessThanOrEqualTo(2),
            reason: '$stage: no retry loop within one pass');
        expect(await w.a.h.listIds(), [id], reason: '$stage: local data kept');
        expect(await w.a.syncState(id), isNot(JournalSyncState.synced));
      }
      await w.a.restart();
      await w.a.repo.syncAll();
      expect(w.server.accepted, hasLength(accepted),
          reason: 'still refused after a restart');
      expect(await w.a.h.listIds(), [id]);

      // The account deletion wipe removes the local data.
      await ActivityWipeCoordinator(w.a.h.journal).onAccountDeleted();
      expect(await noDataLeft(w.a.h), isTrue);
      expect(await w.a.repo.syncAll(), isEmpty);
      expect(w.server.accepted, hasLength(accepted));
    });

    test('control: without the fence the same queued put is accepted',
        () async {
      final id = await w.bothSynced();
      await w.a.changeOffline(id, distanceM: 5000);
      final out = await w.a.repo.syncEntry(id);
      expect(out, SyncOutcome.synced);
      expect(w.server.docs[id]!['distanceM'], 5000);
    });
  });

  group('3. real app flow (journal wipe wired through the decorator)', () {
    late Directory docs;
    late SharedPreferences prefs;
    late JournalHarness h;
    late FakeJournalSecureStorage storage;

    setUp(() async {
      docs = await Directory.systemTemp.createTemp('s02_e02_docs');
      addTearDown(() async {
        if (await docs.exists()) await docs.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({
        'activity.cloudStreamsConsent.A': 'granted',
        'activity.cloudStreamsConsent.B': 'granted',
      });
      prefs = await SharedPreferences.getInstance();
      storage = FakeJournalSecureStorage();
      h = JournalHarness.memory();
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      await h.open();
      addTearDown(h.dispose);
    });

    // Called after `h.restart()` where a restart happens, so the decorator
    // always wraps the CURRENT journal instance.
    LocalDataWipe wipeImpl() => activityAwareLocalDataWipe(
        DeviceLocalDataWipe(
            prefs: prefs, documentsDir: docs, forgetPhotoKey: (_) async {}),
        h.journal,
        ownerStore: InMemoryActivityJournalOwnerStore());

    ProviderContainer container(PendingWipeMarker marker, _AuthRepo auth) {
      final c = ProviderContainer(overrides: [
        accountDeletionServiceProvider
            .overrideWithValue(MockAccountDeletionService()),
        // The composition of main.dart: the real device wipe.
        localDataWipeProvider.overrideWithValue(wipeImpl()),
        pendingWipeMarkerProvider.overrideWithValue(marker),
        authRepositoryProvider.overrideWithValue(auth),
        notificationServiceProvider.overrideWithValue(MockNotificationService()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('the per-account activity consent cache is erased with the account '
        'and another account keeps its own', () async {
      final c = container(InMemoryPendingWipeMarker(), _AuthRepo('A'));
      await c.read(accountDeletionActionProvider.notifier).deleteAccount();
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
      expect(prefs.containsKey('activity.cloudStreamsConsent.A'), isFalse,
          reason: 'consent cache of the deleted account');
      expect(prefs.containsKey('activity.cloudStreamsConsent.B'), isTrue);
    });

    test('deleting the account empties the activity journal', () async {
      await seed(h);
      final c = container(InMemoryPendingWipeMarker(), _AuthRepo('A'));
      await c.read(accountDeletionActionProvider.notifier).deleteAccount();
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
      expect(await noDataLeft(h), isTrue, reason: 'journal after deletion');
      expect(storage.values, isEmpty, reason: 'journal key after deletion');
      expect(prefs.containsKey('activity.cloudStreamsConsent.A'), isFalse,
          reason: 'the inner prefs wipe ran as well');
      expect(prefs.containsKey('activity.cloudStreamsConsent.B'), isTrue);
    });

    test('killed after the server confirmed: the next launch finishes the '
        'wipe including the journal', () async {
      await seed(h);
      final marker = InMemoryPendingWipeMarker();
      await marker.add('A'); // the process died right after the server call
      await h.restart();
      final wiped = await finishInterruptedWipe(
          marker: marker, wipe: wipeImpl(), signedInUid: null);
      expect(wiped, isTrue);
      expect(await marker.read(), isEmpty);
      expect(await noDataLeft(h), isTrue, reason: 'journal after relaunch');
      expect(storage.values, isEmpty);
      expect(prefs.containsKey('activity.cloudStreamsConsent.A'), isFalse,
          reason: 'the inner prefs wipe ran as well');
    });
  });
}
