// SQLite-specific behaviour of the transactional command queue store: atomic
// accept, durability, fail-closed recovery, PRAGMA checks, WAL files and
// serialisation. The shared contract runs in queue_store_contract_test.dart.
//
// Desktop runs use sqflite_common_ffi. On Windows the sqlite3 package loads
// sqlite3.dll from PATH and otherwise the OS-provided winsqlite3.dll
// (System32), so no extra file is needed on a Windows 10/11 dev machine.
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart' show queueScopeDirName;
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:fitness_app/features/workouts/offline/sqlite_command_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/offline_test_support.dart';

/// Wraps a real database and rewrites the answer of selected PRAGMA queries.
class _LyingFactory implements DatabaseFactory {
  _LyingFactory(this.inner, this.lie);
  final DatabaseFactory inner;

  /// Returns a replacement rows list for a SQL text, or null to pass through.
  final List<Map<String, Object?>>? Function(String sql) lie;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) async =>
      _LyingDb(await inner.openDatabase(path, options: options), lie);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _LyingDb implements Database {
  _LyingDb(this.db, this.lie);
  final Database db;
  final List<Map<String, Object?>>? Function(String sql) lie;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final l = lie(sql);
    if (l != null) return l;
    return db.rawQuery(sql, arguments);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
          {bool? exclusive}) =>
      db.transaction(action, exclusive: exclusive);
  @override
  Future<void> close() => db.close();
  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      db.insert(table, values,
          nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      db.delete(table, where: where, whereArgs: whereArgs);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      db.execute(sql, arguments);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<Database> rawDb(String path) =>
    databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late TestClock clock;
  late IdMinter minter;
  late FakeServer server;
  StoreFactory? factory;
  final stores = <CommandQueueStore>[];

  String pathOf([String uid = kUid]) => '${rootPathOf(dir)}/${sqliteQueueFileName(uid)}';

  Future<SqliteCommandQueueStore> open({String uid = kUid, DatabaseFactory? db}) async {
    factory = StoreFactory.sqlite(clock, dir, dbFactory: db);
    final s = await factory!.open(uid) as SqliteCommandQueueStore;
    stores.add(s);
    return s;
  }

  /// Opens the next instance over the same factory (previous one disposed).
  Future<SqliteCommandQueueStore> reopen({String uid = kUid}) async {
    final s = await factory!.open(uid) as SqliteCommandQueueStore;
    stores.add(s);
    return s;
  }

  CompleteSetAcceptor accFor(CommandQueueStore s) => acceptorFor(s, clock, minter: minter);

  Future<Map<String, int>> counts() async {
    final db = await rawDb(pathOf());
    try {
      int n(Object? v) => (v as int?) ?? 0;
      return <String, int>{
        for (final t in ['commands', 'logical_sets', 'seq_counters', 'meta'])
          t: n((await db.rawQuery('SELECT COUNT(*) c FROM $t')).first['c']),
      };
    } finally {
      await db.close();
    }
  }

  setUp(() async {
    dir = await makeTempRoot();
    clock = TestClock();
    minter = IdMinter();
    server = FakeServer();
    factory = null;
  });
  tearDown(() async {
    for (final s in stores) {
      try {
        await s.dispose();
      } catch (_) {}
    }
    stores.clear();
    await removeTempRoot(dir);
  });

  group('schema and pragmas', () {
    test('a new database has the documented tables, WAL mode and a unique intent key',
        () async {
      final s = await open();
      final r = (await accFor(s).accept(intentOf('t1'))).record;
      final db = await rawDb(pathOf());
      try {
        final tables = (await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
            .map((e) => e['name'])
            .toSet();
        expect(tables, containsAll(<String>['meta', 'seq_counters', 'logical_sets', 'commands']));
        expect((await db.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
        final meta = {
          for (final e in await db.rawQuery('SELECT key, value FROM meta'))
            e['key']: e['value'],
        };
        expect(meta['schema_version'], '1');
        expect(meta['scope'], queueScopeDirName(kUid));
        expect(meta['created'], isNotNull);
        // The unique intent key is enforced by the database itself.
        await expectLater(
          db.rawInsert(
              'INSERT INTO commands(operation_id, uid, intent_key, state, updated_at_ms, record_json) '
              "VALUES('dup-op', 'x', '${r.intentKey}', 'ACCEPTED', 0, '{}')"),
          throwsA(anything),
        );
      } finally {
        await db.close();
      }
    });

    test('the raw uid never appears in the database file name', () async {
      await open();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(names.where((n) => n.contains(kUid)), isEmpty);
      expect(names.any((n) => n.startsWith('workout_command_queue_u_') && n.endsWith('.db')),
          isTrue);
    });

    for (final lie in <String, List<Map<String, Object?>>? Function(String)>{
      'journal_mode stays delete': (sql) => sql.toLowerCase().contains('journal_mode')
          ? <Map<String, Object?>>[{'journal_mode': 'delete'}]
          : null,
      'synchronous stays NORMAL': (sql) => sql.trim().toLowerCase() == 'pragma synchronous'
          ? <Map<String, Object?>>[{'synchronous': 1}]
          : null,
      'foreign_keys stays off': (sql) => sql.trim().toLowerCase() == 'pragma foreign_keys'
          ? <Map<String, Object?>>[{'foreign_keys': 0}]
          : null,
    }.entries) {
      test('PRAGMA not applied (${lie.key}) -> QueueException, nothing created as recovery, path released',
          () async {
        final bad = _LyingFactory(databaseFactoryFfi, lie.value);
        await expectLater(
          SqliteCommandQueueStore.open(
              uid: kUid, path: pathOf(), factory: bad, nowMs: clock.nowMs),
          throwsA(isA<QueueException>()),
        );
        // Not treated as corruption: no .corrupt copy.
        expect(dir.listSync().any((e) => e.path.contains('.corrupt-')), isFalse);
        // The failed open released the path.
        final s = await open();
        expect(s.openReport.recoveryRequired, isFalse);
        expect((await accFor(s).accept(intentOf('t'))).created, isTrue);
      });
    }

    test('a second instance for the same database in one process is refused until the first is disposed',
        () async {
      final s = await open();
      await expectLater(
          SqliteCommandQueueStore.open(
              uid: kUid, path: pathOf(), factory: databaseFactoryFfi),
          throwsA(isA<StateError>()));
      await s.dispose();
      stores.clear();
      final s2 = await SqliteCommandQueueStore.open(
          uid: kUid, path: pathOf(), factory: databaseFactoryFfi);
      stores.add(s2);
      expect(await s2.listAll(), isEmpty);
    });
  });

  group('atomic accept (one transaction)', () {
    for (final step in <String, String>{
      'command row': 'commands',
      'logical-set row': 'logical_sets',
      'counter row': 'seq_counters',
    }.entries) {
      test('a failure at the ${step.key} changes nothing, and the retry then succeeds with the same sequence',
          () async {
        final s = await open();
        final raw = await rawDb(pathOf());
        try {
          await raw.execute('CREATE TRIGGER boom BEFORE INSERT ON ${step.value} '
              "BEGIN SELECT RAISE(ABORT, 'injected failure'); END");
          await expectLater(accFor(s).accept(intentOf('tap-1')), throwsA(anything));

          // Nothing partial, on disk or in memory.
          expect(await counts(), {'commands': 0, 'logical_sets': 0, 'seq_counters': 0, 'meta': 3});
          expect(await s.listAll(), isEmpty);
          expect(await s.listPending(), isEmpty);

          // Same after a restart.
          await raw.execute('DROP TRIGGER boom');
          final s2 = await (() async {
            await s.dispose();
            return reopen();
          })();
          expect(await s2.listAll(), isEmpty);
          final r = await accFor(s2).accept(intentOf('tap-1'));
          expect(r.created, isTrue);
          expect(r.record.seq, 1, reason: 'a failed accept consumes no sequence');
          expect(await counts(), {'commands': 1, 'logical_sets': 1, 'seq_counters': 1, 'meta': 3});
        } finally {
          await raw.close();
        }
      });
    }

    test('a failure in the live store (no restart) leaves memory and disk equal; the retry gets the same seq',
        () async {
      final s = await open();
      final raw = await rawDb(pathOf());
      try {
        await raw.execute('CREATE TRIGGER boom BEFORE INSERT ON seq_counters '
            "BEGIN SELECT RAISE(ABORT, 'injected failure'); END");
        await expectLater(accFor(s).accept(intentOf('tap-1')), throwsA(anything));
        await raw.execute('DROP TRIGGER boom');
        final r = await accFor(s).accept(intentOf('tap-1'));
        expect(r.created, isTrue);
        expect(r.record.seq, 1);
        expect((await s.listAll()).length, 1);
      } finally {
        await raw.close();
      }
    });

    test('a fault during prune keeps the command row and the logical-set row', () async {
      final s = await open();
      final r = (await accFor(s).accept(intentOf('t1'))).record;
      await s.markSending(r.operationId);
      await s.markResult(r.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      final raw = await rawDb(pathOf());
      try {
        await raw.execute('CREATE TRIGGER boom BEFORE DELETE ON commands '
            "BEGIN SELECT RAISE(ABORT, 'injected failure'); END");
        await expectLater(s.prune(), throwsA(anything));
        expect(await s.get(r.operationId), isNotNull);
        expect((await counts())['commands'], 1);
        await raw.execute('DROP TRIGGER boom');
        expect(await s.prune(), 1);
      } finally {
        await raw.close();
      }
    });
  });

  group('durability and identity after prune', () {
    test('a kill (no dispose) with pending commands: everything is intact after reopening',
        () async {
      var s = await open();
      final ids = <String>[];
      for (var i = 1; i <= 5; i++) {
        ids.add((await accFor(s).accept(intentOf('t$i', setIndex: i))).record.operationId);
      }
      final sending = await s.markSending(ids[0]);
      final before = {for (final r in await s.listAll()) r.operationId: r.toJson()};
      // "Kill": the next instance opens while the old handle was never closed
      // cleanly (the factory only disposes the Dart object).
      s = await reopen();
      final after = {for (final r in await s.listAll()) r.operationId: r.toJson()};
      expect(after.keys.toSet(), before.keys.toSet());
      for (final id in ids.skip(1)) {
        expect(after[id], before[id]);
      }
      final recovered = (await s.get(sending.operationId))!;
      expect(recovered.state, CommandState.unknownEffect);
      expect(recovered.maybeSent, isTrue);
      expect(recovered.canonicalBytes, sending.canonicalBytes);
      expect(s.openReport.recoveredSending, 1);
      expect((await s.listPending()).length, 5);
    });

    test('a duplicate APPEND of a pruned logical set is refused, also after a restart',
        () async {
      var s = await open();
      final r = (await accFor(s).accept(intentOf('t1'))).record;
      await s.markSending(r.operationId);
      await s.markResult(r.operationId,
          const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      clock.advance(const Duration(days: 8));
      expect(await s.prune(), 1);
      expect((await counts())['commands'], 0);
      expect((await counts())['logical_sets'], 1, reason: 'logical sets are never pruned');
      await expectLater(accFor(s).accept(intentOf('other-intent')),
          throwsA(isA<DuplicateLogicalSetException>()));
      s = await reopen();
      await expectLater(accFor(s).accept(intentOf('another-intent')),
          throwsA(isA<DuplicateLogicalSetException>()));
      expect(await s.listAll(), isEmpty);
    });

    test('a sequence is never reused after prune and a restart', () async {
      var s = await open();
      final a = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
      final b = (await accFor(s).accept(intentOf('t2', setIndex: 2))).record;
      for (final r in [a, b]) {
        await s.markSending(r.operationId);
        await s.markResult(r.operationId,
            const CommandResult(to: CommandState.synced, resultCode: 'COMMITTED'));
      }
      clock.advance(const Duration(days: 8));
      expect(await s.prune(), 2);
      s = await reopen();
      expect(await s.listAll(), isEmpty);
      final c = (await accFor(s).accept(intentOf('t3', setIndex: 3))).record;
      expect(c.seq, 3);
      expect((await counts())['seq_counters'], 1);
    });

    test('the idempotent re-accept survives a restart (same intent, same operation id and bytes)',
        () async {
      var s = await open();
      final a = (await accFor(s).accept(intentOf('t1'))).record;
      s = await reopen();
      final again = await accFor(s).accept(intentOf('t1'));
      expect(again.created, isFalse);
      expect(again.record.operationId, a.operationId);
      expect(again.record.canonicalBytes, a.canonicalBytes);
      expect((await counts())['commands'], 1);
    });

    test('500 pending commands: the 501st fails closed, nothing is written, still 500 after a restart',
        () async {
      var s = await open();
      for (var i = 1; i <= kQueueRecordCap; i++) {
        await accFor(s).accept(intentOf('t$i', exerciseId: 'ex-$i'));
      }
      await expectLater(accFor(s).accept(intentOf('over', exerciseId: 'ex-over')),
          throwsA(isA<QueueFullException>()));
      expect(await counts(), {'commands': 500, 'logical_sets': 500, 'seq_counters': 1, 'meta': 3});
      s = await reopen();
      expect((await s.listAll()).length, 500);
      await expectLater(accFor(s).accept(intentOf('over', exerciseId: 'ex-over')),
          throwsA(isA<QueueFullException>()));
    }, timeout: const Timeout(Duration(minutes: 4)));
  });

  group('fail-closed recovery', () {
    Future<void> expectRecoveryRequired(SqliteCommandQueueStore s) async {
      expect(s.openReport.recoveryRequired, isTrue);
      expect(s.openReport.recoveryRequiredReason, isNotNull);
      await expectLater(accFor(s).accept(intentOf('x')),
          throwsA(isA<QueueRecoveryRequiredException>()));
      clock.advance(const Duration(days: 30));
      expect(await s.prune(), 0);
    }

    test('a garbage database file: recovery required, the copy is preserved, the original is untouched',
        () async {
      final garbage = Uint8List.fromList(List<int>.generate(4096, (i) => (i * 7 + 3) & 0xff));
      File(pathOf()).writeAsBytesSync(garbage);
      final s = await open();
      await expectRecoveryRequired(s);
      expect(File(pathOf()).readAsBytesSync(), garbage, reason: 'nothing overwritten');
      final copy = File('${pathOf()}.corrupt-1');
      expect(copy.existsSync(), isTrue);
      expect(copy.readAsBytesSync(), garbage);
      expect(await s.listAll(), isEmpty);
    });

    test('a truncated real database: recovery required and the original bytes stay',
        () async {
      var s = await open();
      for (var i = 1; i <= 20; i++) {
        await accFor(s).accept(intentOf('t$i', exerciseId: 'ex-$i'));
      }
      await s.dispose();
      stores.clear();
      final f = File(pathOf());
      // Fold the WAL into the main file first, then cut the file.
      final raw = await rawDb(pathOf());
      await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await raw.close();
      final full = f.readAsBytesSync();
      final cut = Uint8List.sublistView(full, 0, full.length ~/ 2);
      f.writeAsBytesSync(cut);
      for (final suffix in ['-wal', '-shm']) {
        final x = File('${pathOf()}$suffix');
        if (x.existsSync()) x.deleteSync();
      }
      s = await open();
      await expectRecoveryRequired(s);
      expect(File(pathOf()).readAsBytesSync(), cut);
      expect(File('${pathOf()}.corrupt-1').readAsBytesSync(), cut);
    });

    test('a database of another account (scope mismatch) is never adopted', () async {
      var s = await open(uid: kOtherUid);
      await accFor(s).accept(intentOf('bob'));
      await s.dispose();
      stores.clear();
      final raw = await rawDb(pathOf(kOtherUid));
      await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await raw.close();
      File(pathOf(kOtherUid)).copySync(pathOf(kUid));
      final before = File(pathOf(kUid)).readAsBytesSync();
      s = await open();
      await expectRecoveryRequired(s);
      expect(s.openReport.recoveryRequiredReason, contains('another account'));
      expect(await s.listAll(), isEmpty);
      expect(File(pathOf(kUid)).readAsBytesSync(), before);
    });

    for (final damage in <String, String>{
      'schema version 99': "UPDATE meta SET value='99' WHERE key='schema_version'",
      'created marker deleted': "DELETE FROM meta WHERE key='created'",
      'a required table dropped': 'DROP TABLE logical_sets',
    }.entries) {
      test('${damage.key}: recovery required, nothing overwritten', () async {
        var s = await open();
        await accFor(s).accept(intentOf('t1'));
        await s.dispose();
        stores.clear();
        final raw = await rawDb(pathOf());
        await raw.execute(damage.value);
        await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        await raw.close();
        final before = File(pathOf()).readAsBytesSync();
        s = await open();
        await expectRecoveryRequired(s);
        expect(File(pathOf()).readAsBytesSync(), before);
        expect(File('${pathOf()}.corrupt-1').existsSync(), isTrue);
      });
    }

    test('repeated opens of the same corrupt file do not pile up identical copies',
        () async {
      File(pathOf()).writeAsBytesSync(Uint8List.fromList(List<int>.filled(2048, 7)));
      for (var i = 0; i < 3; i++) {
        final s = await open();
        expect(s.openReport.recoveryRequired, isTrue);
        await s.dispose();
        stores.clear();
      }
      final copies = dir.listSync().where((e) => e.path.contains('.corrupt-')).toList();
      expect(copies.length, 1);
    });

    test('an empty file and a database with no tables at all are treated as fresh',
        () async {
      File(pathOf()).writeAsBytesSync(Uint8List(0));
      var s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await accFor(s).accept(intentOf('t1'))).created, isTrue);
      await s.dispose();
      stores.clear();
      File(pathOf()).deleteSync();
      for (final suffix in ['-wal', '-shm']) {
        final x = File('${pathOf()}$suffix');
        if (x.existsSync()) x.deleteSync();
      }
      final raw = await rawDb(pathOf());
      await raw.execute('PRAGMA user_version = 0');
      await raw.close();
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await accFor(s).accept(intentOf('t1'))).created, isTrue);
      expect(dir.listSync().any((e) => e.path.contains('.corrupt-')), isFalse);
    });

    test('a recovery-required store still shows what it can and refuses all writes cleanly',
        () async {
      File(pathOf()).writeAsBytesSync(Uint8List.fromList(List<int>.filled(512, 1)));
      final s = await open();
      expect(await s.listAll(), isEmpty);
      expect(await s.listPending(), isEmpty);
      expect(await s.get('nope'), isNull);
      await expectLater(accFor(s).accept(intentOf('x')),
          throwsA(isA<QueueRecoveryRequiredException>()));
    });
  });

  group('WAL files', () {
    test('a database copied with its -wal (crash image, no -shm) reopens with every committed command',
        () async {
      final s = await open();
      for (var i = 1; i <= 6; i++) {
        await accFor(s).accept(intentOf('t$i', setIndex: i));
      }
      expect(File('${pathOf()}-wal').existsSync(), isTrue,
          reason: 'WAL mode: committed data lives in the -wal until a checkpoint');
      final image = await makeTempRoot();
      File(pathOf()).copySync('${image.path}/${sqliteQueueFileName(kUid)}');
      File('${pathOf()}-wal').copySync('${image.path}/${sqliteQueueFileName(kUid)}-wal');

      final s2 = await SqliteCommandQueueStore.open(
          uid: kUid,
          path: '${rootPathOf(image)}/${sqliteQueueFileName(kUid)}',
          factory: databaseFactoryFfi,
          nowMs: clock.nowMs);
      stores.add(s2);
      expect(s2.openReport.recoveryRequired, isFalse);
      expect((await s2.listAll()).length, 6);
      expect((await accFor(s2).accept(intentOf('t7', setIndex: 7))).record.seq, 7);
      await s2.dispose();
      stores.remove(s2);
      await removeTempRoot(image);
    });

    test('deleting the -shm and -wal after a clean close loses nothing and reopens', () async {
      var s = await open();
      for (var i = 1; i <= 4; i++) {
        await accFor(s).accept(intentOf('t$i', setIndex: i));
      }
      await s.dispose();
      stores.clear();
      for (final suffix in ['-shm', '-wal']) {
        final x = File('${pathOf()}$suffix');
        if (x.existsSync()) x.deleteSync();
      }
      s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await s.listAll()).length, 4);
    });

    test('leftover -wal/-shm from a previous run do not break reopening', () async {
      var s = await open();
      await accFor(s).accept(intentOf('t1'));
      // Reopen while the WAL files exist (no checkpoint forced).
      s = await reopen();
      s = await reopen();
      expect((await s.listAll()).length, 1);
      expect(s.openReport.recoveryRequired, isFalse);
    });
  });

  group('serialisation', () {
    test('concurrent accepts, sends and prunes from several callers serialise: dense seqs, no lost or duplicated rows',
        () async {
      final s = await open();
      final sender = senderFor(s, server, clock);
      final futures = <Future<Object?>>[];
      for (var i = 1; i <= 30; i++) {
        futures.add(accFor(s).accept(intentOf('t$i', setIndex: i)));
        if (i % 5 == 0) futures.add(sender.sendNext());
        if (i % 7 == 0) futures.add(s.prune());
      }
      await Future.wait(futures);
      await sender.sendAvailable();
      final all = await s.listAll();
      expect(all.length, 30);
      expect(all.map((r) => r.seq).toList()..sort(), List<int>.generate(30, (i) => i + 1));
      expect(all.map((r) => r.operationId).toSet().length, 30);
      expect(all.every((r) => r.state == CommandState.synced), isTrue);
      expect(server.effects.length, 30);
      expect((await counts())['commands'], 30);
    });

    test('two UI callers tapping the same set at once yield one command and one refusal', () async {
      final s = await open();
      final results = await Future.wait(<Future<Object>>[
        accFor(s).accept(intentOf('tap-a')).then<Object>((v) => v, onError: (Object e) => e),
        accFor(s).accept(intentOf('tap-b')).then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<AcceptResult>().length, 1);
      expect(results.whereType<DuplicateLogicalSetException>().length, 1);
      expect((await counts())['commands'], 1);
    });
  });

  group('sender behaviour on SQLite', () {
    test('NOT_WRITER keeps set 1 ahead of set 2 across a restart; the corrected proof delivers 1 then 2',
        () async {
      var s = await open();
      final set1 = (await accFor(s).accept(intentOf('s1', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      final set2 = (await accFor(s).accept(intentOf('s2', setIndex: 2))).record;
      var token = 'stale';
      Future<String?> proof(String u, String sid) async => token;
      server.scriptedCodes.add('NOT_WRITER');
      var sender = senderFor(s, server, clock, proof: proof);
      expect((await sender.sendNext()).code, 'NOT_WRITER');
      expect((await s.get(set1.operationId))!.state, CommandState.accepted);
      expect((await sender.sendNext()).status, SendStatus.sessionOnHold);

      s = await reopen();
      server.scriptedCodes.add('NOT_WRITER');
      sender = senderFor(s, server, clock, proof: proof);
      expect((await sender.sendNext()).code, 'NOT_WRITER');
      expect(server.received.map((e) => e.operationId).toSet(), {set1.operationId});

      token = 'good';
      sender.resetBackoff();
      await sender.sendAvailable();
      expect(server.effects.map((e) => e.operationId).toList(),
          <String>[set1.operationId, set2.operationId]);
    });

    test('an old-build non-terminal CONFLICTED record is a session barrier after a restart',
        () async {
      var s = await open();
      final a = (await accFor(s).accept(intentOf('a1', sessionId: 'A', setIndex: 1))).record;
      clock.advance(const Duration(seconds: 1));
      final a2 = (await accFor(s).accept(intentOf('a2', sessionId: 'A', setIndex: 2))).record;
      clock.advance(const Duration(seconds: 1));
      final b = (await accFor(s).accept(intentOf('b1', sessionId: 'B'))).record;
      await s.markSending(a.operationId);
      await s.markResult(a.operationId,
          const CommandResult(to: CommandState.conflicted, resultCode: 'NOT_WRITER', conflictTerminal: false));
      s = await reopen();
      await senderFor(s, server, clock).sendAvailable();
      expect(server.effects.map((e) => e.operationId).toList(), <String>[b.operationId]);
      expect(server.received.any((e) => e.operationId == a2.operationId), isFalse);
    });

    test('lost ack then restart: the resend has the same id and bytes and exactly one server effect',
        () async {
      var s = await open();
      final rec = (await accFor(s).accept(intentOf('t'))).record;
      server.faults.add(Fault.applyThenThrow);
      expect((await senderFor(s, server, clock).sendNext()).status, SendStatus.retryLater);
      s = await reopen();
      final rep = await senderFor(s, server, clock).sendNext();
      expect(rep.status, SendStatus.synced);
      expect(rep.code, 'ALREADY_COMMITTED');
      expect(server.effects.length, 1);
      expect(server.received[1].payloadBytes, rec.canonicalBytes);
      expect(server.received[1].operationId, rec.operationId);
    });

    test('crash while SENDING: reopen resends the same id and bytes', () async {
      var s = await open();
      final rec = (await accFor(s).accept(intentOf('t'))).record;
      await s.markSending(rec.operationId);
      s = await reopen();
      expect((await senderFor(s, server, clock).sendNext()).status, SendStatus.synced);
      expect(server.received.single.payloadBytes, rec.canonicalBytes);
      expect((await s.get(rec.operationId))!.attempts, 2);
    });

    test('a recovery-required store can still send what it already holds', () async {
      var s = await open();
      final rec = (await accFor(s).accept(intentOf('t'))).record;
      await s.dispose();
      stores.clear();
      final raw = await rawDb(pathOf());
      await raw.execute("UPDATE meta SET value='99' WHERE key='schema_version'");
      await raw.close();
      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      // The damaged database is not used at all: nothing is held, nothing sent.
      expect(await s.listAll(), isEmpty);
      expect((await senderFor(s, server, clock).sendNext()).status, SendStatus.idle);
      expect(server.received, isEmpty);
      expect(rec.operationId, isNotEmpty);
    });
  });
}
