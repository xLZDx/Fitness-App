// S02 remediation E1 (test epic 11a): the account-scoped journal. Oracles:
// docs/phase2/s02/S02_REMEDIATION_E_TEST_NOTES.md heading E1, S02_DESIGN.md
// 6.2, 7 and 17 (item 22) and the lessons-log promise "signing in as someone
// else never destroys my data", not the code under test.
//
// Real FileActivityJournal on a temp directory; a fake secure store with one
// key per scope.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// A journal whose recovery pass throws.
class _BrokenStart extends Fake implements ActivityJournal {
  int closes = 0;

  @override
  Future<JournalRecoveryReport> start() async =>
      throw StateError('recovery failed');

  @override
  Future<void> close() async => closes++;
}

String _fingerprint(ActivitySession s) =>
    '${sessionJson(s)}|${jsonEncode(streamsOf(s))}';

final _hex32 = RegExp(r'^[0-9a-f]{32}$');

void main() {
  late ScopedJournalWorld w;

  setUp(() async => w = await ScopedJournalWorld.create());
  tearDown(() => w.dispose());

  UidScopedActivityJournal j() => w.journal;

  Future<void> putFor(String uid, int n) async {
    expect(await j().bindUid(uid), isTrue);
    await j().put(journalSession(idFor(n), seed: n));
  }

  Future<List<String>> ids() async => [for (final e in await j().list()) e.id]
    ..sort();

  group('persistence across accounts', () {
    test('A to B to A: A\'s sessions, streams, sources, quarantine and key are '
        'identical; B never sees A', () async {
      await putFor('A', 1);
      await j().put(journalSession(idFor(2), seed: 2));
      await w.writeSide('A', 'sources/garmin.cursor.json', '{"cursor":1}');
      await w.writeSide('A', 'quarantine/rejected-1.json', '{"raw":1}');
      final before = {
        for (final id in [idFor(1), idFor(2)])
          id: _fingerprint((await j().read(id))!.session),
      };
      final keyA = w.storage.values.entries
          .where((e) => e.key.endsWith(activityJournalScopeId('A')))
          .single;

      expect(await j().bindUid('B'), isTrue);
      expect(await ids(), isEmpty, reason: 'B starts empty');
      expect(await j().read(idFor(1)), isNull, reason: 'B cannot read A');
      await j().put(journalSession(idFor(3), seed: 3));
      expect(await ids(), [idFor(3)]);

      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), [idFor(1), idFor(2)]);
      for (final id in [idFor(1), idFor(2)]) {
        final e = (await j().read(id))!;
        expect(_fingerprint(e.session), before[id],
            reason: 'A\'s $id is byte-for-byte the same session');
        expect(e.streamLost, isFalse);
      }
      expect(await j().read(idFor(3)), isNull, reason: 'A cannot read B');
      expect(
          File('${w.rootOf('A')}/sources/garmin.cursor.json').readAsStringSync(),
          '{"cursor":1}');
      expect(
          File('${w.rootOf('A')}/quarantine/rejected-1.json')
              .readAsStringSync(),
          '{"raw":1}');
      expect(
          w.storage.values.entries
              .where((e) => e.key.endsWith(activityJournalScopeId('A')))
              .single
              .value,
          keyA.value,
          reason: 'A\'s stream key was not regenerated');
      expect(w.storage.deletes, 0, reason: 'no key was ever deleted');
    });

    test('sign-out (bindUid(null)) keeps every file on disk and unbinds',
        () async {
      await putFor('A', 1);
      await w.writeSide('A', 'sources/s.json', '{}');
      final before = await w.snapshot('A');
      expect(before, isNotEmpty, reason: 'precondition');

      expect(await j().bindUid(null), isTrue);
      expect(j().boundUid, isNull);
      expect(await w.snapshot('A'), before, reason: 'nothing was deleted');
      expect(w.storage.deletes, 0);
      expect(await ids(), isEmpty, reason: 'reads are empty while unbound');

      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), [idFor(1)], reason: 'sign back in: data is there');
    });

    test('the scope id is a hash: no directory name and no key name contains '
        'the raw uid', () async {
      const uid = 'user-ABC-123';
      await putFor(uid, 1);
      final scope = activityJournalScopeId(uid);
      expect(scope, matches(_hex32));
      expect(scope, isNot(contains('user')));
      expect(activityJournalScopeId(uid), scope, reason: 'deterministic');
      expect(activityJournalScopeId('user-ABC-124'), isNot(scope));
      expect(await w.scopeDirs(), [scope]);
      expect(w.opened, [scope]);
      expect(w.storage.values.keys, hasLength(1));
      final key = w.storage.values.keys.single;
      expect(key, '${SecureStorageJournalKeyProvider.keyName}.$scope');
      expect(key, isNot(contains(uid)));
      expect(Directory(w.base).listSync(recursive: true).map((e) => e.path),
          everyElement(isNot(contains(uid))));
    });

    test('the production factory uses <support>/activity_journal/<hash> and '
        'the default key name stays for an unscoped provider', () async {
      final saved = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(w.tmp.path);
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      addTearDown(() => PathProviderPlatform.instance = saved);

      final prod = UidScopedActivityJournal();
      addTearDown(prod.close);
      expect(await prod.bindUid('user-ABC-123'), isTrue);
      await prod.put(journalSession(idFor(1), seed: 1));
      expect(await w.scopeDirs(), [activityJournalScopeId('user-ABC-123')]);
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.keys.single,
          'activity_journal.key.v1.${activityJournalScopeId('user-ABC-123')}');

      expect(SecureStorageJournalKeyProvider().keyNameInUse,
          'activity_journal.key.v1',
          reason: 'no scope = the original key name');
    });
  });

  group('unbound journal', () {
    test('reads are empty', () async {
      expect(j().boundUid, isNull);
      expect(await j().list(), isEmpty);
      expect(await j().listTombstones(), isEmpty);
      expect(await j().read(idFor(1)), isNull);
      expect(j().streamLostCount, 0);
      final a = await j().assessSignOut();
      expect((a.entryCount, a.unsyncedCount, a.streamLostCount), (0, 0, 0));
    });

    test('every write is refused with JournalUnbound and lands nowhere',
        () async {
      await putFor('A', 1);
      await j().bindUid(null);
      final before = await w.snapshot('A');
      final s = journalSession(idFor(9), seed: 9);
      final writes = <String, Future<Object?> Function()>{
        'put': () => j().put(s),
        'delete': () => j().delete(idFor(1)),
        'updateSyncState': () =>
            j().updateSyncState(idFor(1), JournalSyncState.synced),
        'updateRecord': () => j().updateRecord(idFor(1), s),
        'markSynced': () => j().markSynced(idFor(1)),
        'markStreamUploaded': () => j().markStreamUploaded(idFor(1)),
        'wipe': () => j().wipe(),
      };
      for (final e in writes.entries) {
        await expectLater(e.value(), throwsA(isA<JournalUnbound>()),
            reason: e.key);
      }
      expect(await w.snapshot('A'), before, reason: 'no write reached disk');
      expect(await w.scopeDirs(), [activityJournalScopeId('A')],
          reason: 'no other scope was created');
    });

    test('JournalUnbound is a JournalWriteFailure (callers fail closed)', () {
      expect(const JournalUnbound(), isA<JournalWriteFailure>());
    });
  });

  group('bindUid', () {
    test('idempotent for the same uid: one open, the journal keeps working',
        () async {
      await putFor('A', 1);
      expect(await j().bindUid('A'), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(w.opened, [activityJournalScopeId('A')]);
      expect(await ids(), [idFor(1)]);
    });

    test('bindUid(null) while unbound is true and opens nothing', () async {
      expect(await j().bindUid(null), isTrue);
      expect(w.opened, isEmpty);
    });

    test('an empty uid fails closed and unbinds', () async {
      await putFor('A', 1);
      expect(await j().bindUid(''), isFalse);
      expect(j().boundUid, isNull);
      expect(await ids(), isEmpty);
    });

    test('concurrent bindUid(A), bindUid(B), bindUid(A): serialized, the last '
        'request wins, every open succeeds (no second journal on one root)',
        () async {
      final gate = w.gate = Completer<void>();
      final f1 = j().bindUid('A');
      final f2 = j().bindUid('B');
      final f3 = j().bindUid('A');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(w.opened, [activityJournalScopeId('A')],
          reason: 'B and the second A wait for the first bind');
      gate.complete();
      expect(await Future.wait([f1, f2, f3]), [true, true, true]);
      expect(j().boundUid, 'A');
      expect(w.opened, [
        activityJournalScopeId('A'),
        activityJournalScopeId('B'),
        activityJournalScopeId('A'),
      ]);
      await j().put(journalSession(idFor(1), seed: 1));
      expect(await ids(), [idFor(1)]);
    });

    test('concurrent bindUid(A), bindUid(B): ends in B, never a mix',
        () async {
      await putFor('A', 1);
      final f = [j().bindUid('B'), j().bindUid('A'), j().bindUid('B')];
      expect(await Future.wait(f), [true, true, true]);
      expect(j().boundUid, 'B');
      expect(await ids(), isEmpty, reason: 'B\'s reads, not A\'s');
      await j().put(journalSession(idFor(2), seed: 2));
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), [idFor(1)], reason: 'the put went to B only');
    });

    test('a switch to null requested during an in-flight bind ends unbound',
        () async {
      final gate = w.gate = Completer<void>();
      final f1 = j().bindUid('A');
      final f2 = j().bindUid(null);
      gate.complete();
      expect(await f1, isTrue);
      expect(await f2, isTrue);
      expect(j().boundUid, isNull);
      await expectLater(
          j().put(journalSession(idFor(1), seed: 1)),
          throwsA(isA<JournalUnbound>()));
    });

    test('open throws: false, nothing bound, reads empty, writes refused',
        () async {
      w.failOpen.add(activityJournalScopeId('A'));
      expect(await j().bindUid('A'), isFalse);
      expect(j().boundUid, isNull);
      expect(await ids(), isEmpty);
      await expectLater(j().put(journalSession(idFor(1), seed: 1)),
          throwsA(isA<JournalUnbound>()));
      // Control: once the open works the same uid binds.
      w.failOpen.clear();
      expect(await j().bindUid('A'), isTrue);
      expect(j().boundUid, 'A');
    });

    test('a failed switch leaves the previous account UNbound, not bound',
        () async {
      await putFor('B', 1);
      w.failOpen.add(activityJournalScopeId('A'));
      expect(await j().bindUid('A'), isFalse);
      expect(j().boundUid, isNull);
      expect(await ids(), isEmpty, reason: 'B\'s data is not exposed to A');
      await expectLater(j().put(journalSession(idFor(2), seed: 2)),
          throwsA(isA<JournalUnbound>()),
          reason: 'a write cannot land in B while A is signed in');
      w.failOpen.clear();
      expect(await j().bindUid('B'), isTrue);
      expect(await ids(), [idFor(1)]);
    });

    test('recovery (start) throws: false, nothing bound, the half-open '
        'journal is closed', () async {
      final broken = _BrokenStart();
      final scoped = UidScopedActivityJournal(
          scopesRoot: () async => '${w.base}/activity_journal',
          factory: (_) async => broken);
      expect(await scoped.bindUid('A'), isFalse);
      expect(scoped.boundUid, isNull);
      expect(broken.closes, 1);
      expect(await scoped.list(), isEmpty);
    });

    test('a copied or restored directory of A never opens for B', () async {
      await putFor('A', 1);
      await j().bindUid(null);
      // A backup restore puts A's files under another name and damages A's
      // own scope: no key, a corrupt CURRENT.
      final src = Directory(w.rootOf('A'));
      final copy = Directory('${w.base}/activity_journal/restored_copy_of_a');
      await copy.create(recursive: true);
      await for (final e in src.list(recursive: true)) {
        final rel = e.path.replaceAll('\\', '/').substring(
            src.path.replaceAll('\\', '/').length);
        if (e is File) {
          final t = File('${copy.path}$rel');
          await t.parent.create(recursive: true);
          await e.copy(t.path);
        }
      }
      w.storage.values.clear();
      for (final f in src.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('CURRENT')) f.writeAsBytesSync([0, 1, 2]);
      }
      w.opened.clear();

      expect(await j().bindUid('B'), isTrue);
      expect(w.opened, [activityJournalScopeId('B')],
          reason: 'only B\'s own scope is ever opened for B');
      expect(await ids(), isEmpty);
      expect(await j().read(idFor(1)), isNull);
      await j().put(journalSession(idFor(5), seed: 5));
      expect(await ids(), [idFor(5)]);
    });
  });

  group('wipes', () {
    Future<void> twoAccounts() async {
      await putFor('A', 1);
      await w.writeSide('A', 'sources/a.json', '{"a":1}');
      await putFor('B', 2);
      await w.writeSide('B', 'quarantine/b.json', '{"b":1}');
    }

    String keyOf(String uid) =>
        '${SecureStorageJournalKeyProvider.keyName}.${activityJournalScopeId(uid)}';

    test('wipeForUid(A) while unbound wipes only A: B is byte-identical',
        () async {
      await twoAccounts();
      await j().bindUid(null);
      final b = await w.snapshot('B');
      final bKey = w.storage.values[keyOf('B')];

      await j().wipeForUid('A');

      expect(await w.snapshot('B'), b);
      expect(w.storage.values[keyOf('B')], bKey);
      expect(w.storage.values.containsKey(keyOf('A')), isFalse,
          reason: 'A\'s key is gone');
      expect(j().boundUid, isNull);
      expect(File('${w.rootOf('A')}/sources/a.json').existsSync(), isFalse);
      // Remediation G4: refused until bindUid(null) clears the marker.
      expect(await j().bindUid('A'), isFalse);
      expect(await j().bindUid(null), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), isEmpty);
      expect(await j().bindUid('B'), isTrue);
      expect(await ids(), [idFor(2)]);
    });

    test('wipeForUid(A) while B is bound does not touch B and keeps B bound',
        () async {
      await twoAccounts(); // B is bound now
      final b = await w.snapshot('B');
      await j().wipeForUid('A');
      expect(j().boundUid, 'B');
      expect(await ids(), [idFor(2)]);
      expect(await w.snapshot('B'), b);
      await j().put(journalSession(idFor(3), seed: 3));
      expect(await ids(), [idFor(2), idFor(3)], reason: 'B still writable');
      // Remediation G4: refused (and B unbound) until bindUid(null).
      expect(await j().bindUid('A'), isFalse);
      expect(await j().bindUid(null), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), isEmpty);
      expect(File('${w.rootOf('A')}/sources/a.json').existsSync(), isFalse);
    });

    test('wipeForUid(bound uid) wipes it and leaves the journal unbound',
        () async {
      await twoAccounts();
      await j().wipeForUid('B');
      expect(j().boundUid, isNull);
      expect(await ids(), isEmpty);
      await expectLater(j().put(journalSession(idFor(7), seed: 7)),
          throwsA(isA<JournalUnbound>()));
      expect(w.storage.values.containsKey(keyOf('B')), isFalse);
      expect(File('${w.rootOf('B')}/quarantine/b.json').existsSync(), isFalse);
      expect(w.storage.values.containsKey(keyOf('A')), isTrue);
      // Remediation F2: the wiped uid cannot be re-bound by a re-emission.
      expect(await j().bindUid('B'), isFalse);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), [idFor(1)]);
      // Another uid ended the refusal: a later genuine sign-in of B is clean.
      expect(await j().bindUid('B'), isTrue);
      expect(await ids(), isEmpty);
    });

    test('wipeForUid with an empty uid is refused', () async {
      await expectLater(j().wipeForUid(''), throwsA(isA<JournalUnbound>()));
    });

    test('wipe() wipes only the bound scope', () async {
      await twoAccounts();
      final a = await w.snapshot('A');
      await j().wipe();
      expect(await ids(), isEmpty);
      expect(await w.snapshot('A'), a, reason: 'A untouched');
      expect(w.storage.values.containsKey(keyOf('B')), isFalse);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), [idFor(1)]);
    });
  });
}
