/// Value types of the local journal (S02 design 3.4, 10): the on-disk record
/// envelope, the COMMIT marker, the entry handed to callers, the recovery
/// report and a small async mutex.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../data/activity_session.dart';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Sync state of an entry. `synced` is written only after the commit callable
/// returned success (design 10).
enum JournalSyncState {
  pending('pending'),
  synced('synced'),
  uploadFailed('upload_failed'),
  syncConflict('sync_conflict');

  const JournalSyncState(this.wire);

  final String wire;

  static JournalSyncState parse(Object? raw) {
    for (final s in values) {
      if (s.wire == raw) return s;
    }
    return pending;
  }
}

/// Journal-owned state stored in `record.json` next to the session map.
/// Tombstone, `synced` and the sync bookkeeping live here, so rebuilding the
/// index from records loses none of them (design 10).
class JournalState {
  const JournalState({
    this.tombstone = false,
    this.syncState = JournalSyncState.pending,
    this.baseRev,
    this.baseSummary,
    this.streamLost = false,
    this.streamsPlainHash,
    this.streamUploadedHash,
  });

  final bool tombstone;
  final JournalSyncState syncState;

  /// Server revision this device last synced (design 3.2).
  final int? baseRev;

  /// Summary last stored or read from the server (design 3.2).
  final Map<String, Object?>? baseSummary;

  /// The stream is unavailable on this device (design 3.5).
  final bool streamLost;

  /// SHA-256 of the plaintext streams document; makes an identical re-put a
  /// no-op without decrypting.
  final String? streamsPlainHash;

  /// The [streamsPlainHash] whose private stream object the cloud has stored
  /// (set only after the commit callable succeeded). Separate from
  /// [syncState], which the SUMMARY sync owns: a summary sync that marked the
  /// entry `synced` must not hide a stream that was never uploaded, and a
  /// stream upload must not hide an unsynced summary.
  final String? streamUploadedHash;

  /// True when the current streams are not yet in the cloud.
  bool get streamUploadPending =>
      streamsPlainHash != null && streamUploadedHash != streamsPlainHash;

  bool get synced => syncState == JournalSyncState.synced;

  JournalState copyWith({
    bool? tombstone,
    JournalSyncState? syncState,
    Object? baseRev = _keep,
    Object? baseSummary = _keep,
    bool? streamLost,
    Object? streamsPlainHash = _keep,
    Object? streamUploadedHash = _keep,
  }) =>
      JournalState(
        tombstone: tombstone ?? this.tombstone,
        syncState: syncState ?? this.syncState,
        baseRev: identical(baseRev, _keep) ? this.baseRev : baseRev as int?,
        baseSummary: identical(baseSummary, _keep)
            ? this.baseSummary
            : baseSummary as Map<String, Object?>?,
        streamLost: streamLost ?? this.streamLost,
        streamsPlainHash: identical(streamsPlainHash, _keep)
            ? this.streamsPlainHash
            : streamsPlainHash as String?,
        streamUploadedHash: identical(streamUploadedHash, _keep)
            ? this.streamUploadedHash
            : streamUploadedHash as String?,
      );

  static const Object _keep = Object();

  Map<String, dynamic> toJson() => {
        'tombstone': tombstone,
        'synced': synced,
        'syncState': syncState.wire,
        if (baseRev != null) 'baseRev': baseRev,
        if (baseSummary != null) 'baseSummary': baseSummary,
        'streamLost': streamLost,
        if (streamsPlainHash != null) 'streamsPlainHash': streamsPlainHash,
        if (streamUploadedHash != null) 'streamUploadedHash': streamUploadedHash,
      };

  static JournalState fromJson(Object? raw) {
    if (raw is! Map) return const JournalState();
    final rev = raw['baseRev'];
    final base = raw['baseSummary'];
    return JournalState(
      tombstone: raw['tombstone'] == true,
      syncState: raw.containsKey('syncState')
          ? JournalSyncState.parse(raw['syncState'])
          : (raw['synced'] == true
              ? JournalSyncState.synced
              : JournalSyncState.pending),
      baseRev: rev is num ? rev.toInt() : null,
      baseSummary: base is Map
          ? {for (final e in base.entries) e.key.toString(): e.value}
          : null,
      streamLost: raw['streamLost'] == true,
      streamsPlainHash:
          raw['streamsPlainHash'] is String ? raw['streamsPlainHash'] as String : null,
      streamUploadedHash: raw['streamUploadedHash'] is String
          ? raw['streamUploadedHash'] as String
          : null,
    );
  }
}

/// `record.json` of one generation: the session map WITHOUT streams (kept raw
/// so a newer-schema record round-trips unknown keys), the journal state, the
/// mutation `seq` and the hash of the same generation's `streams.bin`.
class JournalRecord {
  const JournalRecord({
    required this.seq,
    required this.streamHash,
    required this.session,
    required this.state,
  });

  static const int format = 1;

  final int seq;
  final String streamHash;
  final Map<String, dynamic> session;
  final JournalState state;

  String get id => session['id'] is String ? session['id'] as String : '';

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'format': format,
        'seq': seq,
        'streamHash': streamHash,
        'state': state.toJson(),
        'session': session,
      })));

  static JournalRecord? tryDecode(Uint8List bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) return null;
      final session = raw['session'];
      final seq = raw['seq'];
      final hash = raw['streamHash'];
      if (session is! Map || seq is! num || hash is! String) return null;
      if (session['id'] is! String) return null;
      return JournalRecord(
        seq: seq.toInt(),
        streamHash: hash,
        session: {for (final e in session.entries) e.key.toString(): e.value},
        state: JournalState.fromJson(raw['state']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The COMMIT marker. Its atomic rename is THE commit point (design 10).
class CommitMarker {
  const CommitMarker({
    required this.seq,
    required this.recordSha256,
    required this.streamsSha256,
  });

  final int seq;
  final String recordSha256;
  final String streamsSha256;

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'seq': seq,
        'record': recordSha256,
        'streams': streamsSha256,
      })));

  static CommitMarker? tryDecode(Uint8List bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) return null;
      final seq = raw['seq'];
      final r = raw['record'];
      final s = raw['streams'];
      if (seq is! num || r is! String || s is! String) return null;
      return CommitMarker(seq: seq.toInt(), recordSha256: r, streamsSha256: s);
    } catch (_) {
      return null;
    }
  }
}

/// What callers see. [session] has its streams only when [streamsLoaded];
/// never `put` a session read without streams back.
class JournalEntry {
  const JournalEntry({
    required this.session,
    required this.state,
    required this.generation,
    required this.streamsLoaded,
  });

  final ActivitySession session;
  final JournalState state;

  /// The `seq` of the selected generation (`g<generation>`).
  final int generation;
  final bool streamsLoaded;

  String get id => session.id;
  bool get streamLost => state.streamLost;
}

/// Outcome of the recovery pass (read by tests and diagnostics).
class JournalRecoveryReport {
  /// Activity id -> selected generation number.
  final Map<String, int> selectedGenerations = {};

  /// Activities flagged `streamLost` at recovery (damaged or missing
  /// `streams.bin` of a COMMITTED generation).
  final Set<String> streamLost = {};

  /// Activities dropped because no generation had a valid COMMIT.
  final Set<String> absent = {};

  /// Generation directories deleted (uncommitted, invalid or aged orphans).
  final List<String> deletedGenerations = [];

  /// Activities whose CURRENT pointer was rewritten.
  final Set<String> currentRepaired = {};
  bool indexRebuilt = false;
  int tempFilesRemoved = 0;
  final List<String> diagnostics = [];
}

/// Result of the sign-out assessment (design 3.5).
class SignOutAssessment {
  const SignOutAssessment({
    required this.entryCount,
    required this.unsyncedCount,
    required this.streamLostCount,
  });

  /// Live (non-deleted) entries. Any non-zero value warns: laps, provenance
  /// and heart rate never upload, so the device holds data the cloud lacks.
  final int entryCount;
  final int unsyncedCount;
  final int streamLostCount;

  bool get requiresWarning => entryCount > 0;
}

/// A minimal async lock: callers run strictly one after another (design 10
/// single writer).
class JournalMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() body) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }
}
