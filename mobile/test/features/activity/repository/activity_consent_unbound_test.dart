// S02 test epic 15: remediation I2, the consent contract with an unbound store
// and the early consent bind. Oracles: S02_REMEDIATION_H_TEST_NOTES.md heading
// I2 (items 7 to 12) and design 17 item 24.
//
// Part 1 (client level): over a store with no account, grant, withdraw and
// deleteCloudStreamsNow throw ConsentAccountChangedException before any state
// change or server call. Part 2 (startup closure, real client, real consent
// store, real uploader with a recording cloud): consent is bound and loaded
// before the journal bind and the sync, whatever those do.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/gated_prefs.dart';
import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stream_upload_world.dart';

class _Uploader extends Fake implements ActivityStreamUploader {
  int cancels = 0;
  @override
  void cancelQueued() => cancels++;
}

class _Repo extends Fake implements ActivitySyncRepository {
  final Map<int, Completer<void>> gates = {};
  int calls = 0;
  bool throwOnAccountChanged = false;
  int changed = 0;

  @override
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) async {
    final n = ++calls;
    final g = gates[n];
    if (g != null) await g.future;
    return const {};
  }

  @override
  void onAccountChanged() {
    changed++;
    if (throwOnAccountChanged) throw StateError('onAccountChanged exploded');
  }

  @override
  void onJournalBindingChanged() {}
  @override
  Future<void> dispose() async {}
}

/// The real store whose sign-in always fails.
class _ThrowingSignInStore extends AccountScopedConsentStore {
  @override
  Future<void> signIn(String uid) async => throw StateError('signIn exploded');
}

AuthUser user(String uid) =>
    AuthUser(uid: uid, displayName: uid, provider: AuthProvider.google);

const prefKeyA = 'activity.cloudStreamsConsent.A';

void main() {
  group('client level: an unbound store refuses before any effect', () {
    late FakeSettingsServer server;

    Map<String, CloudStreamsConsentStore Function()> stores() => {
          'in-memory default': () => InMemoryCloudStreamsConsentStore(),
          'account scoped before signIn': () {
            installPrefs({consentKeyA: 'granted'});
            return AccountScopedConsentStore();
          },
        };

    setUp(() => server = FakeSettingsServer());

    for (final entry in {
      'in-memory default': 0,
      'account scoped before signIn': 1,
    }.entries) {
      test('grant, withdraw and withdraw with delete throw: ${entry.key}',
          () async {
        final store = stores()[entry.key]!();
        expect(store.boundUid, isNull);
        final client =
            ActivityCloudSettingsClient(call: server.call, store: store);

        await expectLater(
            client.grant(), throwsA(isA<ConsentAccountChangedException>()));
        await expectLater(
            client.withdraw(), throwsA(isA<ConsentAccountChangedException>()));
        await expectLater(client.withdraw(deleteExisting: true),
            throwsA(isA<ConsentAccountChangedException>()));

        expect(server.requests, isEmpty, reason: 'the callable is never invoked');
        expect(client.state, CloudStreamsConsent.unknown);
        expect(client.consentUid, isNull);

        // No hidden "unpersisted withdrawal" was recorded: after binding the
        // store to A, load() reads the stored granted value.
        if (store is InMemoryCloudStreamsConsentStore) {
          store.boundUid = 'A';
          await store.write(CloudStreamsConsent.granted);
        } else if (store is AccountScopedConsentStore) {
          await store.signIn('A');
        }
        await client.load();
        expect(client.state, CloudStreamsConsent.granted,
            reason: 'a refused withdraw must not force withdrawn');
        expect(client.isGranted, isTrue);
        expect(client.consentUid, 'A');
      });
    }

    test('deleteCloudStreamsNow on an unbound client throws, sends nothing, '
        'and a later call after the bind sends exactly once', () async {
      final store = InMemoryCloudStreamsConsentStore();
      final client =
          ActivityCloudSettingsClient(call: server.call, store: store);
      final withdrawal =
          ActivityConsentWithdrawal(settings: client, uploader: _Uploader());

      await expectLater(withdrawal.deleteCloudStreamsNow(),
          throwsA(isA<ConsentAccountChangedException>()));
      expect(server.requests, isEmpty);

      store.boundUid = 'A';
      await withdrawal.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(1),
          reason: 'no requested key was recorded for the null account');
      await withdrawal.deleteCloudStreamsNow();
      expect(server.deleteRequests, hasLength(1), reason: 'once per account');
    });

    test('control: a bound store grants and withdraws as before', () async {
      final store = InMemoryCloudStreamsConsentStore(boundUid: 'A');
      final client =
          ActivityCloudSettingsClient(call: server.call, store: store);
      await client.grant();
      expect(client.isGranted, isTrue);
      await client.withdraw();
      expect(client.state, CloudStreamsConsent.withdrawn);
      expect(server.requests, hasLength(2));
    });
  });

  group('startup closure: consent is bound before the bind and the sync', () {
    late StreamUploadWorld sw;
    late ScopedJournalWorld scoped;
    late _Repo repo;
    late GatedPrefsStore prefs;
    late FakeSettingsServer server;
    late AccountScopedConsentStore store;
    late ActivityCloudSettingsClient client;
    late StreamController<AuthUser?> auth;
    late List<String> logs;
    late void Function(String? message, {int? wrapWidth}) savedDebugPrint;
    late ProviderContainer c;

    setUp(() async {
      scoped = await ScopedJournalWorld.create();
      auth = StreamController<AuthUser?>();
      logs = [];
      savedDebugPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      debugPrint = savedDebugPrint;
      unawaited(auth.close());
      await scoped.dispose();
    });

    /// [useScopedJournal]: the wiring binds the scoped journal (which may be
    /// made to fail); otherwise the plain journal of the upload world.
    Future<void> build(Map<String, Object> stored,
        {bool useScopedJournal = false,
        AccountScopedConsentStore? customStore}) async {
      sw = await StreamUploadWorld.open();
      addTearDown(sw.dispose);
      await sw.h.journal.put(journalSession(idFor(1), seed: 0));
      await sw.summarySync();
      prefs = installPrefs(stored);
      store = customStore ?? AccountScopedConsentStore();
      server = FakeSettingsServer();
      client = ActivityCloudSettingsClient(call: server.call, store: store);
      repo = _Repo();
      late final ActivityStreamUploader uploader;
      c = ProviderContainer(overrides: [
        activityFlagsProvider
            .overrideWithValue(const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(
            useScopedJournal ? scoped.journal : sw.h.journal),
        authUserProvider.overrideWith((ref) => auth.stream),
        activitySyncRepositoryProvider.overrideWithValue(repo),
        activityStreamUploaderProvider.overrideWith((ref) => uploader),
        activityCloudSettingsClientProvider.overrideWithValue(client),
        activityConsentStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      uploader = sw.makeUploader(
        consentView: client,
        currentUid: () => c.read(authUserProvider).valueOrNull?.uid,
      );
      c.read(activityCloudSyncWiringProvider);
    }

    Future<void> until(bool Function() done, String what) async {
      for (var i = 0; i < 600 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue, reason: 'not reached: $what $logs');
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 100));

    Future<void> emit(AuthUser? u) async {
      auth.add(u);
      await Future<void>.delayed(Duration.zero);
    }

    test('the journal bind fails: consent is still bound and loaded, nothing '
        'syncs, nothing uploads', () async {
      await build({consentKeyA: 'granted'}, useScopedJournal: true);
      scoped.failOpen.add(activityJournalScopeId('A'));
      await emit(user('A'));
      await until(
          () => logs.any((l) => l.contains('journal bind failed')), 'bind log');
      await settle();
      expect(store.boundUid, 'A');
      expect(client.isGranted, isTrue);
      expect(client.consentUid, 'A');
      expect(repo.calls, 0, reason: 'no sync without a bound journal');
      expect(sw.cloud.log, isEmpty, reason: 'no resume, no upload');
    });

    test('a withdraw during a pending syncAll is persisted and survives a '
        'later load; the upload after the release stays silent', () async {
      await build({consentKeyA: 'granted'});
      repo.gates[1] = Completer<void>();
      await emit(user('A'));
      await until(() => repo.calls == 1, 'A in syncAll');
      expect(client.isGranted, isTrue, reason: 'consent was loaded first');

      await client.withdraw(); // the store is bound: no exception
      final p = await SharedPreferences.getInstance();
      expect(p.getString(prefKeyA), 'withdrawn');
      expect(server.requests, hasLength(1));

      repo.gates[1]!.complete();
      await settle();
      await client.load();
      expect(client.state, CloudStreamsConsent.withdrawn);
      expect(sw.cloud.log, isEmpty, reason: 'withdrawn: nothing is uploaded');
    });

    test('an onAccountChanged that throws still unbinds the consent store and '
        'resets the settings', () async {
      final uncaught = <Object>[];
      // The container is created inside the guarded zone: the exception of the
      // listener is reported to the zone of its container.
      await runZonedGuarded(() async {
        await build({consentKeyA: 'granted'});
        await emit(user('A'));
        await until(() => sw.cloud.commits.length == 1, 'A uploads');
        expect(store.boundUid, 'A');
        expect(client.isGranted, isTrue);

        repo.throwOnAccountChanged = true;
        forgetPrefs();
        final gate = prefs.gateNext(); // hold B's sign-in so the null shows
        await emit(user('B'));
        await until(() => repo.changed == 1, 'account change handled');
        await settle();

        expect(store.boundUid, isNull,
            reason: 'unbound first, before onAccountChanged threw');
        expect(client.consentUid, isNull);
        expect(client.state, CloudStreamsConsent.unknown);
        expect(client.isGranted, isFalse);
        gate.complete();
        await settle();
      }, (e, s) => uncaught.add(e));
      expect(uncaught.whereType<StateError>(), isNotEmpty,
          reason: 'the throw surfaced (control: the fake did throw)');
      // A's stored consent is kept; B never uploaded under it.
      expect(sw.cloud.commits, hasLength(1));
    });

    test('a sign-in that throws: logged, the bind and the sync still run, '
        'consent stays unknown and nothing is uploaded', () async {
      await build({consentKeyA: 'granted'}, customStore: _ThrowingSignInStore());
      await emit(user('A'));
      await until(() => repo.calls == 1, 'sync ran');
      await settle();
      expect(logs.any((l) => l.contains('consent load failed (StateError)')),
          isTrue);
      expect(client.isGranted, isFalse);
      expect(store.boundUid, isNull);
      expect(sw.cloud.creates, isEmpty);
      expect(sw.cloud.puts, isEmpty);
      expect(sw.cloud.commits, isEmpty);
    });

    test('control: the same start with a working store uploads once',
        () async {
      await build({consentKeyA: 'granted'});
      await emit(user('A'));
      await until(() => sw.cloud.commits.length == 1, 'A uploads');
      expect(sw.cloud.creates, hasLength(1));
    });
  });
}
