/// Durable, uid-scoped file implementation of [CommandQueueStore].
///
/// Layout under `<root>/<scope>/` where `scope` is derived from the uid by a
/// hash (the raw uid is never a path segment):
///   - `records/<hex(operationId)>.json`  one file per record
///   - `seq.json`                         the seq counters (never pruned)
///   - `logical_sets.json`                the logical-set markers (never pruned)
///   - `seq.json.bak`, `logical_sets.json.bak`  validated duplicates
/// Every write is temp file + flush + rename (see [QueueFileOps]).
///
/// The two metadata files carry the information that must outlive pruned
/// records (sequence high-water marks, logical-set identity). Each is written
/// as one JSON line plus a `#sha256:<hex>` checksum line, backup first and
/// primary second, so the backup is never older than the primary. At open a
/// corrupt or missing file is recovered from its validated twin; a corrupt
/// file is preserved as `<name>.corrupt-<n>` before it is replaced. If neither
/// copy validates the store fails closed ([QueueRecoveryRequiredException] on
/// append) instead of rebuilding from surviving records.
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
    this.recoveryRequiredReason,
  });

  final int loaded;
  final int recoveredSending;
  final int removedTempFiles;

  /// Record files that could not be parsed. They are left untouched on disk
  /// (never deleted) and are not part of the in-memory view. The status counts
  /// them as "could not sync".
  final List<String> unreadableFiles;

  /// `seq.json` was corrupt or missing and was restored from its backup.
  final bool seqFileRepaired;

  /// `logical_sets.json` was corrupt or missing and was restored from its
  /// backup.
  final bool markersFileRepaired;

  /// Non-null when the metadata could not be completely recovered: the store
  /// refuses appends and pruning. Corrupt originals are left in place.
  final String? recoveryRequiredReason;

  bool get recoveryRequired => recoveryRequiredReason != null;
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
  static const String _backupSuffix = '.bak';
  static const String _corruptInfix = '.corrupt-';
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
    final problems = <String>[];
    final seqMeta = await _loadMeta<Map<String, int>>(
      path: _seqPath,
      decode: (doc) => <String, int>{
        for (final e in (doc['counters'] as Map).entries)
          e.key as String: e.value as int,
      },
      problems: problems,
    );
    final markerMeta = await _loadMeta<List<LogicalSetMarker>>(
      path: _markersPath,
      decode: (doc) => <LogicalSetMarker>[
        for (final e in (doc['sets'] as Map).entries)
          LogicalSetMarker(
            logicalSetId: e.key as String,
            operationId: (e.value as Map)['operationId'] as String,
            acceptedAtLocalWallMs: (e.value as Map)['acceptedAt'] as int,
          ),
      ],
      problems: problems,
    );
    seed(records, seqMeta.value ?? <String, int>{},
        markerMeta.value ?? const <LogicalSetMarker>[]);
    if (problems.isNotEmpty) {
      // Fail closed: nothing is rewritten and the corrupt originals stay on
      // disk. Appends and pruning are refused; existing records stay readable.
      recoveryRequiredReason = problems.join('; ');
    } else if (markersNeedPersist) {
      await persistLogicalSetMarkers(markersView);
    }
    final recovered = await recoverInterrupted();
    _report = QueueOpenReport(
      loaded: records.where((r) => r.uid == uid).length,
      recoveredSending: recovered,
      removedTempFiles: removedTmp,
      unreadableFiles: unreadable,
      seqFileRepaired: seqMeta.restored,
      markersFileRepaired: markerMeta.restored,
      recoveryRequiredReason: recoveryRequiredReason,
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
      _writeMeta(_seqPath, {'format': 1, 'counters': counters});

  @override
  Future<void> persistLogicalSetMarkers(
          Map<String, LogicalSetMarker> markers) =>
      _writeMeta(_markersPath, {
        'format': 1,
        'sets': {
          for (final e in markers.entries)
            e.key: {
              'operationId': e.value.operationId,
              'acceptedAt': e.value.acceptedAtLocalWallMs,
            },
        },
      });

  // ---- redundant metadata files -------------------------------------------

  static const String _checkPrefix = '#sha256:';

  static Uint8List _frame(Map<String, Object?> doc) {
    final body = jsonEncode(doc);
    final sum = crypto.sha256.convert(utf8.encode(body));
    return Uint8List.fromList(utf8.encode('$body\n$_checkPrefix$sum\n'));
  }

  /// Backup first, primary second: if the process dies between the two, the
  /// backup is the newer (or equal) copy, never the older one.
  Future<void> _writeMeta(String path, Map<String, Object?> doc) async {
    final bytes = _frame(doc);
    final bak = '$path$_backupSuffix';
    final previous = await ops.read(bak);
    await ops.writeAtomic(bak, bytes);
    try {
      await ops.writeAtomic(path, bytes);
    } catch (_) {
      // The write was not acknowledged: put the previous backup back so a
      // restart cannot restore an unacknowledged state from it.
      try {
        if (previous == null) {
          await ops.delete(bak);
        } else {
          await ops.writeAtomic(bak, previous);
        }
      } catch (_) {
        // Residual: the backup stays one write ahead; open prefers a valid
        // primary, and uses the backup only if the primary is lost.
      }
      rethrow;
    }
  }

  /// Parses a framed file. A file without a checksum line is a format-1 file
  /// written before the redundancy existed and is accepted if it parses. Null
  /// when the content is corrupt.
  static Map<String, Object?>? _parseFramed(Uint8List raw) {
    try {
      final text = utf8.decode(raw).trimRight();
      final idx = text.lastIndexOf('\n$_checkPrefix');
      final String body;
      if (idx < 0) {
        body = text;
      } else {
        body = text.substring(0, idx);
        final claimed = text.substring(idx + 1 + _checkPrefix.length).trim();
        if (crypto.sha256.convert(utf8.encode(body)).toString() != claimed) {
          return null;
        }
      }
      return Map<String, Object?>.from(jsonDecode(body) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Reads [path] and its backup. Both missing means a fresh store (value
  /// null). Otherwise a validated copy is returned (and the other copy is
  /// healed, a corrupt file being preserved first) or the problem is added to
  /// [problems] and nothing is touched (fail closed).
  Future<_Meta<T>> _loadMeta<T>({
    required String path,
    required T Function(Map<String, Object?> doc) decode,
    required List<String> problems,
  }) async {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final bakPath = '$path$_backupSuffix';

    Future<(Uint8List?, T?)> read(String p) async {
      final raw = await ops.read(p);
      if (raw == null) return (null, null);
      final doc = _parseFramed(raw);
      if (doc == null) return (raw, null);
      try {
        return (raw, decode(doc));
      } catch (_) {
        return (raw, null);
      }
    }

    final (pRaw, pVal) = await read(path);
    final (bRaw, bVal) = await read(bakPath);
    if (pRaw == null && bRaw == null) return _Meta<T>(null, false);

    if (pVal != null && bVal != null) {
      // The primary is authoritative. The backup may be one write ahead (the
      // primary write after it failed or the process died); that write was not
      // acknowledged, so its extra content is ignored.
      return _Meta<T>(pVal, false);
    }
    if (pVal != null) {
      // Backup missing (older store) or corrupt: re-create it from the primary.
      if (bRaw != null) await _preserveCorrupt('$name$_backupSuffix', bRaw);
      await ops.writeAtomic(bakPath, pRaw!);
      return _Meta<T>(pVal, false);
    }
    if (bVal != null) {
      // Primary corrupt or missing: keep the evidence, restore from the backup.
      if (pRaw != null) await _preserveCorrupt(name, pRaw);
      await ops.writeAtomic(path, bRaw!);
      return _Meta<T>(bVal, true);
    }
    problems.add('$name and its backup are unreadable');
    return _Meta<T>(null, false);
  }

  /// Copies corrupt bytes to `<name>.corrupt-<n>` (n = highest existing + 1)
  /// beside the original before the original is replaced.
  Future<void> _preserveCorrupt(String name, Uint8List raw) async {
    var next = 1;
    for (final f in await ops.listFileNames(scopeDir)) {
      final i = f.indexOf(_corruptInfix);
      if (i < 0) continue;
      final n = int.tryParse(f.substring(i + _corruptInfix.length));
      if (n != null && n >= next) next = n + 1;
    }
    await ops.writeAtomic('$scopeDir/$name$_corruptInfix$next', raw);
  }

  @override
  Future<void> removeRecordFromDisk(String operationId) =>
      ops.delete(_recordPath(operationId));
}

class _Meta<T> {
  _Meta(this.value, this.restored);

  /// Null for a fresh store (no file) or when nothing validated.
  final T? value;
  final bool restored;
}
