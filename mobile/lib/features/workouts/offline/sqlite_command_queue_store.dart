/// Transactional SQLite implementation of [CommandQueueStore] (package
/// sqflite; WAL, `synchronous=FULL`, `foreign_keys=ON`). One database file per
/// uid (see [sqliteQueueFileName]); the raw uid is never written to a path.
///
/// Schema version 1:
///   - `meta(key, value)`            `schema_version`, `created`, `scope`
///   - `seq_counters(seq_key, next_seq)`  sequence high-water marks, never pruned
///   - `logical_sets(logical_set_id PRIMARY KEY, operation_id, accepted_at)`
///       the durable uniqueness guarantee of a logical set; rows are NEVER
///       deleted (not even by [prune]).
///   - `commands(operation_id PRIMARY KEY, intent_key UNIQUE, ... record_json)`
///
/// Accept is ONE transaction (command row + logical-set row + counter): all or
/// nothing, so there is no two-slot metadata, no completion marker and no
/// rollback code. A failed transaction changes nothing, in memory or on disk.
///
/// Open: PRAGMAs are applied AND read back (a mismatch fails closed with a
/// [QueueException]); an existing database must pass `quick_check` and the
/// schema/created/scope checks. Otherwise the file is left in place, copied to
/// `<name>.corrupt-<n>`, and the store opens in recovery-required mode
/// ([QueueRecoveryRequiredException] on accept; prune is a no-op). A fresh
/// database is created only when no database file existed, or the file holds
/// no table at all (a crash during the very first creation).
///
/// Known limits: one store instance per database file per process; the other
/// local tables of protocol section 3.1 do not exist yet.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'command_queue_store.dart';
import 'command_queue_store_base.dart';
import 'command_record.dart';
import 'file_command_queue_store.dart' show QueueOpenReport, queueScopeDirName;

const int kSqliteQueueSchemaVersion = 1;

/// File name of the database of [uid] inside the app support directory.
String sqliteQueueFileName(String uid) =>
    'workout_command_queue_${queueScopeDirName(uid)}.db';

class _OpenProblem implements Exception {
  _OpenProblem(this.reason);
  final String reason;
}

/// A PRAGMA did not take effect; fail closed (not a corruption).
class _PragmaProblem implements Exception {
  _PragmaProblem(this.what);
  final String what;
}

class SqliteCommandQueueStore extends BaseCommandQueueStore
    implements HasUnreadableRecords {
  SqliteCommandQueueStore._({
    required super.uid,
    required super.nowMs,
    required this.path,
    required Database? db,
    required int Function() clock,
  })  : _db = db,
        _clock = clock;

  final String path;
  final Database? _db;
  final int Function() _clock;

  static final Set<String> _openPaths = <String>{};

  late QueueOpenReport _report;
  QueueOpenReport get openReport => _report;

  final List<String> _unreadable = <String>[];

  @override
  int get unreadableRecordCount => _unreadable.length;

  /// Opens (and recovers) the database at [path]. [factory] is the seam for
  /// tests (sqflite_common_ffi, fault injection); it defaults to sqflite's.
  /// [path] may be [inMemoryDatabasePath].
  static Future<SqliteCommandQueueStore> open({
    required String uid,
    required String path,
    DatabaseFactory? factory,
    int Function()? nowMs,
  }) async {
    final inMemory = path == inMemoryDatabasePath;
    if (!inMemory && !_openPaths.add(path)) {
      throw StateError(
          'a command queue store is already open for this database in this process; dispose it first');
    }
    try {
      final clock = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);
      final f = factory ?? databaseFactory;
      final existed = !inMemory && File(path).existsSync();
      Database? db;
      String? problem;
      try {
        db = await f.openDatabase(path,
            options: OpenDatabaseOptions(singleInstance: !inMemory));
        await _applyPragmas(db, inMemory);
        problem = await _checkOrCreateSchema(db, uid, clock);
      } on _PragmaProblem catch (e) {
        await _closeQuietly(db);
        throw QueueException('SQLite PRAGMA not applied: ${e.what}');
      } on _OpenProblem catch (e) {
        problem = e.reason;
      } catch (e) {
        // Opening a database that did not exist must not be masked as
        // corruption: surface the real error.
        if (!existed) {
          await _closeQuietly(db);
          rethrow;
        }
        problem = 'database unreadable: $e';
      }
      if (problem != null) {
        await _closeQuietly(db);
        db = null;
        if (existed) await _preserveCorrupt(path);
      }
      final store = SqliteCommandQueueStore._(
          uid: uid, nowMs: nowMs, path: path, db: db, clock: clock);
      await store._load(problem);
      return store;
    } catch (_) {
      if (!inMemory) _openPaths.remove(path);
      rethrow;
    }
  }

  static Future<void> _closeQuietly(Database? db) async {
    try {
      await db?.close();
    } catch (_) {}
  }

  static Future<void> _applyPragmas(Database db, bool inMemory) async {
    final jm = await db.rawQuery('PRAGMA journal_mode=WAL');
    final mode =
        jm.isEmpty ? null : jm.first.values.first?.toString().toLowerCase();
    if (mode != 'wal' && !(inMemory && mode == 'memory')) {
      throw _PragmaProblem('journal_mode=$mode');
    }
    await db.rawQuery('PRAGMA synchronous=FULL');
    final sync = await db.rawQuery('PRAGMA synchronous');
    final syncV = sync.isEmpty ? null : sync.first.values.first;
    if (syncV != 2) throw _PragmaProblem('synchronous=$syncV');
    await db.rawQuery('PRAGMA foreign_keys=ON');
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    final fkV = fk.isEmpty ? null : fk.first.values.first;
    if (fkV != 1) throw _PragmaProblem('foreign_keys=$fkV');
  }

  /// Returns null when the database is usable (created if it held no table);
  /// throws [_OpenProblem] when it must not be used.
  static Future<String?> _checkOrCreateSchema(
      Database db, String uid, int Function() clock) async {
    final qc = await db.rawQuery('PRAGMA quick_check');
    if (qc.isEmpty || qc.first.values.first != 'ok') {
      throw _OpenProblem('integrity check failed');
    }
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
        "AND name != 'android_metadata'");
    final scope = queueScopeDirName(uid);
    if (tables.isEmpty) {
      await db.transaction((txn) async {
        await txn.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL) WITHOUT ROWID');
        await txn.execute(
            'CREATE TABLE seq_counters(seq_key TEXT PRIMARY KEY NOT NULL, next_seq INTEGER NOT NULL) WITHOUT ROWID');
        await txn.execute(
            'CREATE TABLE logical_sets(logical_set_id TEXT PRIMARY KEY NOT NULL, operation_id TEXT NOT NULL, accepted_at INTEGER NOT NULL) WITHOUT ROWID');
        await txn.execute('CREATE TABLE commands('
            'operation_id TEXT PRIMARY KEY NOT NULL, '
            'uid TEXT NOT NULL, '
            'session_id TEXT, origin_device_install_id TEXT, exercise_id TEXT, '
            'logical_set_id TEXT, '
            'intent_key TEXT UNIQUE, '
            'seq INTEGER, '
            'state TEXT NOT NULL, '
            'attempts INTEGER, '
            'accepted_at_local_wall_ms INTEGER, '
            'updated_at_ms INTEGER NOT NULL, '
            'record_json TEXT NOT NULL)');
        await txn.execute('CREATE INDEX commands_state ON commands(state)');
        await txn.insert('meta',
            {'key': 'schema_version', 'value': '$kSqliteQueueSchemaVersion'});
        await txn.insert('meta', {'key': 'scope', 'value': scope});
        await txn.insert(
            'meta', {'key': 'created', 'value': '${clock()}'});
      });
      return null;
    }
    final meta = <String, String>{
      for (final r in await db.rawQuery('SELECT key, value FROM meta'))
        r['key']! as String: r['value']! as String,
    };
    if (meta['created'] == null) throw _OpenProblem('created marker missing');
    if (meta['schema_version'] != '$kSqliteQueueSchemaVersion') {
      throw _OpenProblem(
          'unsupported schema version ${meta['schema_version']}');
    }
    if (meta['scope'] != scope) {
      throw _OpenProblem('database belongs to another account');
    }
    for (final t in const ['seq_counters', 'logical_sets', 'commands']) {
      if (!tables.any((r) => r['name'] == t)) {
        throw _OpenProblem('table $t missing');
      }
    }
    return null;
  }

  /// Copies the unusable database (and its WAL) to `<name>.corrupt-<n>`; the
  /// original stays in place so nothing is ever replaced by an empty file.
  static Future<void> _preserveCorrupt(String path) async {
    try {
      final file = File(path);
      final dir = file.parent;
      final base = file.uri.pathSegments.last;
      var next = 1;
      var sameLength = false;
      final len = file.lengthSync();
      for (final e in dir.listSync()) {
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('$base.corrupt-') || name.endsWith('-wal')) {
          continue;
        }
        final n = int.tryParse(name.substring(base.length + 9));
        if (n != null && n >= next) next = n + 1;
        if (n != null && e is File && e.lengthSync() == len) sameLength = true;
      }
      if (sameLength) return;
      await file.copy('$path.corrupt-$next');
      final wal = File('$path-wal');
      if (wal.existsSync()) await wal.copy('$path.corrupt-$next-wal');
    } catch (_) {
      // Best effort; the original is untouched either way.
    }
  }

  Future<void> _load(String? problem) async {
    final records = <CommandRecord>[];
    final counters = <String, int>{};
    final markers = <LogicalSetMarker>[];
    final db = _db;
    if (problem == null && db != null) {
      for (final r in await db.rawQuery(
          'SELECT operation_id, record_json FROM commands')) {
        try {
          records.add(CommandRecord.fromJson(Map<String, Object?>.from(
              jsonDecode(r['record_json']! as String) as Map)));
        } catch (_) {
          _unreadable.add(r['operation_id']! as String);
        }
      }
      for (final r in await db.rawQuery('SELECT * FROM seq_counters')) {
        counters[r['seq_key']! as String] = r['next_seq']! as int;
      }
      for (final r in await db.rawQuery('SELECT * FROM logical_sets')) {
        markers.add(LogicalSetMarker(
          logicalSetId: r['logical_set_id']! as String,
          operationId: r['operation_id']! as String,
          acceptedAtLocalWallMs: r['accepted_at']! as int,
        ));
      }
    }
    seed(records, counters, markers);
    if (problem != null) {
      recoveryRequiredReason = problem;
    } else if (markersNeedPersist) {
      await persistMetadata(seqCountersView, markersView);
    }
    final recovered = problem == null ? await recoverInterrupted() : 0;
    _report = QueueOpenReport(
      loaded: records.where((r) => r.uid == uid).length,
      recoveredSending: recovered,
      removedTempFiles: 0,
      unreadableFiles: List<String>.of(_unreadable),
      recoveryRequiredReason: recoveryRequiredReason,
    );
  }

  Database get _live {
    final db = _db;
    if (db == null) {
      throw QueueRecoveryRequiredException(
          recoveryRequiredReason ?? 'database is not open');
    }
    return db;
  }

  Map<String, Object?> _row(CommandRecord r) => <String, Object?>{
        'operation_id': r.operationId,
        'uid': r.uid,
        'session_id': r.sessionId,
        'origin_device_install_id': r.originDeviceInstallId,
        'exercise_id': r.exerciseId,
        'logical_set_id': r.logicalSetId,
        'intent_key': r.intentKey,
        'seq': r.seq,
        'state': r.state.wire,
        'attempts': r.attempts,
        'accepted_at_local_wall_ms': r.acceptedAtLocalWallMs,
        'updated_at_ms': _clock(),
        'record_json': jsonEncode(r.toJson()),
      };

  @override
  Future<void> persistRecord(CommandRecord record) => _live.insert(
      'commands', _row(record),
      conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> removeRecordFromDisk(String operationId) async {
    await _live
        .delete('commands', where: 'operation_id = ?', whereArgs: [operationId]);
  }

  /// Idempotent upsert of counters and markers in one transaction. Used by
  /// re-adoption and by the open-time heal; the hot paths use [commitAccept].
  @override
  Future<void> persistMetadata(
      Map<String, int> counters, Map<String, LogicalSetMarker> markers) {
    return _live.transaction((txn) async {
      for (final e in counters.entries) {
        await txn.insert('seq_counters',
            {'seq_key': e.key, 'next_seq': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in markers.values) {
        await txn.insert(
            'logical_sets',
            {
              'logical_set_id': m.logicalSetId,
              'operation_id': m.operationId,
              'accepted_at': m.acceptedAtLocalWallMs,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// The single accept transaction: command row, logical-set row and counter.
  @override
  Future<void> commitAccept(CommandRecord record, String seqKey, int nextSeq,
      LogicalSetMarker marker) {
    return _live.transaction((txn) async {
      await txn.insert('commands', _row(record),
          conflictAlgorithm: ConflictAlgorithm.abort);
      await txn.insert(
          'logical_sets',
          {
            'logical_set_id': marker.logicalSetId,
            'operation_id': marker.operationId,
            'accepted_at': marker.acceptedAtLocalWallMs,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);
      await txn.insert('seq_counters',
          {'seq_key': seqKey, 'next_seq': nextSeq},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Prune removes only the command row; `logical_sets` and `seq_counters`
  /// were committed with the accept and are never touched here.
  @override
  Future<void> commitPrune(CommandRecord record) =>
      removeRecordFromDisk(record.operationId);

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _closeQuietly(_db);
    if (path != inMemoryDatabasePath) _openPaths.remove(path);
  }
}
