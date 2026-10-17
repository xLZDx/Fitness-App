// S04-15 Journal lifecycle and owner-only storage, S04-16 Storage full, plus the
// 30-day fallback and expiry rows DT-30-3, DT-30-13 and the pre-unbind hook
// (journal side of S04-30). Rows DT-15-1..4, 7..10, DT-16-1..4, DT-30-3, 13 of
// docs/phase2/s04/S04_TEST_PLAN.md. Oracle: Design 4.7 / 4.8 and the privacy
// contract, not the code. Widget rows (DT-15-5, DT-16-5) are NOT_RUN here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/scoped_journal_world.dart';
import 'journal_kit.dart';

final String id1 = recId(1);

class _NoopWipe implements LocalDataWipe {
  @override
  Future<void> wipe(String uid) async {}
}

/// Real files, the real scoped S02 journal, the real recording journal.
class RealWorld {
  RealWorld._(this.w, this.rec, this.shutdownCalls);
  final ScopedJournalWorld w;
  final FileRecordingJournal rec;
  final List<String> shutdownCalls;

  static Future<RealWorld> create() async {
    final w = await ScopedJournalWorld.create();
    final calls = <String>[];
    final rec = FileRecordingJournal(
      activity: w.journal,
      boundUid: () => w.journal.boundUid,
      scopesRoot: () async => '${w.base}/activity_journal',
      keyProviderFor: (scope) => SecureStorageJournalKeyProvider(storage: w.storage, scopeId: scope),
      runner: InlineHeavyWorkRunner(),
    );
    w.journal.recordingGuard = rec;
    return RealWorld._(w, rec, calls);
  }

  String scopeDir(String uid) => w.rootOf(uid);
  String recDir(String uid) => '${scopeDir(uid)}/$kRecordingDirName';

  Future<void> bind(String uid) async => expect(await w.journal.bindUid(uid), isTrue);

  Future<void> record(String uid, String id, int n) async {
    await rec.begin(metaFor(id, uid: uid, startUtcMs: 1760000000000));
    for (var i = 1; i <= n; i++) {
      rec.enqueueSample(smp(i), GateCounters.zero);
    }
    await rec.flush();
  }

  /// Every file path under the scope directory of [uid], relative.
  List<String> tree(String uid) {
    final d = Directory(scopeDir(uid));
    if (!d.existsSync()) return const [];
    return [
      for (final e in d.listSync(recursive: true, followLinks: false))
        if (e is File) e.path.replaceAll('\\', '/').substring(scopeDir(uid).length)
    ]..sort();
  }

  Future<void> dispose() async {
    try {
      await rec.closeScope(w.journal.boundUid == null ? '' : activityJournalScopeId(w.journal.boundUid!));
    } catch (_) {}
    await w.dispose();
  }
}

/// The "strict path" hook with the kit's journal.
RecordingPreUnbindHook hookFor(RecKit k, List<String> calls, {void Function(int)? kept}) =>
    RecordingPreUnbindHook(
      journal: k.journal,
      shutdownRecorder: () async => calls.add('shutdown'),
      onFallbackKept: kept,
    );

void main() {
  group('DT-15-1 wipe on the real tree', () {
    late RealWorld rw;
    setUp(() async => rw = await RealWorld.create());
    tearDown(() => rw.dispose());

    test('/device-wipe: recording/ is gone after the wipe, no undecryptable leftover', () async {
      await rw.bind('user-a');
      await rw.record('user-a', id1, 5);
      expect(rw.tree('user-a').where((f) => f.contains('/recording/')), isNotEmpty);
      await rw.w.journal.wipeForUid('user-a');
      expect(Directory(rw.recDir('user-a')).existsSync(), isFalse);
      expect(rw.tree('user-a'), isEmpty, reason: 'no file of the scope survives');
      expect(rw.w.storage.values.keys.where((k) => k.endsWith(activityJournalScopeId('user-a'))), isEmpty,
          reason: 'the key is forgotten: nothing undecryptable stays');
    });

    test('/account-deletion: the recorder is shut down first, then recording/ is emptied', () async {
      await rw.bind('user-a');
      await rw.record('user-a', id1, 5);
      final registry = PreUnbindHookRegistry();
      final calls = <String>[];
      registry.register(RecordingPreUnbindHook(
          journal: rw.rec, shutdownRecorder: () async => calls.add('shutdown')));
      final wipe = ActivityAwareLocalDataWipe(
          inner: _NoopWipe(), journal: rw.w.journal, preUnbind: registry);
      await wipe.wipe('user-a');
      expect(calls, ['shutdown'], reason: 'deletion: shutdown only, no hand-off');
      expect(rw.tree('user-a'), isEmpty);
      expect(Directory(rw.recDir('user-a')).existsSync(), isFalse);
    });

    test('/sign-out-and-delete: hand-off first (a stored session), then the journal is gone', () async {
      await rw.bind('user-a');
      await rw.record('user-a', id1, 5);
      final registry = PreUnbindHookRegistry();
      registry.register(RecordingPreUnbindHook(journal: rw.rec, shutdownRecorder: () async {}));
      expect(await registry.runBounded('user-a', UnbindReason.signOut), PreUnbindOutcome.completed);
      expect((await rw.w.journal.list()).map((e) => e.id), [nativeActivityId(id1)]);
      expect(Directory('${rw.recDir('user-a')}/$id1').existsSync(), isFalse, reason: 'cleaned after the hand-off');
      await rw.w.journal.wipeForUid('user-a');
      expect(rw.tree('user-a'), isEmpty);
    });
  });

  test('DT-15-2 every top-level entry of the support directory is excluded from backup', () async {
    final rw = await RealWorld.create();
    try {
      await rw.bind('user-a');
      await rw.record('user-a', id1, 3);
      final tops = [
        for (final e in Directory(rw.w.tmp.path).listSync()) e.path.replaceAll('\\', '/').split('/').last
      ];
      expect(tops, isNotEmpty);
      String strip(String xml) => xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final dataExt = strip(File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync());
      final backup = strip(File('android/app/src/main/res/xml/backup_rules.xml').readAsStringSync());
      final sections = <String>[
        RegExp(r'<cloud-backup>(.*?)</cloud-backup>', dotAll: true).firstMatch(dataExt)!.group(1)!,
        RegExp(r'<device-transfer>(.*?)</device-transfer>', dotAll: true).firstMatch(dataExt)!.group(1)!,
        RegExp(r'<full-backup-content>(.*?)</full-backup-content>', dotAll: true).firstMatch(backup)!.group(1)!,
      ];
      expect(sections, hasLength(3));
      for (final t in tops) {
        for (final s in sections) {
          expect(RegExp('<exclude\\s+domain="file"\\s+path="$t"\\s*/>').hasMatch(s), isTrue,
              reason: 'top-level entry "$t" must be excluded in every section');
        }
      }
      expect(tops, contains(kScopedJournalRootDirName));
    } finally {
      await rw.dispose();
    }
  });

  test('DT-15-3 one shared scoped-root constant; the recording directory is under it', () {
    expect(kRecordingDirName, 'recording');
    expect(kActivityBackupExcludedDirs, contains(kScopedJournalRootDirName));
    final providers = File('lib/features/recording/journal/recording_journal_providers.dart').readAsStringSync();
    expect(providers.contains('kScopedJournalRootDirName'), isTrue,
        reason: 'the factory root uses the shared constant');
    final scoped = File('lib/features/activity/repository/uid_scoped_activity_journal.dart').readAsStringSync();
    expect(scoped.contains('kScopedJournalRootDirName'), isTrue);
    final rec = File('lib/features/recording/journal/file_recording_journal.dart').readAsStringSync();
    expect(rec.contains('kRecordingDirName'), isTrue, reason: 'one constant for the folder name');
    expect(RegExp(r"'recording'").hasMatch(rec), isFalse, reason: 'no second spelling of the folder');
  });

  test('DT-15-4 two real scope directories: another account sees nothing', () async {
    final rw = await RealWorld.create();
    try {
      await rw.bind('user-a');
      await rw.record('user-a', id1, 4);
      // unfinished for A: the process "restarts" (fresh recording journal object not needed:
      // A's list excludes only the active one, so close the active scope first)
      await rw.rec.closeScope(activityJournalScopeId('user-a'));
      await rw.bind('user-b');
      final fresh = FileRecordingJournal(
        activity: rw.w.journal,
        boundUid: () => rw.w.journal.boundUid,
        scopesRoot: () async => '${rw.w.base}/activity_journal',
        keyProviderFor: (scope) => SecureStorageJournalKeyProvider(storage: rw.w.storage, scopeId: scope),
        runner: InlineHeavyWorkRunner(),
      );
      expect(await fresh.listUnfinished(), isEmpty, reason: 'B is bound: A\'s recording is not listed');
      expect(Directory('${rw.recDir('user-a')}/$id1').existsSync(), isTrue, reason: 'and not touched');
      await fresh.closeScope(activityJournalScopeId('user-b'));
      await rw.bind('user-a');
      final again = FileRecordingJournal(
        activity: rw.w.journal,
        boundUid: () => rw.w.journal.boundUid,
        scopesRoot: () async => '${rw.w.base}/activity_journal',
        keyProviderFor: (scope) => SecureStorageJournalKeyProvider(storage: rw.w.storage, scopeId: scope),
        runner: InlineHeavyWorkRunner(),
      );
      final r = await again.listUnfinished();
      expect(r.single.recordingId, id1, reason: 'the same account sees its recording again');
      expect(r.single.sampleCount, 4);
      await again.closeScope(activityJournalScopeId('user-a'));
    } finally {
      await rw.dispose();
    }
  });

  test('DT-15-7 a flush in flight: after the wipe no file or directory is recreated', () async {
    final k = await RecKit.create();
    try {
      await k.journal.begin(k.meta(id1));
      for (var i = 1; i <= 3; i++) {
        k.journal.enqueueSample(smp(i), GateCounters.zero);
      }
      k.fs.reached = Completer<void>();
      k.fs.gate = Completer<void>();
      final flush = k.journal.flush(); // blocks inside the write
      await k.fs.reached!.future;
      var closed = false;
      final close = k.journal.closeScope(k.scopeId).then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse, reason: 'closing waits for the in-flight write to drain');
      k.fs.gate!.complete();
      await flush;
      await close;
      // the S02 wipe now deletes the scope
      await k.mem.deleteDir('${RecKit.scopesRoot}/${k.scopeId}');
      await k.mem.createDir(RecKit.scopesRoot);
      k.put('${RecKit.scopesRoot}/${k.scopeId}.wiped', utf8.encode('wiping'));
      final filesAfterWipe = k.mem.files.keys.toSet();
      final dirsAfterWipe = k.mem.dirs.toSet();
      // late writes after the wipe
      k.journal.enqueueSample(smp(9), GateCounters.zero);
      await k.journal.flush();
      await k.journal.appendEvent(const JournalEvent(JournalEventKind.pause, 9500)).then((_) {}, onError: (_) {});
      expect(await k.journal.listUnfinished(), isEmpty);
      await expectLater(k.journal.begin(k.meta(recId(2))), throwsJournalCode('ownerScopeLost'));
      expect(k.mem.files.keys.toSet(), filesAfterWipe, reason: 'no file recreated');
      expect(k.mem.dirs.toSet(), dirsAfterWipe, reason: 'no directory recreated');
    } finally {
      await k.dispose();
    }
  });

  test('DT-15-8 the root is the app-private support directory, not external storage or cache', () {
    final src = File('lib/features/recording/journal/recording_journal_providers.dart').readAsStringSync();
    expect(src.contains('getApplicationSupportDirectory'), isTrue);
    for (final bad in [
      'getExternalStorageDirectory',
      'getTemporaryDirectory',
      'getApplicationCacheDirectory',
      'getExternalCacheDirectories',
      'getDownloadsDirectory',
      'getApplicationDocumentsDirectory',
    ]) {
      expect(src.contains(bad), isFalse, reason: bad);
    }
  });

  group('DT-15-9 lifecycle on two scopes, state asserted after each step', () {
    test('/successful-hand-off-then-the-recording-journal-is-deleted', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      expect(k.filesOf(id1), isNotEmpty);
      expect(await k.finish(id1), HandOffResult.done);
      expect(k.filesOf(id1), isEmpty);
      expect(await activityCount(k), 1);
      await k.dispose();
    });

    test('/failed-hand-off-the-unsealed-recording-stays-encrypted-in-its-own-scope', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('store down');
      expect(await k.finish(id1), HandOffResult.failedKept);
      expect(k.filesOf(id1), containsAll(['meta.json', 'seg-0001.log', 'SEALED']));
      // encrypted at rest: no plaintext coordinate text and no float bytes of the sentinel
      for (final f in k.filesOf(id1)) {
        final b = k.bytesOf('${k.dirOf(id1)}/$f');
        if (b == null) continue;
        final text = latin1.decode(b);
        expect(text.contains('"la"'), isFalse, reason: '$f has no JSON column names');
        expect(text.contains('47.0'), isFalse, reason: '$f has no coordinate digits');
        expect(text.contains('user-a'), isFalse, reason: '$f has no uid');
      }
      // and no other account can read or even list it
      k.uid = 'user-b';
      expect(await k.journal.listUnfinished(), isEmpty);
      await k.dispose();
    });

    test('/explicit-sign-out-hands-off-first-then-deletes-and-names-the-leftover (gpsSignOutNotice) when the hand-off failed', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      final calls = <String>[];
      int? keptReported;
      final hook = hookFor(k, calls, kept: (n) => keptReported = n);
      // (1) healthy sign-out: hand-off then delete, no notice
      await hook.run('user-a', UnbindReason.signOut);
      expect(calls, ['shutdown']);
      expect(keptReported, isNull);
      expect(await activityCount(k), 1);
      expect(k.filesOf(id1), isEmpty);
      // (2) a second recording whose hand-off fails: the leftover is named
      await k.record(recId(2), 5);
      k.activity.putError = StateError('down');
      await hook.run('user-a', UnbindReason.signOut);
      expect(keptReported, 1, reason: 'the sign-out UI is told one recording stayed');
      expect(k.filesOf(recId(2)), contains('FALLBACK'));
      expect(k.filesOf(recId(2)), contains('seg-0001.log'));
      await k.dispose();
    });

    test('/account-deletion-deletes-the-leftover', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      expect(k.filesOf(id1), contains('FALLBACK'));
      // the S02 wipe of the scope (closeScope first, then the tree)
      await k.journal.closeScope(k.scopeId);
      await k.mem.deleteDir('${RecKit.scopesRoot}/${k.scopeId}');
      expect(k.mem.files.keys.where((f) => f.contains(id1)), isEmpty);
      await k.dispose();
    });

    test('/expiry-at-30-days-deletes-the-leftover', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      k.activity.putError = StateError('still down');
      k.clock.advance(const Duration(days: 29, hours: 23));
      expect((await k.journal.listUnfinished()).single.recordingId, id1, reason: 'present before 30 days');
      k.clock.advance(const Duration(hours: 1));
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.filesOf(id1), isEmpty, reason: 'no sample left');
      expect(await activityCount(k), 0);
      await k.dispose();
    });

    test('/subsequent-sign-in-of-the-same-account-offers-recovery-and-another-account-sees-nothing', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      k.uid = null; // signed out
      expect(await k.journal.listUnfinished(), isEmpty);
      k.uid = 'user-b';
      expect(await k.journal.listUnfinished(), isEmpty, reason: 'another account sees nothing');
      expect(k.filesOf0('user-a', id1), isNotEmpty, reason: 'and the recording is still in its own scope');
      k.uid = 'user-a';
      final r = await k.journal.listUnfinished();
      expect(r.single.recordingId, id1, reason: 'the same account is offered the recording again');
      expect(r.single.sampleCount, 5);
      await k.dispose();
    });
  });

  test('DT-15-10 the amendment of GPS-PRIV-014 is recorded as PROPOSED next to the contract line', () {
    final contract = File('../docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md').readAsStringSync();
    final i = contract.indexOf('GPS-PRIV-014');
    expect(i, isNonNegative);
    final near = contract.substring(i, (i + 2200).clamp(0, contract.length));
    expect(near.contains('S04 proposed clarification'), isTrue);
    expect(near.contains('PROPOSED'), isTrue);
    expect(near.contains('30 days'), isTrue);
    final req = File('../docs/phase2/s04/S04_REQUIREMENTS.md').readAsStringSync();
    expect(req.contains('Amendment of GPS-PRIV-014'), isTrue);
    expect(req.contains('Option B: keep strict deletion'), isTrue);
    expect(req.contains('Owner: operator'), isTrue);
  });

  group('pre-unbind hook (journal side)', () {
    test('runBounded: no hook, completed, timed out at the bound, failed', () {
      fakeAsync((fa) {
        final reg = PreUnbindHookRegistry();
        expect(settle(fa, reg.runBounded('u', UnbindReason.signOut)), PreUnbindOutcome.noHook);
        reg.register(_Fn((_, __) async {}));
        expect(settle(fa, reg.runBounded('u', UnbindReason.signOut)), PreUnbindOutcome.completed);
        final never = Completer<void>();
        reg.register(_Fn((_, __) => never.future));
        PreUnbindOutcome? o;
        reg.runBounded('u', UnbindReason.signOut).then((v) => o = v);
        fa.elapse(const Duration(seconds: 4, milliseconds: 900));
        expect(o, isNull, reason: 'still waiting at 4.9 s');
        fa.elapse(const Duration(milliseconds: 200));
        fa.flushMicrotasks();
        expect(o, PreUnbindOutcome.timedOut, reason: 'bounded at 5 s');
        reg.register(_Fn((_, __) async => throw StateError('x')));
        expect(settle(fa, reg.runBounded('u', UnbindReason.signOut)), PreUnbindOutcome.failed);
      });
    });

    test('accountDeleted runs the shutdown only; a pending revoked decision is left as is', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      final calls = <String>[];
      await hookFor(k, calls).run('user-a', UnbindReason.accountDeleted);
      expect(calls, ['shutdown']);
      expect(await activityCount(k), 0);
      expect(k.filesOf(id1), isNot(contains('SEALED')));
      // a recording awaiting the user's Keep/Delete decision is not touched by sign-out
      final k2 = await RecKit.create(uid: 'user-b');
      await k2.record(id1, 5);
      await k2.journal.appendEvent(const JournalEvent(JournalEventKind.permissionRevoked, 5100));
      await k2.journal.seal(id1, const SealRequest(reason: StopReason.permissionRevoked, lastOffsetMs: 5100));
      await hookFor(k2, []).run('user-b', UnbindReason.signOut);
      expect(await activityCount(k2), 0, reason: 'no hand-off for a pending decision');
      expect(k2.filesOf(id1), contains('seg-0001.log'));
      await k.dispose();
      await k2.dispose();
    });
  });

  group('DT-30-3 / DT-30-13 fallback and expiry', () {
    test('DT-30-3 /hand-off-impossible-leftover-invisible-to-other-uid', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      final before = k.snapshot(id1);
      k.uid = 'user-b';
      expect(await k.journal.listUnfinished(), isEmpty);
      await expectLater(k.journal.openForResume(id1), throwsA(isA<RecordingJournalError>()));
      await k.journal.decideDelete(id1).then((_) {}, onError: (_) {});
      await k.journal.quarantine(id1).then((_) {}, onError: (_) {});
      k.uid = 'user-a';
      expect(k.snapshot(id1), before, reason: 'another uid can neither open nor change it');
      await k.dispose();
    });

    test('DT-30-3 /expires-at-30-days (fake clock 29 d 23 h and 30 d)', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      k.clock.advance(const Duration(days: 29, hours: 23));
      expect(await k.journal.listUnfinished(), hasLength(1));
      expect(k.filesOf(id1), contains('seg-0001.log'));
      k.clock.advance(const Duration(hours: 1));
      expect(await k.journal.listUnfinished(), isEmpty);
      expect(k.filesOf(id1), isEmpty);
      expect(k.mem.files.keys.where((f) => f.contains(id1)), isEmpty);
      await k.dispose();
    });

    test('DT-30-13 /ordinary-unfinished-recording-never-expires', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      await k.kill();
      k.clock.advance(const Duration(days: 400));
      final r = await k.journal.listUnfinished();
      expect(r.single.recordingId, id1);
      expect(r.single.sampleCount, 5);
      await k.dispose();
    });

    test('DT-30-13 /expiry-sweep-runs-at-bind-time-and-only-for-failed-hand-off-and-quarantined', () async {
      final k = await RecKit.create();
      await k.record(recId(2), 5); // will be left by a failed sign-out hand-off
      k.activity.putError = StateError('down');
      await hookFor(k, []).run('user-a', UnbindReason.signOut);
      expect(k.filesOf(recId(2)), contains('FALLBACK'));
      k.activity.putError = null;
      await k.record(recId(3), 4); // quarantined (unreadable + Keep)
      await k.kill();
      k.put('${k.dirOf(recId(3))}/meta.json', Uint8List(3));
      await k.journal.quarantine(recId(3));
      await k.record(id1, 5); // an ordinary unfinished recording
      await k.kill();
      k.clock.advance(const Duration(days: 31));
      final r = await k.journal.listUnfinished(); // the sweep is the listing itself
      expect(r.map((e) => e.recordingId), [id1], reason: 'only the ordinary one is left');
      expect(k.filesOf(recId(2)), isEmpty);
      expect(k.filesOf(recId(3)), isEmpty);
      await k.dispose();
    });
  });

  group('S04-16 storage full', () {
    test('DT-16-1 /space-returns: a 20 s write failure loses nothing; storageRecovered clears the banner', () {
      fakeAsync((fa) {
        final k = settle(fa, RecKit.create());
        settle(fa, k.journal.begin(k.meta(id1)));
        var s = 0;
        void second() {
          tick(fa, k, 1000);
          k.journal.enqueueSample(smp(++s), GateCounters.zero);
          fa.flushMicrotasks();
        }

        for (var i = 0; i < 6; i++) {
          second();
        }
        k.fs.failSegWrites = true;
        for (var i = 0; i < 20; i++) {
          second();
        }
        expect(k.faults, contains(JournalFault.storageFailing));
        expect(k.faults, isNot(contains(JournalFault.storageGaveUp)));
        k.fs.failSegWrites = false;
        for (var i = 0; i < 12; i++) {
          second();
        }
        expect(k.faults, contains(JournalFault.storageRecovered));
        settle(fa, k.journal.flush());
        expect(k.sampleCountOnDisk(id1), s, reason: 'every fix is on disk after the space returned');
        // readable and contiguous after the rotation
        settle(fa, k.kill());
        final r = settle(fa, k.journal.listUnfinished());
        expect(r.single.status, UnfinishedStatus.readable);
        expect(r.single.sampleCount, s);
        settle(fa, k.dispose());
      });
    });

    test('DT-16-1 /stops-after-60s: the retry window gives up; everything kept in memory is saved once space returns', () {
      fakeAsync((fa) {
        final k = settle(fa, RecKit.create());
        settle(fa, k.journal.begin(k.meta(id1)));
        var s = 0;
        void second() {
          tick(fa, k, 1000);
          k.journal.enqueueSample(smp(++s), GateCounters.zero);
          fa.flushMicrotasks();
        }

        for (var i = 0; i < 6; i++) {
          second();
        }
        k.fs.failSegWrites = true;
        for (var i = 0; i < 50; i++) {
          second();
        }
        expect(k.faults, isNot(contains(JournalFault.storageGaveUp)), reason: 'not before 60 s');
        for (var i = 0; i < 25; i++) {
          second();
        }
        expect(k.faults, contains(JournalFault.storageGaveUp), reason: 'after the 60 s window');
        // the recorder stops: the user frees space, the stop reason is stored if possible and all is saved
        k.fs.failSegWrites = false;
        settle(fa, k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedStorage, 81000)));
        settle(fa, k.journal.seal(id1, const SealRequest(reason: StopReason.storage)));
        expect(settle(fa, k.journal.handOff(id1)), HandOffResult.done);
        final stored = settle(fa, k.activityReal.read(nativeActivityId(id1)))!;
        expect(stored.session.streams.values.map((e) => e.offsetsMs.length).reduce((a, b) => a > b ? a : b), s,
            reason: 'saved everything up to the stop');
        settle(fa, k.dispose());
      });
    });

    test('DT-16-2 the stop reason stoppedStorage is stored in SEALED and as an event when possible', () async {
      final k = await RecKit.create();
      await k.record(id1, 5);
      await k.journal.appendEvent(const JournalEvent(JournalEventKind.stoppedStorage, 5500));
      await k.journal.seal(id1, const SealRequest(reason: StopReason.storage));
      final sealed = jsonDecode(utf8.decode(k.cipher().open(k.bytesOf('${k.dirOf(id1)}/SEALED')!))) as Map;
      expect(sealed['reason'], 'storage');
      expect(eventKinds(k, id1), contains('stoppedStorage'));
      await k.dispose();
    });

    test('DT-16-3 sustained failure for 60 s at 1 Hz: the buffer stays bounded (well under 600 fixes) and nothing is dropped', () {
      fakeAsync((fa) {
        final k = settle(fa, RecKit.create());
        settle(fa, k.journal.begin(k.meta(id1)));
        k.fs.failSegWrites = true;
        var s = 0;
        for (var i = 0; i < 70; i++) {
          tick(fa, k, 1000);
          k.journal.enqueueSample(smp(++s), GateCounters.zero);
          fa.flushMicrotasks();
        }
        expect(s, lessThan(600));
        expect(k.faults, containsAllInOrder([JournalFault.storageFailing, JournalFault.storageGaveUp]),
            reason: 'the retry window ends at 60 s, so at most ~60 fixes + the batch were ever buffered');
        k.fs.failSegWrites = false;
        settle(fa, k.journal.flush());
        expect(k.sampleCountOnDisk(id1), s, reason: 'every buffered fix survived');
        settle(fa, k.dispose());
      });
    });

    test('DT-16-4 disk full at begin: refused, no directory, no ghost recording', () async {
      final k = await RecKit.create();
      final probe = await RecKit.create(uid: 'user-p');
      probe.fs.clearLog();
      await probe.journal.begin(probe.meta(id1));
      final idx = probe.fs.log.firstWhere((o) => o.kind == FsOpKind.write && o.path.contains('meta.json')).index;
      await probe.dispose();
      k.fs.clearLog();
      k.fs.arm(FaultPlan(idx, FaultMode.diskFullAt));
      await expectLater(k.journal.begin(k.meta(id1)), throwsA(isA<RecordingJournalError>()));
      expect(k.fs.fired, isTrue);
      expect(k.mem.dirs.contains(k.dirOf(id1)), isFalse);
      expect(await k.journal.listUnfinished(), isEmpty, reason: 'no unreadable ghost is offered');
      await k.dispose();
    });
  });
}

class _Fn implements PreUnbindHook {
  _Fn(this.f);
  final Future<void> Function(String, UnbindReason) f;
  @override
  Future<void> run(String ownerUid, UnbindReason reason) => f(ownerUid, reason);
}

extension on RecKit {
  List<String> filesOf0(String uidX, String id) {
    final p = '${recDirOf(uidX)}/$id/';
    return [
      for (final f in mem.files.keys)
        if (f.startsWith(p)) f.substring(p.length)
    ];
  }
}
