// S02 test epic 14a: remediation H-A startup wiring (`activityCloudSyncWiringProvider`).
// Oracles: S02_REMEDIATION_H_TEST_NOTES.md H-A items 13 and 16 to 19, S02_DESIGN.md
// 17 items 23 and 24 and the external finding: an obsolete startup of account A
// must never run a step for B, and B never uploads under A's consent.
//
// The REAL startup closure runs over a fake auth stream. Part 1 uses recording
// fakes to pin the order and the re-verification after each await. Part 2 uses
// the real settings client, the real consent store (opened through a gated
// platform store) and the real uploader with recording callables.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
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

class _Repo extends Fake implements ActivitySyncRepository {
  _Repo(this.events);
  final List<String> events;

  /// 1-based syncAll call number -> gate.
  final Map<int, Completer<void>> gates = {};
  int calls = 0;

  @override
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) async {
    final n = ++calls;
    events.add('sync');
    final g = gates[n];
    if (g != null) await g.future;
    return const {};
  }

  @override
  void onAccountChanged() => events.add('changed');
  @override
  void onJournalBindingChanged() {}
  @override
  Future<void> dispose() async {}
}

class _Uploader extends Fake implements ActivityStreamUploader {
  _Uploader(this.events);
  final List<String> events;
  @override
  void cancelQueued() => events.add('cancel');
  @override
  void resume() => events.add('resume');
  @override
  Future<void> runPending() async => events.add('run');
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  _Settings(this.events);
  final List<String> events;
  Object? loadError;
  Completer<void>? loadGate;
  @override
  void reset() => events.add('reset');
  @override
  Future<void> load() async {
    events.add('load');
    final g = loadGate;
    if (g != null) {
      loadGate = null;
      await g.future;
    }
    if (loadError != null) throw loadError!;
  }
}

/// The real store with a hook point: records and may hold a sign-in.
class _Consent extends AccountScopedConsentStore {
  _Consent(this.events);
  final List<String> events;
  Completer<void>? signInGate;

  @override
  Future<void> signIn(String uid) async {
    events.add('signIn:$uid');
    final g = signInGate;
    if (g != null) {
      signInGate = null;
      await g.future;
    }
    await super.signIn(uid);
  }

  @override
  void signOut() {
    events.add('signOut');
    super.signOut();
  }
}

AuthUser user(String uid, {AuthProvider p = AuthProvider.google}) =>
    AuthUser(uid: uid, displayName: uid, provider: p);

void main() {
  late ScopedJournalWorld w;
  late List<String> events;
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() async {
    w = await ScopedJournalWorld.create();
    events = [];
    auth = StreamController<AuthUser?>();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
    await w.dispose();
  });

  Future<void> until(bool Function() done, [String? what]) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'not reached: $what $events $logs');
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  int count(String e) => events.where((x) => x == e).length;

  group('recording fakes: re-verification after every await (items 16 to 19)',
      () {
    late _Repo repo;
    late _Uploader uploader;
    late _Settings settings;
    late _Consent consent;
    late ProviderContainer c;

    void build() {
      repo = _Repo(events);
      uploader = _Uploader(events);
      settings = _Settings(events);
      consent = _Consent(events);
      c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(w.journal),
        authUserProvider.overrideWith((ref) => auth.stream),
        activitySyncRepositoryProvider.overrideWithValue(repo),
        activityStreamUploaderProvider.overrideWithValue(uploader),
        activityCloudSettingsClientProvider.overrideWithValue(settings),
        activityConsentStoreProvider.overrideWithValue(consent),
      ]);
      addTearDown(c.dispose);
      c.read(activityCloudSyncWiringProvider);
    }

    test('16a A held in syncAll, B signs in: A never signs in, loads, resumes '
        'or runs; B runs once', () async {
      build();
      repo.gates[1] = Completer<void>();
      await emit(user('A'));
      await until(() => repo.calls == 1, 'A in syncAll');
      await emit(user('B'));
      await until(() => count('run') == 1, 'B run');
      repo.gates[1]!.complete();
      await settle();
      expect(events.where((e) => e.startsWith('signIn')), ['signIn:B']);
      expect(count('load'), 1);
      expect(count('resume'), 1);
      expect(count('run'), 1);
    });

    test('16b A held in consentStore.signIn: nothing of A after the release',
        () async {
      build();
      consent.signInGate = Completer<void>();
      final gate = consent.signInGate!;
      await emit(user('A'));
      await until(() => events.contains('signIn:A'), 'A signIn');
      await emit(user('B'));
      await until(() => count('run') == 1, 'B run');
      gate.complete();
      await settle();
      expect(count('load'), 1, reason: 'A must not load after the switch');
      expect(count('resume'), 1);
      expect(count('run'), 1);
    });

    test('16c A held in settings.load: no resume and no run for A', () async {
      build();
      settings.loadGate = Completer<void>();
      final gate = settings.loadGate!;
      await emit(user('A'));
      await until(() => count('load') == 1, 'A load');
      await emit(user('B'));
      await until(() => count('run') == 1, 'B run');
      gate.complete();
      await settle();
      expect(count('resume'), 1, reason: 'only B resumes');
      expect(count('run'), 1);
    });

    test('16d A held in the journal bind: A never syncs or signs in',
        () async {
      build();
      w.gate = Completer<void>();
      final gate = w.gate!;
      await emit(user('A'));
      await until(() => w.opened.isNotEmpty, 'A bind opened');
      await emit(user('B'));
      // The scoped journal serializes binds: B's bind queues behind A's open.
      gate.complete();
      await until(() => count('run') == 1, 'B run');
      await settle();
      expect(count('sync'), 1, reason: 'only B syncs');
      expect(events.where((e) => e.startsWith('signIn')), ['signIn:B']);
      expect(count('run'), 1);
    });

    test('17 order: bind, sync, signIn, load, resume, run', () async {
      build();
      await emit(user('A'));
      await until(() => count('run') == 1);
      expect(events, ['sync', 'signIn:A', 'load', 'resume', 'run']);
      expect(w.journal.boundUid, 'A', reason: 'bound before the sync');
    });

    test('17b a load that throws: no resume, no run, logged', () async {
      build();
      settings.loadError = StateError('offline');
      await emit(user('A'));
      await until(
          () => logs.any((l) => l.contains('start stream upload failed')));
      expect(count('resume'), 0);
      expect(count('run'), 0);
    });

    test('18 raw uid change or sign-out: signOut + reset once each before the '
        'next signIn, stored consent of A kept', () async {
      SharedPreferences.setMockInitialValues(
          {'activity.cloudStreamsConsent.A': 'granted'});
      build();
      await emit(user('A'));
      await until(() => count('run') == 1);
      events.clear();
      await emit(user('B'));
      await until(() => count('run') == 1);
      expect(count('signOut'), 1);
      expect(count('reset'), 1);
      expect(events.indexOf('signOut'), lessThan(events.indexOf('signIn:B')));
      expect(events.indexOf('reset'), lessThan(events.indexOf('signIn:B')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('activity.cloudStreamsConsent.A'), 'granted');

      events.clear();
      await emit(null);
      await settle();
      expect(count('signOut'), 1);
      expect(count('reset'), 1);
      expect(count('signIn:B'), 0);
      expect(prefs.getString('activity.cloudStreamsConsent.A'), 'granted');
    });

    test('18b anonymous X replaced by B resets too; first sign-in does not',
        () async {
      build();
      await emit(user('X', p: AuthProvider.anonymous));
      await settle();
      expect(count('signOut'), 0, reason: 'first value: nothing to reset');
      await emit(user('B'));
      await until(() => count('run') == 1);
      expect(count('signOut'), 1);
      expect(count('reset'), 1);
      expect(count('changed'), 1);
      expect(count('cancel'), 1);
    });

    test('18c same uid re-emitted: no reset, no second start', () async {
      build();
      await emit(user('A'));
      await until(() => count('run') == 1);
      events.clear();
      await emit(AuthUser(uid: 'A', displayName: 'new', provider: AuthProvider.google));
      await settle();
      expect(events, isEmpty);
    });

    test('19 deletion in progress for the signed-in uid: onAccountChanged and '
        'cancelQueued at once, the released start does nothing', () async {
      build();
      repo.gates[1] = Completer<void>();
      await emit(user('A'));
      await until(() => repo.calls == 1);
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      expect(count('changed'), 1);
      expect(count('cancel'), 1);
      repo.gates[1]!.complete();
      await settle();
      expect(events.where((e) => e.startsWith('signIn')), isEmpty);
      expect(count('load'), 0);
      expect(count('run'), 0);
    });

    test('19b a deletion flag of another uid does nothing', () async {
      build();
      await emit(user('A'));
      await until(() => count('run') == 1);
      events.clear();
      c.read(accountBeingDeletedUidProvider.notifier).state = 'Z';
      await settle();
      expect(events, isEmpty);
    });
  });

  group('real client + real consent store + real uploader: no upload for B on '
      'A\'s consent (item 13 and the finding)', () {
    late StreamUploadWorld sw;
    late _Repo repo;
    late GatedPrefsStore prefs;
    late AccountScopedConsentStore store;
    late ActivityCloudSettingsClient client;
    late ProviderContainer c;
    final id1 = idFor(1);
    final id2 = idFor(2);

    Future<void> build(Map<String, Object> stored) async {
      sw = await StreamUploadWorld.open();
      addTearDown(sw.dispose);
      await sw.h.journal.put(journalSession(id1, seed: 0));
      await sw.summarySync();
      prefs = installPrefs(stored);
      store = AccountScopedConsentStore();
      client = ActivityCloudSettingsClient(
          call: FakeSettingsServer().call, store: store);
      repo = _Repo(events);
      late final ActivityStreamUploader uploader;
      c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(sw.h.journal),
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

    Future<void> addSecondEntry() async {
      await sw.h.journal.put(journalSession(id2, seed: 1));
      await sw.summarySync();
    }

    test('A granted, B unknown: A uploads (control), B uploads nothing',
        () async {
      await build({consentKeyA: 'granted'});
      await emit(user('A'));
      await until(() => sw.cloud.commits.length == 1, 'A uploads');
      expect(sw.cloud.creates.single.activityId, id1);
      await addSecondEntry();
      await emit(user('B'));
      await settle();
      await settle();
      expect(client.isGranted, isFalse);
      expect(client.consentUid, 'B');
      expect(sw.cloud.creates, hasLength(1), reason: 'no create for B');
      expect(sw.cloud.puts, hasLength(1));
      expect(sw.cloud.commits, hasLength(1));
    });

    test('A granted, B withdrawn: nothing for B', () async {
      await build({consentKeyA: 'granted', consentKeyB: 'withdrawn'});
      await emit(user('A'));
      await until(() => sw.cloud.commits.length == 1);
      await addSecondEntry();
      await emit(user('B'));
      await settle();
      await settle();
      expect(client.state, CloudStreamsConsent.withdrawn);
      expect(sw.cloud.creates, hasLength(1));
      expect(sw.cloud.commits, hasLength(1));
    });

    test('A delayed in syncAll while B signs in: zero calls ever', () async {
      await build({consentKeyA: 'granted'});
      repo.gates[1] = Completer<void>();
      await emit(user('A'));
      await until(() => repo.calls == 1);
      await emit(user('B'));
      await settle();
      repo.gates[1]!.complete();
      await settle();
      await settle();
      expect(sw.cloud.log, isEmpty, reason: 'A obsolete, B unknown');
      expect(store.boundUid, 'B');
      expect(client.isGranted, isFalse);
    });

    test('A delayed consent-store init (A granted), B signs in and finishes '
        'first: zero calls, B bound', () async {
      await build({consentKeyA: 'granted'});
      final gate = prefs.gateNext();
      await emit(user('A'));
      await until(() => prefs.calls == 1, 'A store opening');
      forgetPrefs();
      await emit(user('B'));
      await until(() => store.boundUid == 'B' && count('sync') == 2, 'B chain');
      await settle();
      gate.complete();
      await settle();
      await settle();
      expect(store.boundUid, 'B');
      expect(client.consentUid, isNot('A'));
      expect(client.isGranted, isFalse);
      expect(sw.cloud.log, isEmpty);
    });

    test('B init delayed (A finished granted): nothing for B during or after',
        () async {
      await build({consentKeyA: 'granted'});
      await emit(user('A'));
      await until(() => sw.cloud.commits.length == 1);
      await addSecondEntry();
      forgetPrefs();
      final gate = prefs.gateNext();
      await emit(user('B'));
      await until(() => prefs.calls == 2, 'B store opening');
      await settle();
      expect(client.isGranted, isFalse, reason: 'B opening: A state is gone');
      expect(sw.cloud.creates, hasLength(1));
      gate.complete();
      await settle();
      await settle();
      expect(sw.cloud.creates, hasLength(1), reason: 'B unknown after init');
    });

    test('stale completion after sign-out: nothing runs, store unbound',
        () async {
      await build({consentKeyA: 'granted'});
      final gate = prefs.gateNext();
      await emit(user('A'));
      await until(() => prefs.calls == 1);
      await emit(null);
      await settle();
      gate.complete();
      await settle();
      await settle();
      expect(store.boundUid, isNull);
      expect(client.isGranted, isFalse);
      expect(sw.cloud.log, isEmpty);
    });
  });
}
