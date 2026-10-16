// S02 remediation E1 (test epic 11a, replaces the B2 owner-marker version).
// Oracles: docs/phase2/s02/S02_REMEDIATION_E_TEST_NOTES.md heading E1 and
// S02_DESIGN.md sections 6.2, 7 and 17 (item 22), not the code under test.
//
//  1. The decorator `ActivityAwareLocalDataWipe` / `activityAwareLocalDataWipe`
//     (scope of the DELETED uid, whoever is bound; plain journal fallback).
//  2. The relaunch path with a pending wipe, also while another account is bound.
//  3. `activityCloudSyncWiringProvider`: the journal of the signed-in uid is
//     bound first; a failed bind starts no sync and no upload (fail closed).
//
// The scoped journal is the REAL one over real files (ScopedJournalWorld); a
// plain journal is a counting wrapper over the real file journal.
import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
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

/// A scoped journal whose `wipeForUid` records and can fail; reads and the rest
/// go to the real scoped journal.
class _Scoped extends Fake implements ActivityJournal, AccountScopedJournal {
  _Scoped(this.inner);

  final UidScopedActivityJournal inner;
  final List<String> wiped = [];
  bool failWipe = false;

  @override
  Future<void> wipeForUid(String uid) async {
    wiped.add(uid);
    if (failWipe) throw StateError('disk error');
    await inner.wipeForUid(uid);
  }

  @override
  Future<bool> bindUid(String? uid) => inner.bindUid(uid);

  // Remediation F2 added these to AccountScopedJournal; a Fake throws on them.
  @override
  String? get boundUid => inner.boundUid;

  @override
  bool get isBound => inner.isBound;
}

/// A plain (NOT account-scoped) journal: counts and optionally fails `wipe()`.
class _Plain extends Fake implements ActivityJournal {
  _Plain(this.inner);

  final ActivityJournal inner;
  bool failWipe = false;
  int wipes = 0;

  @override
  Future<void> wipe() async {
    wipes++;
    if (failWipe) throw StateError('disk error');
    await inner.wipe();
  }

  @override
  Future<List<JournalEntry>> list() => inner.list();

  @override
  Future<List<JournalEntry>> listTombstones() => inner.listTombstones();
}

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
  _Uploader(this.journal);

  final UidScopedActivityJournal journal;
  int runs = 0;
  final List<String?> boundAtResume = [];

  @override
  void cancelQueued() {}

  @override
  void resume() => boundAtResume.add(journal.boundUid);

  @override
  Future<void> runPending() async => runs++;
}

class _Settings extends Fake implements ActivityCloudSettingsClient {
  int loads = 0;
  int resets = 0;

  @override
  void reset() => resets++;

  @override
  Future<void> load() async => loads++;
}

class _Consent extends AccountScopedConsentStore {
  final List<String> signIns = [];

  @override
  Future<void> signIn(String uid) async => signIns.add(uid);
}

void main() {
  late ScopedJournalWorld w;

  setUp(() async => w = await ScopedJournalWorld.create());
  tearDown(() => w.dispose());

  Future<void> putFor(String uid, int n) async {
    expect(await w.journal.bindUid(uid), isTrue);
    await w.journal.put(journalSession(idFor(n), seed: n));
  }

  Future<List<String>> idsOf(String uid) async {
    // A wipe of the bound uid refuses its re-bind (remediation F2); a sign-out
    // (unbind) ends the refusal, as in the real flow, before the next sign-in.
    await w.journal.bindUid(null);
    expect(await w.journal.bindUid(uid), isTrue);
    return [for (final e in await w.journal.list()) e.id]..sort();
  }

  String keyOf(String uid) =>
      '${SecureStorageJournalKeyProvider.keyName}.${activityJournalScopeId(uid)}';

  group('1. the decorator', () {
    test('activityAwareLocalDataWipe(inner, null) returns inner itself', () {
      final inner = _Inner();
      expect(activityAwareLocalDataWipe(inner, null), same(inner));
    });

    test('with a journal it returns the decorator, not the inner object', () {
      final inner = _Inner();
      final wipe = activityAwareLocalDataWipe(inner, w.journal);
      expect(wipe, isNot(same(inner)));
      expect(wipe, isA<ActivityAwareLocalDataWipe>());
    });

    test('wipe(A) runs the inner wipe and empties A\'s scope: sessions, side '
        'files and key', () async {
      await putFor('A', 1);
      await w.writeSide('A', 'sources/a.json', '{}');
      final inner = _Inner();
      await ActivityAwareLocalDataWipe(inner: inner, journal: w.journal)
          .wipe('A');
      expect(inner.wiped, ['A']);
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await idsOf('A'), isEmpty);
    });

    test('wipe(A) while B is bound wipes A\'s scope and leaves B untouched '
        'and bound', () async {
      await putFor('A', 1);
      await putFor('B', 2);
      final b = await w.snapshot('B');
      final bKey = w.storage.values[keyOf('B')];
      expect(w.journal.boundUid, 'B');

      await ActivityAwareLocalDataWipe(inner: _Inner(), journal: w.journal)
          .wipe('A');

      expect(w.journal.boundUid, 'B', reason: 'B stays bound');
      expect([for (final e in await w.journal.list()) e.id], [idFor(2)]);
      expect(await w.snapshot('B'), b, reason: 'B\'s files are byte-identical');
      expect(w.storage.values[keyOf('B')], bKey);
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await idsOf('A'), isEmpty, reason: 'A\'s sessions are gone');
    });

    test('a failed journal wipe is reported as activity_journal in '
        'LocalWipeIncomplete', () async {
      await putFor('A', 1);
      final scoped = _Scoped(w.journal)..failWipe = true;
      final wipe = ActivityAwareLocalDataWipe(inner: _Inner(), journal: scoped);
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['activity_journal'])));
      expect(scoped.wiped, ['A']);
      expect(await idsOf('A'), [idFor(1)], reason: 'nothing was wiped');
    });

    test('a plain (non scoped) journal falls back to wipe()', () async {
      await w.journal.bindUid('A');
      final plain = _Plain(w.journal);
      await ActivityAwareLocalDataWipe(inner: _Inner(), journal: plain)
          .wipe('X');
      expect(plain.wipes, 1);
    });

    test('a plain journal wipe failure is reported as activity_journal',
        () async {
      await w.journal.bindUid('A');
      final plain = _Plain(w.journal)..failWipe = true;
      await expectLater(
          ActivityAwareLocalDataWipe(inner: _Inner(), journal: plain).wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['activity_journal'])));
    });

    test('an inner LocalWipeIncomplete still wipes the journal and is '
        'rethrown WITHOUT activity_journal when the journal wipe worked',
        () async {
      await putFor('A', 1);
      final scoped = _Scoped(w.journal);
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(LocalWipeIncomplete(['progress_photos'])),
          journal: scoped);
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['progress_photos'])));
      expect(scoped.wiped, ['A'], reason: 'the inner failure did not skip it');
      expect(await idsOf('A'), isEmpty);
    });

    test('an inner LocalWipeIncomplete plus a journal failure reports both, '
        'inner first', () async {
      final scoped = _Scoped(w.journal)..failWipe = true;
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(LocalWipeIncomplete(['progress_photos'])),
          journal: scoped);
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having((e) => e.remaining,
              'remaining', ['progress_photos', 'activity_journal'])));
    });

    test('a non-wipe inner error is rethrown as itself after the journal was '
        'wiped', () async {
      await putFor('A', 1);
      final wipe = ActivityAwareLocalDataWipe(
          inner: _Inner(StateError('boom')), journal: w.journal);
      await expectLater(wipe.wipe('A'), throwsA(isA<StateError>()));
      expect(await idsOf('A'), isEmpty);
    });
  });

  group('2. relaunch path and the scope of the deleted account', () {
    test('finishInterruptedWipe with the decorator empties the deleted '
        'account\'s journal and removes the pending marker', () async {
      await putFor('A', 1);
      await w.journal.bindUid(null);
      final marker = InMemoryPendingWipeMarker()..add('A');
      final wiped = await finishInterruptedWipe(
        marker: marker,
        wipe: activityAwareLocalDataWipe(_Inner(), w.journal),
        signedInUid: null,
      );
      expect(wiped, isTrue);
      expect(await marker.read(), isEmpty);
      expect(await idsOf('A'), isEmpty);
    });

    test('a journal wipe failure keeps the pending marker; the next launch '
        'retries and finishes', () async {
      await putFor('A', 1);
      await w.journal.bindUid(null);
      final marker = InMemoryPendingWipeMarker()..add('A');
      final scoped = _Scoped(w.journal)..failWipe = true;
      final wipe = activityAwareLocalDataWipe(_Inner(), scoped);

      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isFalse);
      expect(await marker.read(), {'A'}, reason: 'marker kept for the retry');
      expect(scoped.wiped, ['A']);
      expect(w.storage.values.containsKey(keyOf('A')), isTrue,
          reason: 'nothing was wiped yet');

      scoped.failWipe = false; // the next launch
      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isTrue);
      expect(scoped.wiped, ['A', 'A'], reason: 'the journal wipe was retried');
      expect(await marker.read(), isEmpty);
      expect(await idsOf('A'), isEmpty);
    });

    test('pending wipe of X while Y is bound wipes ONLY X\'s scope; Y\'s '
        'journal and key are untouched', () async {
      await putFor('X', 1);
      await putFor('Y', 2);
      final y = await w.snapshot('Y');
      final inner = _Inner();
      final marker = InMemoryPendingWipeMarker()..add('X');
      final wiped = await finishInterruptedWipe(
        marker: marker,
        wipe: activityAwareLocalDataWipe(inner, w.journal),
        signedInUid: 'Y',
      );
      expect(wiped, isTrue);
      expect(inner.wiped, ['X']);
      expect(w.journal.boundUid, 'Y');
      expect(await w.snapshot('Y'), y);
      expect([for (final e in await w.journal.list()) e.id], [idFor(2)]);
      expect(w.storage.values.containsKey(keyOf('Y')), isTrue);
      expect(w.storage.values.containsKey(keyOf('X')), isFalse);
      expect(await marker.read(), isEmpty);
      expect(await idsOf('X'), isEmpty);
    });
  });

  group('3. the cloud wiring binds first (fail closed)', () {
    late FakeSummaryBackend backend;
    late _Uploader uploader;
    late _Settings settings;
    late _Consent consent;
    late List<String> logs;
    late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

    setUp(() {
      backend = FakeSummaryBackend();
      uploader = _Uploader(w.journal);
      settings = _Settings();
      consent = _Consent();
      logs = [];
      savedDebugPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    });

    tearDown(() => debugPrint = savedDebugPrint);

    ProviderContainer container(String signedInUid) {
      final repo = ActivitySyncRepository(journal: w.journal, backend: backend);
      addTearDown(repo.dispose);
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(
            const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(w.journal),
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

    Future<void> until(bool Function() done) async {
      // Real files: give the disk I/O real time (bounded, on a condition).
      for (var i = 0; i < 1000 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue, reason: 'condition was not reached: $logs');
    }

    test('signed-in B: B\'s journal is bound BEFORE the uploader resumes; '
        'sync and upload start; A\'s data is not touched', () async {
      await putFor('A', 1);
      await w.journal.bindUid(null);
      final a = await w.snapshot('A');
      final c = container('B');
      c.read(activityCloudSyncWiringProvider);

      await until(() => uploader.runs == 1);
      expect(uploader.boundAtResume, ['B'], reason: 'bound before resume');
      expect(w.journal.boundUid, 'B');
      expect(backend.count('listTombstoneIds'), 1, reason: 'syncAll ran');
      expect(consent.signIns, ['B']);
      expect(settings.loads, 1);
      expect(await w.snapshot('A'), a, reason: 'A\'s data is byte-identical');
      expect(w.storage.values.containsKey(keyOf('A')), isTrue);
    });

    test('signed-in A again: A\'s sessions are there and are what sync sees',
        () async {
      await putFor('A', 1);
      await w.journal.bindUid(null);
      final c = container('A');
      c.read(activityCloudSyncWiringProvider);
      await until(() => uploader.runs == 1);
      expect([for (final e in await w.journal.list()) e.id], [idFor(1)]);
      expect(backend.count('listTombstoneIds'), 1);
    });

    test('the bind fails: no sync, no upload, no resume, no settings, no '
        'consent; nothing wiped', () async {
      await putFor('A', 1);
      await w.journal.bindUid(null);
      final a = await w.snapshot('A');
      w.failOpen.add(activityJournalScopeId('B'));
      final c = container('B');
      c.read(activityCloudSyncWiringProvider);

      await until(() => logs.any((l) => l.contains('journal bind failed')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(w.journal.boundUid, isNull);
      expect(backend.calls, isEmpty, reason: 'no syncAll');
      expect(uploader.runs, 0);
      expect(uploader.boundAtResume, isEmpty);
      expect(settings.loads, 0);
      expect(consent.signIns, isEmpty);
      expect(await w.snapshot('A'), a);
    });
  });
}
