/// Durable, uid-scoped file implementation of [CommandQueueStore].
///
/// Layout under `<root>/<scope>/` where `scope` is derived from the uid by a
/// hash (the raw uid is never a path segment):
///   - `records/<hex(operationId)>.json`  one file per record
///   - `seq.json`                         the seq counters (never pruned)
/// Every write is temp file + flush + rename (see [QueueFileOps]).
///
/// Known limits (V0): one store instance per uid per process is assumed (no
/// cross-process lock); the other local tables of section 3.1 (set_context,
/// effective_set, intent_keys, session_sender_state, observed_generation) do
/// not exist yet.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'command_queue_store.dart';
import 'command_queue_store_base.dart';
import 'command_record.dart';
import 'queue_file_ops.dart';

/// Directory name for [uid] under the queue root. One-way, so another uid
/// never maps to the same directory and the uid is not written to disk paths.
String queueScopeDirName(String uid) {
  final h = crypto.sha256.convert(utf8.encode('fitnessup-offline-queue|$uid'));
  return 'u_${h.toString().substring(0, 32)}';
}

String _hex(String s) {
  final b = StringBuffer();
  for (final byte in utf8.encode(s)) {
    b.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// What `open` found on disk; for diagnostics and tests.
class QueueOpenReport {
  const QueueOpenReport({
    required this.loaded,
    required this.recoveredSending,
    required this.removedTempFiles,
    required this.unreadableFiles,
    this.seqFileRepaired = false,
    this.markersFileRepaired = false,
  });

  final int loaded;
  final int recoveredSending;
  final int removedTempFiles;

  /// Record files that could not be parsed. They are left untouched on disk
  /// (never deleted) and are not part of the in-memory view. The status counts
  /// them as "could not sync".
  final List<String> unreadableFiles;

  /// `seq.json` existed but was unreadable; counters were rebuilt from the
  /// surviving records (a seq of a pruned record could be reused).
  final bool seqFileRepaired;

  /// `logical_sets.json` existed but was unreadable; markers were rebuilt from
  /// the surviving records (markers of pruned stubs are lost).
  final bool markersFileRepaired;
}

class FileCommandQueueStore extends BaseCommandQueueStore
    implements HasUnreadableRecords {
  FileCommandQueueStore._({
    required super.uid,
    required super.nowMs,
    required this.scopeDir,
    required this.ops,
  });

  final String scopeDir;
  final QueueFileOps ops;

  /// Scope directories opened by this process. A second concurrent instance
  /// for the same scope would race on temp files and SENDING recovery.
  static final Set<String> _openScopes = <String>{};

  late QueueOpenReport _report;
  QueueOpenReport get openReport => _report;

  @override
  int get unreadableRecordCount => _report.unreadableFiles.length;

  @override
  Future<void> dispose() async {
    await super.dispose();
    _openScopes.remove(scopeDir);
  }

  String get _recordsDir => '$scopeDir/records';
  String get _seqPath => '$scopeDir/seq.json';
  String get _markersPath => '$scopeDir/logical_sets.json';
  String _recordPath(String operationId) =>
      '$_recordsDir/${_hex(operationId)}.json';

  /// Opens (and recovers) the store of [uid] under [rootDir].
  ///
  /// Recovery: leftover temp files are removed (they are incomplete writes,
  /// the real file is intact); a record found in SENDING returns to
  /// UNKNOWN_EFFECT (T10).
  static Future<FileCommandQueueStore> open({
    required String uid,
    required String rootDir,
    QueueFileOps ops = const IoQueueFileOps(),
    int Function()? nowMs,
  }) async {
    final scopeDir = '$rootDir/${queueScopeDirName(uid)}';
    if (!_openScopes.add(scopeDir)) {
      throw StateError(
          'a command queue store is already open for this uid and root in this process; dispose it first');
    }
    try {
      final store = FileCommandQueueStore._(
        uid: uid,
        nowMs: nowMs,
        scopeDir: scopeDir,
        ops: ops,
      );
      await store._load();
      return store;
    } catch (_) {
      _openScopes.remove(scopeDir);
      rethrow;
    }
  }

  Future<void> _load() async {
    await ops.ensureDir(_recordsDir);
    var removedTmp = 0;
    final unreadable = <String>[];
    final records = <CommandRecord>[];
    for (final name in await ops.listFileNames(_recordsDir)) {
      final path = '$_recordsDir/$name';
      if (name.endsWith(IoQueueFileOps.tempSuffix)) {
        await ops.delete(path);
        removedTmp++;
        continue;
      }
      if (!name.endsWith('.json')) continue;
      try {
        final bytes = await ops.read(path);
        if (bytes == null) continue;
        final doc = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        records.add(CommandRecord.fromJson(
            Map<String, Object?>.from(doc['record'] as Map)));
      } catch (_) {
        unreadable.add(name);
      }
    }
    // Leftover temp files of seq.json / logical_sets.json (unique names).
    for (final name in await ops.listFileNames(scopeDir)) {
      if (name.endsWith(IoQueueFileOps.tempSuffix)) {
        await ops.delete('$scopeDir/$name');
        removedTmp++;
      }
    }
    var seqRepaired = false;
    var markersRepaired = false;
    final counters = <String, int>{};
    try {
      final bytes = await ops.read(_seqPath);
      if (bytes != null) {
        final doc = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        for (final e in (doc['counters'] as Map).entries) {
          counters[e.key as String] = e.value as int;
        }
      }
    } catch (_) {
      // An unreadable counter file is repaired by seed(): every counter is
      // raised above the highest seq of a surviving record. Recorded in the
      // open report.
      seqRepaired = true;
    }
    final markers = <LogicalSetMarker>[];
    try {
      final bytes = await ops.read(_markersPath);
      if (bytes != null) {
        final doc = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        for (final e in (doc['sets'] as Map).entries) {
          final v = Map<String, Object?>.from(e.value as Map);
          markers.add(LogicalSetMarker(
            logicalSetId: e.key as String,
            operationId: v['operationId'] as String,
            acceptedAtLocalWallMs: v['acceptedAt'] as int,
          ));
        }
      }
    } catch (_) {
      // Unreadable marker table: seed() rebuilds markers from the surviving
      // records. Markers of already pruned stubs are lost in that case.
      markersRepaired = true;
    }
    seed(records, counters, markers);
    if (markersNeedPersist || markersRepaired) {
      await persistLogicalSetMarkers(markersView);
    }
    final recovered = await recoverInterrupted();
    _report = QueueOpenReport(
      loaded: records.where((r) => r.uid == uid).length,
      recoveredSending: recovered,
      removedTempFiles: removedTmp,
      unreadableFiles: unreadable,
      seqFileRepaired: seqRepaired,
      markersFileRepaired: markersRepaired,
    );
  }

  @override
  Future<void> persistRecord(CommandRecord record) => ops.writeAtomic(
        _recordPath(record.operationId),
        Uint8List.fromList(
            utf8.encode(jsonEncode({'format': 1, 'record': record.toJson()}))),
      );

  @override
  Future<void> persistSeqCounters(Map<String, int> counters) =>
      ops.writeAtomic(
        _seqPath,
        Uint8List.fromList(
            utf8.encode(jsonEncode({'format': 1, 'counters': counters}))),
      );

  @override
  Future<void> persistLogicalSetMarkers(
          Map<String, LogicalSetMarker> markers) =>
      ops.writeAtomic(
        _markersPath,
        Uint8List.fromList(utf8.encode(jsonEncode({
          'format': 1,
          'sets': {
            for (final e in markers.entries)
              e.key: {
                'operationId': e.value.operationId,
                'acceptedAt': e.value.acceptedAtLocalWallMs,
              },
          },
        }))),
      );

  @override
  Future<void> removeRecordFromDisk(String operationId) =>
      ops.delete(_recordPath(operationId));
}
