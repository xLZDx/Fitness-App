// Regression: sqflite on Android always creates an `android_metadata` table in
// every new database. The schema check used to see a non-empty table list,
// skipped CREATE TABLE and then failed with "no such table: meta". The
// sqflite_common_ffi used by the other tests does not create that table, so
// these tests plant it by hand to reproduce the Android file layout.
import 'dart:io';

import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/sqlite_command_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/offline_test_support.dart';

Future<Database> rawDb(String path) =>
    databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));

/// Adds the table exactly as the Android sqflite plugin does.
Future<void> plantAndroidMetadata(Database db) async {
  await db.execute('CREATE TABLE android_metadata(locale TEXT)');
  await db.insert('android_metadata', {'locale': 'en_US'});
}

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late TestClock clock;
  late IdMinter minter;
  StoreFactory? factory;
  final stores = <CommandQueueStore>[];

  String pathOf([String uid = kUid]) => '${rootPathOf(dir)}/${sqliteQueueFileName(uid)}';

  Future<SqliteCommandQueueStore> open({String uid = kUid}) async {
    factory = StoreFactory.sqlite(clock, dir);
    final s = await factory!.open(uid) as SqliteCommandQueueStore;
    stores.add(s);
    return s;
  }

  Future<SqliteCommandQueueStore> reopen({String uid = kUid}) async {
    final s = await factory!.open(uid) as SqliteCommandQueueStore;
    stores.add(s);
    return s;
  }

  Future<void> closeAll() async {
    for (final s in stores) {
      try {
        await s.dispose();
      } catch (_) {}
    }
    stores.clear();
  }

  CompleteSetAcceptor accFor(CommandQueueStore s) => acceptorFor(s, clock, minter: minter);

  Future<Set<Object?>> tableNames() async {
    final db = await rawDb(pathOf());
    try {
      return (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((e) => e['name'])
          .toSet();
    } finally {
      await db.close();
    }
  }

  setUp(() async {
    dir = await makeTempRoot();
    clock = TestClock();
    minter = IdMinter();
    factory = null;
  });
  tearDown(() async {
    await closeAll();
    await removeTempRoot(dir);
  });

  group('android_metadata is not a foreign table', () {
    test('a file holding ONLY android_metadata opens as a normal store, creates the schema, accepts and survives a restart',
        () async {
      final raw = await rawDb(pathOf());
      await plantAndroidMetadata(raw);
      await raw.close();

      var s = await open();
      expect(s.openReport.recoveryRequired, isFalse);
      expect(s.openReport.recoveryRequiredReason, isNull);
      final r = await accFor(s).accept(intentOf('t1'));
      expect(r.created, isTrue);
      expect(r.record.seq, 1);

      expect(await tableNames(),
          containsAll(<String>['android_metadata', 'meta', 'seq_counters', 'logical_sets', 'commands']));

      s = await (() async {
        await s.dispose();
        stores.clear();
        return reopen();
      })();
      expect(s.openReport.recoveryRequired, isFalse);
      final pending = await s.listPending();
      expect(pending.length, 1);
      expect(pending.single.operationId, r.record.operationId);
      expect(pending.single.canonicalBytes, r.record.canonicalBytes);

      // The android_metadata row is left alone.
      final db = await rawDb(pathOf());
      try {
        expect(await db.rawQuery('SELECT locale FROM android_metadata'),
            [<String, Object?>{'locale': 'en_US'}]);
      } finally {
        await db.close();
      }
      expect(dir.listSync().any((e) => e.path.contains('.corrupt-')), isFalse,
          reason: 'nothing was treated as corruption');
    });

    test('android_metadata plus a real foreign table still requires recovery; the file is untouched and a copy is kept',
        () async {
      final raw = await rawDb(pathOf());
      await plantAndroidMetadata(raw);
      await raw.execute('CREATE TABLE foreign_thing(id INTEGER PRIMARY KEY, v TEXT)');
      await raw.insert('foreign_thing', {'v': 'keep me'});
      await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await raw.close();
      final before = File(pathOf()).readAsBytesSync();

      final s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      expect(s.openReport.recoveryRequiredReason, isNotNull);
      await expectLater(accFor(s).accept(intentOf('x')),
          throwsA(isA<QueueRecoveryRequiredException>()));
      expect(await s.listAll(), isEmpty);
      // Opening switches the header to WAL mode, so bytes may differ from
      // `before`; the content must not.
      expect(File(pathOf()).lengthSync(), greaterThanOrEqualTo(before.length));
      expect(File('${pathOf()}.corrupt-1').existsSync(), isTrue);
      final chk = await rawDb(pathOf());
      try {
        expect(await chk.rawQuery('SELECT v FROM foreign_thing'),
            [<String, Object?>{'v': 'keep me'}]);
      } finally {
        await chk.close();
      }
      expect(await tableNames(), isNot(contains('meta')),
          reason: 'no schema is created inside a foreign database');
    });

    test('an existing valid store with android_metadata present reopens with its commands intact',
        () async {
      var s = await open();
      final a = (await accFor(s).accept(intentOf('t1', setIndex: 1))).record;
      final b = (await accFor(s).accept(intentOf('t2', setIndex: 2))).record;
      await s.dispose();
      stores.clear();

      final raw = await rawDb(pathOf());
      await plantAndroidMetadata(raw);
      await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await raw.close();

      s = await reopen();
      expect(s.openReport.recoveryRequired, isFalse);
      expect((await s.listPending()).map((r) => r.operationId).toSet(),
          {a.operationId, b.operationId});
      final c = (await accFor(s).accept(intentOf('t3', setIndex: 3))).record;
      expect(c.seq, 3, reason: 'sequence continues; the schema was not recreated');
      expect(dir.listSync().any((e) => e.path.contains('.corrupt-')), isFalse);
    });

    test('android_metadata with a damaged store (required table dropped) is still recovery-required',
        () async {
      var s = await open();
      await accFor(s).accept(intentOf('t1'));
      await s.dispose();
      stores.clear();

      final raw = await rawDb(pathOf());
      await plantAndroidMetadata(raw);
      await raw.execute('DROP TABLE logical_sets');
      await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await raw.close();

      s = await open();
      expect(s.openReport.recoveryRequired, isTrue);
      await expectLater(accFor(s).accept(intentOf('x')),
          throwsA(isA<QueueRecoveryRequiredException>()));
    });
  });
}
