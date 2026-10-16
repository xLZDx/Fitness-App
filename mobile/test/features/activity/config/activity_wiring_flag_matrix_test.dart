// S02 test epic 10b: remediation D, the flag matrix of the wiring. Oracle:
// docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md bullets 2 to 4.
//
//  both OFF        : identical to today (no journal, no overrides, wipe not
//                    wrapped, uploader and withdrawal providers null, the start
//                    sync does nothing).
//  localJournal ON : journal opens; only the journal override (NO sync
//                    repository, so no Firestore backend, tombstone pusher or
//                    uploader is constructed); wipe wrapped; conflict card
//                    hidden.
//  cloudSync / both: journal opens; journal AND sync overrides; uploader and
//                    start-up sync work.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_journal_owner.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/activity/widgets/activity_sync_entry_card.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

class _Inner implements LocalDataWipe {
  @override
  Future<void> wipe(String uid) async {}
}

class _OwnerStore implements ActivityJournalOwnerStore {
  String? uid;
  final List<String> writes = [];

  @override
  Future<String?> read() async => uid;
  @override
  Future<void> write(String value) async {
    writes.add(value);
    uid = value;
  }

  @override
  Future<void> clear() async => uid = null;
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

const _off = ActivityFlags();
const _local = ActivityFlags(localJournal: true);
const _cloud = ActivityFlags(cloudSync: true);
const _both = ActivityFlags(cloudSync: true, localJournal: true);

void main() {
  late JournalHarness h;
  late Directory tmp;
  late PathProviderPlatform savedPaths;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    tmp = Directory.systemTemp.createTempSync('activity_flag_matrix_');
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(tmp.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() async {
    debugPrint = savedDebugPrint;
    PathProviderPlatform.instance = savedPaths;
    await h.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('both OFF: identical to today', () {
    test('openActivityJournal returns null and touches no disk', () async {
      expect(await openActivityJournal(flags: _off), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('activityRootOverrides is empty, even when a journal is supplied',
        () {
      expect(activityRootOverrides(flags: _off), isEmpty);
      expect(activityRootOverrides(flags: _off, journal: h.journal), isEmpty);
    });

    test('activityAwareLocalDataWipe returns the inner wipe unchanged', () {
      final inner = _Inner();
      expect(activityAwareLocalDataWipe(inner, null), same(inner));
    });

    test('uploader and withdrawal providers are null', () {
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(_off),
        activityJournalProvider.overrideWithValue(h.journal),
        activityCloudSettingsClientProvider.overrideWithValue(_Settings()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(activityStreamUploaderProvider), isNull);
      expect(c.read(activityConsentWithdrawalProvider), isNull);
    });
  });

  group('localJournal ON only: journal without any network object', () {
    test('openActivityJournal opens a journal', () async {
      final j = await openActivityJournal(flags: _local);
      expect(j, isNotNull, reason: 'logs: $logs');
    });

    test('overrides contain only the journal override', () {
      final o = activityRootOverrides(flags: _local, journal: h.journal);
      expect(o, hasLength(1));
      final c = ProviderContainer(overrides: o);
      addTearDown(c.dispose);
      expect(c.read(activityJournalProvider), same(h.journal));
      // The sync repository (Firestore backend, tombstone pusher) is not
      // overridden: the default provider throws, so nothing built it.
      expect(() => c.read(activitySyncRepositoryProvider),
          throwsA(anything));
    });

    test('a journal that failed to open (null) gives no overrides', () {
      expect(activityRootOverrides(flags: _local), isEmpty);
    });

    test('the wipe is wrapped', () {
      final w = activityAwareLocalDataWipe(_Inner(), h.journal,
          ownerStore: _OwnerStore());
      expect(w, isA<ActivityAwareLocalDataWipe>());
    });

    test('uploader and withdrawal providers stay null even with a journal',
        () {
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(_local),
        activityJournalProvider.overrideWithValue(h.journal),
        activityCloudSettingsClientProvider.overrideWithValue(_Settings()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(activityStreamUploaderProvider), isNull);
      expect(c.read(activityConsentWithdrawalProvider), isNull);
    });

    testWidgets('the conflict entry card is hidden and the presenter is never '
        'read', (tester) async {
      // The binding checks foundation vars after the body, before tearDown.
      debugPrint = savedDebugPrint;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activityFlagsProvider.overrideWithValue(_local),
          activityJournalProvider.overrideWithValue(h.journal),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivitySyncEntryCard())),
      ));
      expect(find.byKey(const Key('activitySync.entryCard')), findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'reading the presenter would hit the unset sync repository');
    });
  });

  for (final entry in {'cloudSync ON only': _cloud, 'both ON': _both}.entries) {
    group(entry.key, () {
      final flags = entry.value;

      test('openActivityJournal opens a journal', () async {
        expect(await openActivityJournal(flags: flags), isNotNull,
            reason: 'logs: $logs');
      });

      test('overrides contain the journal AND the sync repository', () {
        expect(activityRootOverrides(flags: flags, journal: h.journal),
            hasLength(2));
      });

      test('the wipe is wrapped', () {
        expect(
            activityAwareLocalDataWipe(_Inner(), h.journal,
                ownerStore: _OwnerStore()),
            isA<ActivityAwareLocalDataWipe>());
      });

      test('uploader and withdrawal providers exist', () {
        final c = ProviderContainer(overrides: [
          activityFlagsProvider.overrideWithValue(flags),
          activityJournalProvider.overrideWithValue(h.journal),
          activityCloudSettingsClientProvider.overrideWithValue(_Settings()),
        ]);
        addTearDown(c.dispose);
        expect(c.read(activityStreamUploaderProvider), isNotNull);
        expect(c.read(activityConsentWithdrawalProvider), isNotNull);
      });
    });
  }

  group('start-up sync wiring per flag combination', () {
    Future<(_OwnerStore, FakeSummaryBackend, _Settings)> signIn(
        ActivityFlags flags) async {
      final owner = _OwnerStore();
      final backend = FakeSummaryBackend();
      final settings = _Settings();
      final auth = StreamController<AuthUser?>();
      addTearDown(() => unawaited(auth.close()));
      final repo = ActivitySyncRepository(journal: h.journal, backend: backend);
      addTearDown(repo.dispose);
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(flags),
        activityJournalProvider.overrideWithValue(h.journal),
        activityJournalOwnerStoreProvider.overrideWithValue(owner),
        activitySyncRepositoryProvider.overrideWithValue(repo),
        activityCloudSettingsClientProvider.overrideWithValue(settings),
        activityConsentStoreProvider.overrideWithValue(_Consent()),
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(c.dispose);
      c.read(activityCloudSyncWiringProvider);
      auth.add(const AuthUser(
          uid: 'U', displayName: 'U', provider: AuthProvider.google));
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return (owner, backend, settings);
    }

    for (final flags in [_off, _local]) {
      test('$flags: the start sync is a no-op', () async {
        final (owner, backend, settings) = await signIn(flags);
        expect(owner.writes, isEmpty, reason: 'no claim');
        expect(backend.calls, isEmpty, reason: 'no syncAll');
        expect(settings.loads, 0);
      });
    }

    for (final flags in [_cloud, _both]) {
      test('$flags: the start sync claims the journal and syncs', () async {
        final (owner, backend, settings) = await signIn(flags);
        expect(owner.writes, ['U']);
        expect(backend.count('listTombstoneIds'), 1);
        expect(settings.loads, 1);
      });
    }
  });
}
