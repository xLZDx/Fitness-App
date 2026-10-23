/// Durable, uid-scoped file implementation of [CommandQueueStore].
///
/// Layout under `<root>/<scope>/` where `scope` is derived from the uid by a
/// hash (the raw uid is never a path segment):
///   - `records/<hex(operationId)>.json`  one file per record
///   - `meta.a.json`, `meta.b.json`       two slots of ONE metadata document
///   - `store.init`                       written once the first slot exists
/// Every write is temp file + flush + rename (see [QueueFileOps]).
///
/// The metadata document `{format:2, gen, seq:{...}, logicalSets:{...}}` holds
/// the information that must outlive pruned records (sequence high-water marks
/// and logical-set identity markers) and is never pruned. It is followed by a
/// `#sha256:<hex>` line over the body. A write goes to the slot that does NOT
/// hold the highest valid `gen`, with `gen + 1`; the commit point is the
/// successful rename, so a failed write changes neither slot and nothing that
/// was not acknowledged can ever be promoted. No rollback of metadata exists.
///
/// Load takes the valid slot with the highest `gen`. A corrupt slot beside a
/// valid one is preserved as `<slot>.corrupt-<n>` and later overwritten by a
/// normal write. If `store.init` exists but no slot validates, or a slot is
/// corrupt and none validates, the store fails closed
/// ([QueueRecoveryRequiredException] on append and prune) with the originals
/// untouched. A store without `store.init` and without any slot file is fresh
/// (record files of an older in-development build are used to seed it).
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

  /// A corrupt metadata slot was found beside a valid one and was preserved as
  /// `.corrupt-<n>`. Seq counters and markers share one document, so this and
  /// [markersFileRepaired] are always equal.
  final bool seqFileRepaired;

  /// See [seqFileRepaired].
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

  static const String _corruptInfix = '.corrupt-';
  static const String _checkPrefix = '#sha256:';

  String get _recordsDir => '$scopeDir/records';
  String get _initPath => '$scopeDir/store.init';
  String _slotName(String slot) => 'meta.$slot.json';
  String _slotPath(String slot) => '$scopeDir/${_slotName(slot)}';
  String _recordPath(String operationId) =>
      '$_recordsDir/${_hex(operationId)}.json';

  /// Generation and slot of the newest valid metadata document; slot null
  /// until the first document was written.
  int _gen = 0;
  String? _activeSlot;

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
    // Leftover temp files of the metadata slots (unique names).
    for (final name in await ops.listFileNames(scopeDir)) {
      if (name.endsWith(IoQueueFileOps.tempSuffix)) {
        await ops.delete('$scopeDir/$name');
        removedTmp++;
      }
    }

    final initExists = await ops.read(_initPath) != null;
    final a = await _readSlot('a');
    final b = await _readSlot('b');
    _Slot? best;
    for (final s in <_Slot>[a, b]) {
      if (s.valid && (best == null || s.gen > best.gen)) best = s;
    }
    final anySlotFile = a.raw != null || b.raw != null;
    var corruptPreserved = false;
    String? problem;
    var needFirstWrite = false;
    var needInitWrite = false;

    if (best != null) {
      _gen = best.gen;
      _activeSlot = best.slot;
      for (final s in <_Slot>[a, b]) {
        if (s.raw != null && !s.valid) {
          await _preserveCorrupt(_slotName(s.slot), s.raw!);
          corruptPreserved = true;
        }
      }
      needInitWrite = !initExists;
    } else if (initExists || anySlotFile) {
      problem = initExists && !anySlotFile
          ? 'metadata slots are missing'
          : 'metadata slots are unreadable';
    } else {
      // Fresh store (also: records of an older in-development build, which
      // seed the counters and markers below).
      needFirstWrite = true;
    }

    seed(records, best?.counters ?? <String, int>{},
        best?.markers ?? const <LogicalSetMarker>[]);
    if (problem != null) {
      // Fail closed: nothing is rewritten and the originals stay on disk.
      // Appends and pruning are refused; existing records stay readable.
      recoveryRequiredReason = problem;
    } else {
      if (needFirstWrite || markersNeedPersist) {
        await persistMetadata(seqCountersView, markersView);
        needInitWrite = !initExists;
      }
      if (needInitWrite) {
        await ops.writeAtomic(
            _initPath, Uint8List.fromList(utf8.encode('fitnessup-queue 2\n')));
      }
    }
    final recovered = await recoverInterrupted();
    _report = QueueOpenReport(
      loaded: records.where((r) => r.uid == uid).length,
      recoveredSending: recovered,
      removedTempFiles: removedTmp,
      unreadableFiles: unreadable,
      seqFileRepaired: corruptPreserved,
      markersFileRepaired: corruptPreserved,
      recoveryRequiredReason: recoveryRequiredReason,
    );
  }

  @override
  Future<void> persistRecord(CommandRecord record) => ops.writeAtomic(
        _recordPath(record.operationId),
        Uint8List.fromList(
            utf8.encode(jsonEncode({'format': 1, 'record': record.toJson()}))),
      );

  /// Writes the complete metadata document to the slot that does not hold the
  /// newest valid generation. The in-memory generation advances only after the
  /// rename succeeded; a throw leaves both slots as they were.
  @override
  Future<void> persistMetadata(
      Map<String, int> counters, Map<String, LogicalSetMarker> markers) async {
    final gen = _gen + 1;
    final slot = _activeSlot == 'a' ? 'b' : 'a';
    final body = jsonEncode({
      'format': 2,
      'gen': gen,
      'seq': counters,
      'logicalSets': {
        for (final e in markers.entries)
          e.key: {
            'operationId': e.value.operationId,
            'acceptedAt': e.value.acceptedAtLocalWallMs,
          },
      },
    });
    final sum = crypto.sha256.convert(utf8.encode(body));
    await ops.writeAtomic(_slotPath(slot),
        Uint8List.fromList(utf8.encode('$body\n$_checkPrefix$sum\n')));
    _gen = gen;
    _activeSlot = slot;
  }

  @override
  Future<void> removeRecordFromDisk(String operationId) =>
      ops.delete(_recordPath(operationId));

  Future<_Slot> _readSlot(String slot) async {
    final raw = await ops.read(_slotPath(slot));
    if (raw == null) return _Slot(slot, null);
    try {
      final text = utf8.decode(raw).trimRight();
      final idx = text.lastIndexOf('\n$_checkPrefix');
      if (idx < 0) return _Slot(slot, raw);
      final body = text.substring(0, idx);
      final claimed = text.substring(idx + 1 + _checkPrefix.length).trim();
      if (crypto.sha256.convert(utf8.encode(body)).toString() != claimed) {
        return _Slot(slot, raw);
      }
      final doc = Map<String, Object?>.from(jsonDecode(body) as Map);
      if (doc['format'] != 2) return _Slot(slot, raw);
      final gen = doc['gen'] as int;
      final counters = <String, int>{
        for (final e in (doc['seq'] as Map).entries)
          e.key as String: e.value as int,
      };
      final markers = <LogicalSetMarker>[
        for (final e in (doc['logicalSets'] as Map).entries)
          LogicalSetMarker(
            logicalSetId: e.key as String,
            operationId: (e.value as Map)['operationId'] as String,
            acceptedAtLocalWallMs: (e.value as Map)['acceptedAt'] as int,
          ),
      ];
      return _Slot(slot, raw, gen: gen, counters: counters, markers: markers);
    } catch (_) {
      return _Slot(slot, raw);
    }
  }

  /// Copies corrupt bytes to `<name>.corrupt-<n>` (n = highest existing + 1)
  /// beside the original, which is left in place.
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
}

/// One metadata slot as found on disk. [raw] null = file missing; [valid] =
/// checksum, format and content all verified.
class _Slot {
  _Slot(this.slot, this.raw, {this.gen = 0, this.counters, this.markers});

  final String slot;
  final Uint8List? raw;
  final int gen;
  final Map<String, int>? counters;
  final List<LogicalSetMarker>? markers;

  bool get valid => counters != null && markers != null;
}
