// S02 test epic 14a: the promise behind remediation H-A. "My GPS data is never
// uploaded under another account's consent." End to end over the REAL
// FileActivityJournal (per-account scopes on a temp directory), the real
// ActivitySyncRepository, the real AccountScopedConsentStore and
// ActivityCloudSettingsClient (fake preferences platform store), the real
// ActivityStreamUploader with a recording cloud and the REAL startup closure
// of `activityCloudSyncWiringProvider`.
//
// A has stored consent `granted`, B has none. A's startup stalls in `syncAll`
// while B signs in. The oracle is the promise: zero create, PUT and commit calls
// after B is signed in, B's stream marker never set, A's data and A's stored
// consent untouched. A control run shows the same world uploads for A alone.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/gated_prefs.dart';
import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

class _Backend implements ActivitySummaryBackend {
  /// Holds the first `listTombstoneIds` (A's startup pass).
  Completer<void>? firstListGate;
  int lists = 0;
  final List<String> writes = [];

  @override
  Future<Set<String>> listTombstoneIds() async {
    final n = ++lists;
    if (n == 1) {
      final g = firstListGate;
      if (g != null) await g.future;
    }
    return {};
  }

  @override
  Future<bool> tombstoneExists(String id) async => false;
  @override
  Future<Map<String, Object?>?> readSummary(String id) async => null;
  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    writes.add(id);
  }
}

void main() {
  late Directory tmp;
  late UidScopedActivityJournal journal;
  late StreamController<AuthUser?> auth;
  late FakeClock clock;
  late FakeStreamCloud cloud;
  late _Backend backend;
  late GatedPrefsStore prefs;
  late AccountScopedConsentStore store;
  late ActivityCloudSettingsClient client;
  late ProviderContainer c;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;
  final keys = <String, JournalKeyProvider>{};
  final idA = idFor(1);
  final idB = idFor(3);

  AuthUser user(String uid) =>
      AuthUser(uid: uid, displayName: uid, provider: AuthProvider.google);

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'not reached: $what $logs');
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('s02_consent_switch_');
    keys.clear();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    auth = StreamController<AuthUser?>();
    clock = FakeClock();
    cloud = FakeStreamCloud(clock);
    backend = _Backend();
    journal = UidScopedActivityJournal(factory: (scope) async {
      return FileActivityJournal(
        rootPath: '${tmp.path.replaceAll('\\', '/')}/activity_journal/$scope',
        keyProvider: keys.putIfAbsent(scope,
            () => InMemoryJournalKeyProvider(fixedJournalKey(scope.hashCode))),
      );
    });
    // A has one activity, B has one activity (both owe a summary sync).
    expect(await journal.bindUid('A'), isTrue);
    await journal.put(journalSession(idA, seed: 1));
    expect(await journal.bindUid('B'), isTrue);
    await journal.put(journalSession(idB, seed: 3));
    expect(await journal.bindUid(null), isTrue);

    // A's stored consent is granted; B has never been asked.
    prefs = installPrefs({consentKeyA: 'granted'});
    store = AccountScopedConsentStore();
    client = ActivityCloudSettingsClient(
        call: FakeSettingsServer().call, store: store);

    final repo = ActivitySyncRepository(
      journal: journal,
      backend: backend,
      clock: clock.call,
      authUid: () => c.read(authUserProvider).valueOrNull?.uid,
    );
    late final ActivityStreamUploader uploader;
    c = ProviderContainer(overrides: [
      activityFlagsProvider
          .overrideWithValue(const ActivityFlags(cloudSync: true)),
      activityJournalProvider.overrideWithValue(journal),
      authUserProvider.overrideWith((ref) => auth.stream),
      activitySyncRepositoryProvider.overrideWithValue(repo),
      activityStreamUploaderProvider.overrideWith((ref) => uploader),
      activityCloudSettingsClientProvider.overrideWithValue(client),
      activityConsentStoreProvider.overrideWithValue(store),
    ]);
    uploader = ActivityStreamUploader(
      journal: journal,
      callables: cloud,
      consent: client,
      put: cloud.put,
      flags: const ActivityFlags(cloudSync: true),
      now: clock.call,
      delay: (d) async => clock.advance(d),
      currentUid: () => c.read(authUserProvider).valueOrNull?.uid,
    );
    c.read(activityCloudSyncWiringProvider);
    addTearDown(() async {
      c.dispose();
      await repo.dispose();
    });
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
    try {
      await journal.close();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('control: A alone, consent granted, uploads its own activity',
      () async {
    await emit(user('A'));
    await until(() => cloud.commits.length == 1, 'A uploads');
    expect(cloud.creates.single.activityId, idA);
    expect(client.isGranted, isTrue);
    expect(client.consentUid, 'A');
  });

  test('A granted / B unknown, A stalled in syncAll while B signs in: nothing '
      'is uploaded for B, A\'s data and consent are untouched', () async {
    backend.firstListGate = Completer<void>();
    await emit(user('A'));
    await until(() => backend.lists == 1, 'A stalled in syncAll');
    expect(cloud.log, isEmpty);

    await emit(user('B'));
    await settle();
    expect(client.isGranted, isFalse, reason: 'B has no consent of its own');
    expect(store.boundUid, 'B',
        reason: 'A signed in before its sync (remediation I2), then the '
            'account change unbound it and B bound its own consent');
    expect(cloud.log, isEmpty);

    backend.firstListGate!.complete(); // A's obsolete continuation resumes
    await until(() => store.boundUid == 'B', 'B consent store bound');
    await settle();
    await settle();

    // The promise: not one network step of the stream upload, ever.
    expect(cloud.creates, isEmpty);
    expect(cloud.puts, isEmpty);
    expect(cloud.commits, isEmpty);
    expect(store.boundUid, 'B');
    expect(client.consentUid, isNot('A'));
    expect(client.isGranted, isFalse);

    // B's local data: its summary may sync, its stream marker is never set.
    expect(await journal.bindUid('B'), isTrue);
    expect((await journal.read(idB))!.state.streamUploadPending, isTrue);
    // A's data and A's stored consent survive the whole sequence.
    expect(await journal.bindUid('A'), isTrue);
    expect((await journal.read(idA))!.state.streamUploadPending, isTrue);
    final raw = await prefs.getAll();
    expect(raw[consentKeyA], 'granted');
    expect(raw.containsKey(consentKeyB), isFalse);
  });
}
