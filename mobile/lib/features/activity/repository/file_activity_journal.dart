/// The file-based activity journal (S02 design 3.4, 3.5, 10).
///
/// Layout, write order and recovery are documented in
/// `journal_generation_writer.dart` and `journal_recovery.dart`. This class
/// owns the in-process mutex (single writer), the monotonic sequence counter,
/// the encryption of `streams.bin` and the public API.
///
/// Acknowledgement: `put`, `delete` and the sync-state writers complete only
/// after the COMMIT rename (and the best-effort pointer and index steps that
/// follow it); `onAcknowledged` fires immediately before completion. Failures
/// of `CURRENT`, the index or the old-generation delete after the COMMIT never
/// fail the mutation: they are caches and recovery repairs them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../data/activity_migration.dart';
import '../data/activity_session.dart';
import '../data/activity_versions.dart';
import '../data/sample_stream.dart';
import '../data/sport_type.dart';
import 'activity_journal.dart';
import 'journal_cipher.dart';
import 'journal_errors.dart';
import 'journal_file_system.dart';
import 'journal_generation_writer.dart';
import 'journal_layout.dart';
import 'journal_models.dart';
import 'journal_recovery.dart';

class _Meta {
  _Meta(this.seq, this.record);

  final int seq;
  final JournalRecord record;
}

class FileActivityJournal implements ActivityJournal {
  FileActivityJournal({
    required String rootPath,
    JournalFileSystem fileSystem = const IoJournalFileSystem(),
    required JournalKeyProvider keyProvider,
    DateTime Function()? clock,
    BackupExclusionMarker backupMarker = const NoopBackupExclusionMarker(),
    this.onAcknowledged,
    Duration orphanMaxAge = const Duration(days: 7),
    int quarantineMaxCount = 20,
  })  : _fs = fileSystem,
        _keys = keyProvider,
        _clock = clock ?? DateTime.now,
        _marker = backupMarker,
        _orphanMaxAge = orphanMaxAge,
        _quarantineMax = quarantineMaxCount,
        _paths = JournalPaths(rootPath) {
    _writer = JournalGenerationWriter(_fs, _paths);
  }

  /// Opens the journal in the app support directory with the platform key
  /// store.
  static Future<FileActivityJournal> openDefault({
    BackupExclusionMarker backupMarker = const NoopBackupExclusionMarker(),
  }) async {
    final dir = await getApplicationSupportDirectory();
    return FileActivityJournal(
      rootPath: dir.path,
      keyProvider: SecureStorageJournalKeyProvider(),
      backupMarker: backupMarker,
    );
  }

  /// Called with `(id, seq)` right before a mutation's future completes, i.e.
  /// strictly after the COMMIT rename.
  final void Function(String id, int seq)? onAcknowledged;

  static final Set<String> _openRoots = {};

  final JournalFileSystem _fs;
  final JournalKeyProvider _keys;
  final DateTime Function() _clock;
  final BackupExclusionMarker _marker;
  final Duration _orphanMaxAge;
  final int _quarantineMax;
  final JournalPaths _paths;
  late final JournalGenerationWriter _writer;
  final JournalMutex _mutex = JournalMutex();
  final Map<String, _Meta> _meta = {};
  /// Persisted-lost: checksum mismatch, key present but decryption fails, key
  /// genuinely absent, or a stored streamLost flag. Only this set may feed
  /// `_commitStateOnly` and the early return in `read`.
  final Set<String> _lostIds = {};

  /// Transient-unavailable: key store threw or `streams.bin` hit an I/O error.
  /// Never persisted; retried on the next read.
  final Set<String> _unavailableIds = {};
  int _seq = 0;
  bool _started = false;
  bool _closed = false;

  @override
  int get streamLostCount => _lostIds.length;

  void _ensureStarted() {
    if (!_started || _closed) throw const JournalNotStartedException();
  }

  static void _checkId(String id) {
    if (!kJournalIdPattern.hasMatch(id)) throw JournalInvalidIdException(id);
  }

  @override
  Future<JournalRecoveryReport> start() => _mutex.run(() async {
        if (_closed) throw const JournalNotStartedException();
        if (!_started) {
          if (!_openRoots.add(_paths.root)) {
            throw JournalAlreadyOpenException(_paths.root);
          }
        }
        try {
          final result = await JournalRecoveryPass(
            fs: _fs,
            paths: _paths,
            writer: _writer,
            clock: _clock,
            orphanMaxAge: _orphanMaxAge,
            quarantineMaxCount: _quarantineMax,
          ).run();
          _meta
            ..clear()
            ..addAll({
              for (final e in result.entries.entries)
                e.key: _Meta(e.value.seq, e.value.record),
            });
          if (result.maxSeq > _seq) _seq = result.maxSeq;
          _lostIds
            ..clear()
            ..addAll(result.report.streamLost)
            ..addAll([
              for (final e in result.entries.entries)
                if (e.value.record.state.streamLost) e.key,
            ]);
          _unavailableIds
            ..clear()
            ..addAll(result.streamsUnavailable);
          for (final dir in [
            _paths.journalDir,
            _paths.sourcesDir,
            _paths.quarantineDir,
          ]) {
            await _marker.markExcluded(dir);
          }
          _started = true;
          return result.report;
        } catch (_) {
          if (!_started) _openRoots.remove(_paths.root);
          rethrow;
        }
      });

  @override
  Future<void> close() => _mutex.run(() async {
        if (_started || _closed) _openRoots.remove(_paths.root);
        _closed = true;
        _started = false;
      });

  // ---- mutations -----------------------------------------------------------

  @override
  Future<JournalEntry> put(
    ActivitySession session, {
    JournalSyncState? syncState,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) {
    _checkId(session.id);
    return _mutex.run(() async {
      _ensureStarted();
      if (session.isReadOnly) throw JournalReadOnlyException(session.id);
      final prev = _meta[session.id];
      if (prev != null) {
        if (prev.record.state.tombstone) {
          throw JournalTombstonedException(session.id);
        }
        final schema = prev.record.session['schema'];
        if (schema is num && schema > kActivitySchema) {
          throw JournalReadOnlyException(session.id);
        }
      }

      final sessionMap = session.toJson()..remove('streams');
      final plain = Uint8List.fromList(utf8.encode(jsonEncode({
        'streams': [
          for (final k in StreamKind.values)
            if (session.streams[k] != null) session.streams[k]!.toJson(),
        ],
      })));
      final plainHash = sha256Hex(plain);
      final base = prev?.record.state ?? const JournalState();
      final state = base.copyWith(
        syncState: syncState ?? JournalSyncState.pending,
        baseRev: baseRev ?? base.baseRev,
        baseSummary: baseSummary ?? base.baseSummary,
        streamLost: false,
        streamsPlainHash: plainHash,
      );

      // Idempotent replay: identical content and state is not a new mutation.
      if (prev != null &&
          syncState == null &&
          baseRev == null &&
          baseSummary == null &&
          !prev.record.state.streamLost &&
          prev.record.state.streamsPlainHash == plainHash &&
          jsonEncode(prev.record.session) == jsonEncode(sessionMap)) {
        return JournalEntry(
          session: session,
          state: prev.record.state,
          generation: prev.seq,
          streamsLoaded: true,
        );
      }

      final Uint8List key;
      try {
        key = await _keys.loadOrCreateKey();
      } catch (e) {
        throw JournalKeyUnavailable('encryption key unavailable',
            cause: e, pending: session);
      }
      final sealed =
          AesGcmJournalCipher(key).seal(Uint8List.fromList(gzip.encode(plain)));
      final meta = await _commit(
        session.id,
        sessionMap,
        state,
        sealed,
        'put',
        pending: session,
      );
      return JournalEntry(
        session: session,
        state: meta.record.state,
        generation: meta.seq,
        streamsLoaded: true,
      );
    });
  }

  @override
  Future<void> delete(String id) {
    _checkId(id);
    return _mutex.run(() async {
      _ensureStarted();
      final prev = _meta[id];
      if (prev != null && prev.record.state.tombstone) return;
      ActivitySession? old;
      if (prev != null) old = ActivityMigration.read(prev.record.session);
      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final skeleton = ActivitySession(
        id: id,
        sport: old?.sport ?? SportType.other,
        startUtc: old?.startUtc ?? epoch,
        endUtc: old?.endUtc ?? epoch,
      ).toJson()
        ..remove('streams');
      final state = JournalState(
        tombstone: true,
        syncState: JournalSyncState.pending,
        baseRev: prev?.record.state.baseRev,
        streamsPlainHash: null,
      );
      // A tombstone holds no streams: zero bytes, no key needed.
      await _commit(id, skeleton, state, Uint8List(0), 'delete');
    });
  }

  @override
  Future<bool> updateSyncState(
    String id,
    JournalSyncState state, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) {
    _checkId(id);
    return _mutex.run(() async {
      _ensureStarted();
      final prev = _meta[id];
      if (prev == null) return false;
      if (expectedGeneration != null && expectedGeneration != prev.seq) {
        return false;
      }
      final old = prev.record.state;
      final next = old.copyWith(
        syncState: state,
        baseRev: baseRev ?? old.baseRev,
        baseSummary: baseSummary ?? old.baseSummary,
      );
      if (next.syncState == old.syncState &&
          next.baseRev == old.baseRev &&
          jsonEncode(next.baseSummary) == jsonEncode(old.baseSummary)) {
        return true;
      }
      await _commitStateOnly(id, prev, next, 'synced');
      return true;
    });
  }

  @override
  Future<JournalEntry?> updateRecord(
    String id,
    ActivitySession session, {
    JournalSyncState? syncState,
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) {
    _checkId(id);
    return _mutex.run(() async {
      _ensureStarted();
      final prev = _meta[id];
      if (prev == null || prev.record.state.tombstone) return null;
      if (expectedGeneration != null && expectedGeneration != prev.seq) {
        return null;
      }
      final schema = prev.record.session['schema'];
      if (session.isReadOnly || (schema is num && schema > kActivitySchema)) {
        throw JournalReadOnlyException(id);
      }
      final sessionMap = session.toJson()..remove('streams');
      final old = prev.record.state;
      final next = old.copyWith(
        syncState: syncState ?? old.syncState,
        baseRev: baseRev ?? old.baseRev,
        baseSummary: baseSummary ?? old.baseSummary,
      );
      final entry = JournalEntry(
        session: session,
        state: old,
        generation: prev.seq,
        streamsLoaded: false,
      );
      if (jsonEncode(sessionMap) == jsonEncode(prev.record.session) &&
          next.syncState == old.syncState &&
          next.baseRev == old.baseRev &&
          jsonEncode(next.baseSummary) == jsonEncode(old.baseSummary)) {
        return entry;
      }
      final meta = await _commitStateOnly(id, prev, next, 'put',
          sessionMap: sessionMap);
      return JournalEntry(
        session: session,
        state: meta.record.state,
        generation: meta.seq,
        streamsLoaded: false,
      );
    });
  }

  @override
  Future<bool> markSynced(
    String id, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) =>
      updateSyncState(id, JournalSyncState.synced,
          expectedGeneration: expectedGeneration,
          baseRev: baseRev,
          baseSummary: baseSummary);

  @override
  Future<bool> markStreamUploaded(String id, {int? expectedGeneration}) {
    _checkId(id);
    return _mutex.run(() async {
      _ensureStarted();
      final prev = _meta[id];
      if (prev == null || prev.record.state.tombstone) return false;
      if (expectedGeneration != null && expectedGeneration != prev.seq) {
        return false;
      }
      final old = prev.record.state;
      final hash = old.streamsPlainHash;
      if (hash == null) return false;
      if (old.streamUploadedHash == hash) return true;
      await _commitStateOnly(
          id, prev, old.copyWith(streamUploadedHash: hash), 'synced');
      return true;
    });
  }

  /// A new generation with the same session map and the same `streams.bin`
  /// bytes and a changed state (unknown keys of a newer schema survive).
  Future<_Meta> _commitStateOnly(
      String id, _Meta prev, JournalState state, String op,
      {Map<String, dynamic>? sessionMap}) async {
    final streamsPath = '${_paths.genDir(id, prev.seq)}/$kStreamsFileName';
    Uint8List streams;
    var next = state;
    try {
      streams = await _fs.readBytes(streamsPath);
    } on FileSystemException catch (e) {
      // A MISSING streams.bin of a stream-lost entry must not block metadata
      // edits (sync state, overrides): the new generation carries an empty
      // streams.bin and the persisted streamLost flag. A file that exists but
      // cannot be read right now is a transient failure: abort, change nothing.
      if (await _fs.exists(streamsPath)) {
        throw JournalIoException('cannot read current streams', cause: e);
      }
      streams = Uint8List(0);
      next = next.copyWith(streamLost: true, streamsPlainHash: null);
    }
    if (_lostIds.contains(id) && !next.streamLost) {
      next = next.copyWith(streamLost: true);
    }
    return _commit(id, sessionMap ?? prev.record.session, next, streams, op);
  }

  /// Steps of design 10: new generation, COMMIT (the commit point), then the
  /// best-effort pointer and index. Returns after the acknowledgement point.
  Future<_Meta> _commit(
    String id,
    Map<String, dynamic> sessionMap,
    JournalState state,
    Uint8List streamsBytes,
    String op, {
    ActivitySession? pending,
  }) async {
    final seq = ++_seq;
    final record = JournalRecord(
      seq: seq,
      streamHash: sha256Hex(streamsBytes),
      session: sessionMap,
      state: state,
    );
    try {
      await _writer.write(id, seq, record, streamsBytes);
    } on GenerationAborted catch (e) {
      if (isDiskFull(e.cause)) {
        throw JournalStorageFullException('storage full',
            cause: e.cause, pending: pending);
      }
      throw JournalIoException('journal write failed',
          cause: e.cause, pending: pending);
    }
    // ---- committed: the mutation is durable from here on -------------------
    final meta = _Meta(seq, record);
    _meta[id] = meta;
    try {
      await _writer.writeCurrent(id, seq, record.streamHash);
    } on FileSystemException {
      // CURRENT is a pointer; recovery rebuilds it.
    }
    try {
      await _writer.appendIndex(op, id, seq);
    } on FileSystemException {
      // The index is a cache; recovery rebuilds it from the records.
    }
    onAcknowledged?.call(id, seq);
    return meta;
  }

  // ---- reads ---------------------------------------------------------------

  JournalEntry? _summaryEntry(_Meta m) {
    final s = ActivityMigration.read(m.record.session);
    if (s == null) return null;
    return JournalEntry(
      session: s,
      state: m.record.state,
      generation: m.seq,
      streamsLoaded: false,
    );
  }

  List<JournalEntry> _entries({required bool tombstones}) {
    final metas = _meta.values
        .where((m) => m.record.state.tombstone == tombstones)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return [
      for (final m in metas)
        if (_summaryEntry(m) case final e?) e,
    ];
  }

  @override
  Future<List<JournalEntry>> list() => _mutex.run(() async {
        _ensureStarted();
        return _entries(tombstones: false);
      });

  @override
  Future<List<JournalEntry>> listTombstones() => _mutex.run(() async {
        _ensureStarted();
        return _entries(tombstones: true);
      });

  @override
  Future<JournalEntry?> read(String id) {
    _checkId(id);
    return _mutex.run(() async {
      _ensureStarted();
      final meta = _meta[id];
      if (meta == null || meta.record.state.tombstone) return null;
      final dir = _paths.genDir(id, meta.seq);

      // Re-verify the record against its COMMIT marker.
      // The cache entry is dropped ONLY on a verified mismatch (marker or record
      // missing, or hash different). An I/O error keeps the entry and surfaces
      // a JournalIoException so the caller can retry.
      final JournalRecord record;
      final Uint8List? bytes;
      final CommitMarker? commit;
      try {
        commit = await _writer.readCommit(id, meta.seq);
        bytes = await _writer.readIfPresent('$dir/$kRecordFileName');
      } on JournalUnreadable catch (e) {
        throw JournalIoException('cannot read journal entry $id',
            cause: e.cause);
      }
      final parsed = bytes == null ? null : JournalRecord.tryDecode(bytes);
      if (commit == null ||
          bytes == null ||
          parsed == null ||
          sha256Hex(bytes) != commit.recordSha256) {
        _meta.remove(id);
        return null;
      }
      record = parsed;
      final base = _summaryEntryOf(record, meta.seq);
      if (base == null) return null;
      if (record.state.streamLost) {
        _lostIds.add(id);
        return base;
      }

      // A missing file is persisted loss; an I/O error is transient.
      Uint8List? streamsBytes;
      try {
        streamsBytes = await _writer.readIfPresent('$dir/$kStreamsFileName');
      } on JournalUnreadable {
        _unavailableIds.add(id);
        return _lostEntry(base);
      }
      if (streamsBytes == null ||
          record.streamHash != commit.streamsSha256 ||
          sha256Hex(streamsBytes) != commit.streamsSha256) {
        // Damaged streams of a committed generation: derived, not persisted.
        _lostIds.add(id);
        return _lostEntry(base);
      }

      Uint8List? key;
      try {
        key = await _keys.loadKey();
      } catch (_) {
        // Transient failure: unavailable now, never persisted as lost.
        _unavailableIds.add(id);
        return _lostEntry(base);
      }
      List<dynamic>? streams;
      if (key != null) {
        try {
          final plain = gzip.decode(AesGcmJournalCipher(key).open(streamsBytes));
          final doc = jsonDecode(utf8.decode(plain));
          if (doc is Map && doc['streams'] is List) {
            streams = doc['streams'] as List;
          }
        } catch (_) {
          streams = null;
        }
      }
      if (streams == null) {
        // Key loss (design 3.5): persist streamLost in a NEW generation, never
        // crash, never wipe, never download.
        _lostIds.add(id);
        try {
          final lost = await _commitStateOnly(
              id, meta, record.state.copyWith(streamLost: true), 'put');
          return _lostEntry(_summaryEntryOf(lost.record, lost.seq)!);
        } on JournalException {
          return _lostEntry(base);
        }
      }

      final session = ActivityMigration.read({...record.session, 'streams': streams});
      if (session == null) return null;
      _lostIds.remove(id);
      _unavailableIds.remove(id);
      await _pruneOlder(id, meta.seq);
      return JournalEntry(
        session: session,
        state: record.state,
        generation: meta.seq,
        streamsLoaded: true,
      );
    });
  }

  JournalEntry? _summaryEntryOf(JournalRecord r, int seq) {
    final s = ActivityMigration.read(r.session);
    if (s == null) return null;
    return JournalEntry(
      session: s,
      state: r.state,
      generation: seq,
      streamsLoaded: false,
    );
  }

  JournalEntry _lostEntry(JournalEntry e) => JournalEntry(
        session: e.session,
        state: e.state.copyWith(streamLost: true),
        generation: e.generation,
        streamsLoaded: false,
      );

  /// Deletes generations older than [keepSeq] after a verified read of the
  /// selected one (design 10 step 7). Failures leave orphans for recovery.
  Future<void> _pruneOlder(String id, int keepSeq) async {
    try {
      for (final e in await _fs.list(_paths.activityDir(id))) {
        final g = JournalPaths.parseGeneration(e.name);
        if (e.isDirectory && g != null && g < keepSeq) {
          await _fs.deleteDir(_paths.genDir(id, g));
        }
      }
    } on FileSystemException {
      // Orphan: removed by the next recovery pass.
    }
  }

  // ---- sign-out and wipe ---------------------------------------------------

  @override
  Future<SignOutAssessment> assessSignOut() => _mutex.run(() async {
        _ensureStarted();
        final live = _meta.values.where((m) => !m.record.state.tombstone);
        return SignOutAssessment(
          entryCount: live.length,
          unsyncedCount: live.where((m) => !m.record.state.synced).length,
          streamLostCount: live.where((m) => _lostIds.contains(m.record.id)).length,
        );
      });

  @override
  Future<void> wipe() => _mutex.run(() async {
        _ensureStarted();
        for (final dir in [
          _paths.journalDir,
          _paths.sourcesDir,
          _paths.quarantineDir,
        ]) {
          await _fs.deleteDir(dir);
          await _fs.createDir(dir);
        }
        _meta.clear();
        _lostIds.clear();
        _unavailableIds.clear();
        await _keys.forget();
      });
}
