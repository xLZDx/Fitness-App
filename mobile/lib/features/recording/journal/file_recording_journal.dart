/// The crash-safe recording journal (S04 design 4, lane R5): a sibling of the S02
/// activity journal under the same account scope, implementing the recorder's
/// [RecordingJournalPort]. It is the ONLY place with file I/O for recordings.
///
/// Layout: `<scopes root>/<scopeId>/recording/<recordingId>/` with `meta.json`,
/// `seg-NNNN.log`, `SEALED`, `QUARANTINED`, `DECISION`, `DISCARDING`,
/// `FALLBACK`; a verified KEEP cleanup renames the directory to
/// `<recordingId>.cleanup` first. Every file but the plain progress markers is
/// sealed with the scope's AES-GCM key.
///
/// Errors are content-free ([RecordingJournalError] carries a fixed code).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../activity/data/activity_session.dart';
import '../../activity/data/activity_summary.dart';
import '../../activity/data/native_session_id.dart';
import '../../activity/data/sample_stream.dart';
import '../../activity/data/sport_type.dart';
import '../../activity/repository/activity_journal.dart';
import '../../activity/repository/file_activity_journal.dart'
    show HeavyWorkRunner, IsolateHeavyWorkRunner;
import '../../activity/repository/journal_cipher.dart';
import '../../activity/repository/journal_errors.dart';
import '../../activity/repository/journal_file_system.dart';
import '../../activity/repository/journal_layout.dart';
import '../../activity/repository/journal_models.dart' show JournalMutex;
import '../../activity/repository/journal_recovery.dart' show kJournalIdPattern;
import '../../activity/repository/uid_scoped_activity_journal.dart'
    show
        OwnerCheckedPut,
        RecordingScopeGuard,
        RecordingScopeReopener,
        activityJournalScopeId;
import '../pipeline/pipeline_types.dart';
import '../pipeline/recording_constants.dart';
import '../state/recorder_phase.dart' show StopReason;
import '../state/recording_journal_port.dart';
import 'pre_unbind_hook.dart';
import 'recording_codec.dart';
import 'recording_file_ops.dart';

/// Content-free failure of the recording journal.
class RecordingJournalError implements Exception {
  const RecordingJournalError(this.code);

  final String code;

  @override
  String toString() => 'RecordingJournalError($code)';
}

const String kMetaFile = 'meta.json';
const String kSealedFile = 'SEALED';
const String kQuarantinedFile = 'QUARANTINED';
const String kDecisionFile = 'DECISION';
const String kDiscardingFile = 'DISCARDING';
const String kFallbackFile = 'FALLBACK';
const String kCleanupSuffix = '.cleanup';
const String kRecordingLockFile = 'recording.lock';

/// 30 days (PROPOSED): quarantined and fallback recordings expire.
const int kRecordingExpiryMs = 30 * 24 * 3600 * 1000;
const int kStorageRetryWindowMs = 60000;
const int kUnboundBufferMs = 120000;
const int kFlushBatchSamples = 10;
const int kDecisionWaitMs = 2000;

String _segName(int n) => 'seg-${n.toString().padLeft(4, '0')}.log';
final RegExp _segPattern = RegExp(r'^seg-(\d{4,})\.log$');

class _Pending {
  _Pending(this.build, {this.isBreak = false});

  final Uint8List Function(int counter) build;
  final bool isBreak;
}

class _Active {
  _Active(this.id, this.scopeId, this.uid, this.cipher, this.dir);

  final String id;
  final String scopeId;
  final String uid;
  final JournalCipher cipher;
  final String dir;
  final JournalMutex lock = JournalMutex();
  final List<PipelineSample> batch = [];
  final List<_Pending> pending = [];
  GateCounters counters = GateCounters.zero;
  int counter = 0; // last acknowledged frame counter
  int segNo = 0; // number of the segment the handle writes (0 = none yet)
  int segFrames = 0;
  int lastOffset = 0;
  JournalWriteHandle? handle;
  int? suspectSeg;
  Timer? timer;
  int? failingSince;
  bool gaveUp = false;
  int? unboundSince;
  bool lostReported = false;
  bool closed = false;
}

class _Scope {
  _Scope(this.scopeId, this.uid, this.root, this.recDir, this.cipher);

  final String scopeId;
  final String uid;
  final String root;
  final String recDir;
  final JournalCipher? cipher;
}

class _MetaData {
  _MetaData(this.id, this.startUtcMs, this.offsetMin, this.sport,
      this.autoPause, this.scopeId, this.uid);

  final String id;
  final int startUtcMs;
  final int offsetMin;
  final SportType sport;
  final bool autoPause;
  final String scopeId;
  final String uid;

  RecordingMeta toPort() => RecordingMeta(
        recordingId: id,
        startUtcMs: startUtcMs,
        utcOffsetMinutes: offsetMin,
        sport: sport,
        autoPauseEnabled: autoPause,
        ownerUid: uid,
      );
}

/// Outcome of [FileRecordingJournal.finishAllForOwner].
class FinishAllReport {
  const FinishAllReport(this.handedOff, this.keptInFallback);

  final int handedOff;
  final int keptInFallback;
}

class FileRecordingJournal
    implements RecordingJournalPort, RecordingScopeGuard, RecordingScopeReopener {
  FileRecordingJournal({
    required ActivityJournal activity,
    required String? Function() boundUid,
    required Future<String> Function() scopesRoot,
    required JournalKeyProvider Function(String scopeId) keyProviderFor,
    JournalFileSystem fileSystem = const IoJournalFileSystem(),
    RecordingFileOps fileOps = const IoRecordingFileOps(),
    HeavyWorkRunner runner = const IsolateHeavyWorkRunner(),
    int Function()? nowUtcMs,
    void Function()? onHandedOff,
  })  : _activity = activity,
        _boundUid = boundUid,
        _scopesRoot = scopesRoot,
        _keyFor = keyProviderFor,
        _fs = fileSystem,
        _ops = fileOps,
        _runner = runner,
        _now = nowUtcMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
        _onHandedOff = onHandedOff;

  final ActivityJournal _activity;
  final String? Function() _boundUid;
  final Future<String> Function() _scopesRoot;
  final JournalKeyProvider Function(String) _keyFor;
  final JournalFileSystem _fs;
  final RecordingFileOps _ops;
  final HeavyWorkRunner _runner;
  final int Function() _now;
  final void Function()? _onHandedOff;

  final Map<String, JournalKeyProvider> _keys = {};
  final Map<String, Object> _locks = {};
  final Map<String, Future<void>> _lockFutures = {};
  final Set<String> _closedScopes = {};
  final Map<String, JournalMutex> _recMutex = {};
  final Map<String, Future<void>> _publishing = {};
  final StreamController<JournalFault> _faults = StreamController.broadcast();
  _Active? _active;
  int _flushMs = 5000;

  /// Set by `finishAllForOwner` while the pre-unbind hook runs.
  bool Function()? _handOffCancelled;

  @override
  Stream<JournalFault> get faults => _faults.stream;

  void _fault(JournalFault f) {
    if (!_faults.isClosed) _faults.add(f);
  }

  JournalMutex _mutexFor(String id) => _recMutex.putIfAbsent(id, JournalMutex.new);

  // ------------------------------------------------------------ scope

  /// The bound scope, or null when nothing may be read or written (unbound,
  /// closed for a wipe, durable wiped marker present). Takes the process-wide
  /// lock on first use of a scope (design 4.3, Z14).
  Future<_Scope?> _scope() async {
    final uid = _boundUid();
    if (uid == null || uid.isEmpty) return null;
    final scopeId = activityJournalScopeId(uid);
    if (_closedScopes.contains(scopeId)) return null;
    final base = await _scopesRoot();
    if (await _fs.exists('$base/$scopeId$kWipedMarkerSuffix')) return null;
    final root = '$base/$scopeId';
    final recDir = '$root/$kRecordingDirName';
    if (!_locks.containsKey(scopeId)) {
      // One acquisition per scope: concurrent first callers share the future
      // instead of racing for the process lock (review C13).
      await _lockFutures.putIfAbsent(
          scopeId, () => _acquireScopeLock(scopeId, recDir));
    }
    final key = await _keys.putIfAbsent(scopeId, () => _keyFor(scopeId)).loadKey();
    return _Scope(scopeId, uid, root, recDir, key == null ? null : AesGcmJournalCipher(key));
  }

  Future<void> _acquireScopeLock(String scopeId, String recDir) async {
    try {
      await _fs.createDir(recDir);
      _locks[scopeId] = await _ops.acquireLock('$recDir/$kRecordingLockFile');
    } catch (_) {
      _lockFutures.remove(scopeId); // a failed acquisition is retried later
      throw const RecordingJournalError('journalLocked');
    }
  }

  /// Releases the active recording's timer and every process lock (provider
  /// dispose). Never seals or deletes.
  Future<void> dispose() async {
    final a = _active;
    if (a != null) await _detach(a);
    for (final id in List<String>.of(_locks.keys)) {
      final l = _locks.remove(id);
      if (l == null) continue;
      try {
        await _ops.releaseLock(l);
      } catch (_) {}
    }
    _lockFutures.clear();
  }

  Future<_Scope> _needScope() async {
    final s = await _scope();
    if (s == null) throw const RecordingJournalError('ownerScopeLost');
    return s;
  }

  @override
  void reopenScope(String scopeId) => _closedScopes.remove(scopeId);

  @override
  Future<void> closeScope(String scopeId) async {
    _closedScopes.add(scopeId);
    final a = _active;
    if (a != null && a.scopeId == scopeId) {
      a.closed = true;
      a.timer?.cancel();
      await a.lock.run(() async {
        await _closeHandle(a);
      });
      _fault(JournalFault.ownerScopeLost);
      _active = null;
    }
    _lockFutures.remove(scopeId);
    final l = _locks.remove(scopeId);
    if (l != null) {
      try {
        await _ops.releaseLock(l);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ file helpers

  Future<void> _atomicWrite(String path, Uint8List bytes) async {
    final tmp = '$path$kTempSuffix';
    JournalWriteHandle? h;
    try {
      h = await _fs.openWrite(tmp);
      await h.write(bytes);
      await h.flush();
      await h.fsync();
      await h.close();
      h = null;
      await _fs.rename(tmp, path);
    } catch (_) {
      if (h != null) {
        try {
          await h.close();
        } catch (_) {}
      }
      try {
        await _fs.deleteFile(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  Future<Uint8List?> _readOpt(String path) async {
    if (!await _fs.exists(path)) return null;
    return _fs.readBytes(path);
  }

  Uint8List _utf(String s) => Uint8List.fromList(utf8.encode(s));

  Future<void> _closeHandle(_Active a) async {
    final h = a.handle;
    a.handle = null;
    if (h != null) {
      try {
        await h.close();
      } catch (_) {}
    }
  }

  /// Detaches [a] from the journal WITHOUT sealing or deleting: the timer stops,
  /// the handle closes, the active slot clears. The files stay as an unfinished
  /// recording (review C1, C2, C11).
  Future<void> _detach(_Active a) async {
    a.closed = true;
    a.timer?.cancel();
    await a.lock.run(() => _closeHandle(a));
    if (identical(_active, a)) _active = null;
  }

  @override
  Future<void> abandonActive(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        final a = _active;
        if (a == null || a.id != recordingId) return;
        await _detach(a);
        try {
          // Only a truly empty directory is removed; anything else is data.
          if ((await _fs.list(a.dir)).isEmpty) await _fs.deleteDir(a.dir);
        } catch (_) {}
      });

  /// Reads `meta.json`. An I/O failure PROPAGATES (the caller reports
  /// `unavailable`); only an undecodable or foreign file yields null (review
  /// C3).
  Future<_MetaData?> _readMeta(_Scope s, String id) async {
    final c = s.cipher;
    if (c == null) return null;
    final raw = await _readOpt('${s.recDir}/$id/$kMetaFile');
    if (raw == null) return null;
    try {
      final m = jsonDecode(utf8.decode(c.open(raw)));
      if (m is! Map || m['v'] != 1 || m['id'] != id) return null;
      final sport = SportType.values.firstWhere((x) => x.name == m['sport'],
          orElse: () => SportType.other);
      final scope = m['scope'], uid = m['uid'];
      if (scope is! String || uid is! String || m['t0'] is! int) return null;
      return _MetaData(id, m['t0'] as int, (m['tz'] as int?) ?? 0, sport,
          m['ap'] == true, scope, uid);
    } catch (_) {
      return null;
    }
  }

  /// True when [id] is the active recording (it is never offered or swept).
  bool _isActive(String id) => _active?.id == id;

  /// Segment numbers present in [dir], ascending.
  Future<List<int>> _segments(String dir) async {
    final out = <int>[];
    for (final e in await _fs.list(dir)) {
      final m = _segPattern.firstMatch(e.name);
      if (!e.isDirectory && m != null) out.add(int.parse(m.group(1)!));
    }
    out.sort();
    return out;
  }

  Future<AnalyseResult> _analyse(_Scope s, String dir,
      {bool track = false,
      bool metrics = false,
      int startUtcMs = 0,
      int? elapsed}) async {
    final c = s.cipher;
    final nums = await _segments(dir);
    final bytes = <Uint8List>[
      for (final n in nums) await _fs.readBytes('$dir/${_segName(n)}'),
    ];
    final key = await _keys[s.scopeId]!.loadKey();
    if (c == null || key == null) return AnalyseResult(damage: Damage.badFrame);
    try {
      return await _runner.run<AnalyseJob, AnalyseResult>(
        analyseRecording,
        AnalyseJob(
          segNumbers: nums,
          segBytes: bytes,
          key: key,
          wantTrack: track,
          wantMetrics: metrics,
          startUtcMs: startUtcMs,
          elapsedOverrideMs: elapsed,
        ),
      );
    } catch (_) {
      // The runner failed: that says nothing about the data (review C3).
      return AnalyseResult(damage: Damage.unavailable);
    }
  }

  // ------------------------------------------------------------ begin / write

  @override
  Future<void> begin(RecordingMeta meta) async {
    if (!kJournalIdPattern.hasMatch(meta.recordingId)) {
      throw const RecordingJournalError('badId');
    }
    if (_active != null) throw const RecordingJournalError('alreadyActive');
    final s = await _needScope();
    if (s.uid != meta.ownerUid) throw const RecordingJournalError('ownerScopeLost');
    Uint8List key;
    try {
      key = await _keys[s.scopeId]!.loadOrCreateKey();
    } catch (_) {
      throw const RecordingJournalError('keyUnavailable');
    }
    final cipher = AesGcmJournalCipher(key);
    final dir = '${s.recDir}/${meta.recordingId}';
    var created = false;
    try {
      created = !await _fs.exists(dir);
      await _fs.createDir(dir);
      await _atomicWrite(
        '$dir/$kMetaFile',
        cipher.seal(_utf(jsonEncode({
          'v': 1,
          'id': meta.recordingId,
          't0': meta.startUtcMs,
          'tz': meta.utcOffsetMinutes,
          'sport': meta.sport.name,
          'ap': meta.autoPauseEnabled,
          'scope': s.scopeId,
          'uid': meta.ownerUid,
          'calc': kCalculatorVersionPrefix,
          'smooth': kSmoothingAlgorithmId,
        }))),
      );
    } on Object catch (_) {
      // A failed begin leaves no recording directory (S04-16 AC, DT-11-4):
      // an empty directory would later be offered as an unreadable recording.
      if (created) {
        try {
          await _fs.deleteDir(dir);
        } catch (_) {}
      }
      throw const RecordingJournalError('io');
    }
    if (_active != null) {
      // A late begin that finished after another one took the slot.
      if (created) {
        try {
          await _fs.deleteDir(dir);
        } catch (_) {}
      }
      throw const RecordingJournalError('alreadyActive');
    }
    _activate(_Active(meta.recordingId, s.scopeId, s.uid, cipher, dir));
  }

  void _activate(_Active a) {
    _active = a;
    _restartTimer();
  }

  void _restartTimer() {
    final a = _active;
    if (a == null) return;
    a.timer?.cancel();
    a.timer = Timer.periodic(Duration(milliseconds: _flushMs), (_) {
      if (a.batch.isNotEmpty || a.pending.isNotEmpty) unawaited(_drain(a));
    });
  }

  @override
  void setFlushIntervalMs(int ms) {
    _flushMs = ms < 100 ? 100 : ms;
    _restartTimer();
  }

  @override
  void enqueueSample(PipelineSample sample, GateCounters counters) {
    final a = _active;
    if (a == null || a.closed) return;
    a.batch.add(sample);
    a.counters = counters;
    if (sample.offsetMs > a.lastOffset) a.lastOffset = sample.offsetMs;
    if (a.batch.length >= kFlushBatchSamples) unawaited(_drain(a));
  }

  void _closeBatch(_Active a) {
    if (a.batch.isEmpty) return;
    final copy = List<PipelineSample>.of(a.batch);
    final rj = a.counters;
    a.batch.clear();
    a.pending.add(_Pending((n) => samplesPayload(n, copy, rj)));
  }

  @override
  Future<void> appendEvent(JournalEvent event) async {
    final a = _active;
    if (a == null) throw const RecordingJournalError('notActive');
    _closeBatch(a);
    if (event.offsetMs > a.lastOffset) a.lastOffset = event.offsetMs;
    final kind = event.kind.name;
    final off = event.offsetMs;
    a.pending.add(_Pending((n) => eventPayload(n, kind, off)));
    await _drain(a);
  }

  @override
  Future<void> flush() async {
    final a = _active;
    if (a == null) return;
    _closeBatch(a);
    await _drain(a);
  }

  Future<void> _drain(_Active a) => a.lock.run(() async {
        _closeBatch(a);
        if (a.pending.isEmpty || a.closed) return;
        final bound = _boundUid();
        if (_closedScopes.contains(a.scopeId) || (bound != null && bound != a.uid)) {
          if (!a.lostReported) {
            a.lostReported = true;
            _fault(JournalFault.ownerScopeLost);
          }
          return;
        }
        if (bound == null) {
          // Transient null: keep the frames in memory (bounded, design 4.7).
          a.unboundSince ??= _now();
          if (_now() - a.unboundSince! > kUnboundBufferMs && !a.lostReported) {
            a.lostReported = true;
            _fault(JournalFault.ownerScopeLost);
          }
          return;
        }
        a.unboundSince = null;
        try {
          await _writePending(a);
          if (a.failingSince != null) {
            a.failingSince = null;
            a.gaveUp = false;
            _fault(JournalFault.storageRecovered);
          }
        } catch (_) {
          await _closeHandle(a);
          // Nothing to re-read when no segment was ever opened.
          if (a.segNo > 0) a.suspectSeg = a.segNo;
          final first = a.failingSince == null;
          a.failingSince ??= _now();
          if (first) _fault(JournalFault.storageFailing);
          if (!a.gaveUp &&
              (_now() - a.failingSince! >= kStorageRetryWindowMs ||
                  a.pending.length > 1000)) {
            a.gaveUp = true;
            _fault(JournalFault.storageGaveUp);
          }
        }
      });

  /// Writes the pending frames in order, one fsync at the end. A rotation after
  /// a write error first re-reads the suspect segment (design 4.2, ARCH4).
  Future<void> _writePending(_Active a) async {
    if (a.suspectSeg != null) await _rotateAfterError(a);
    var n = a.counter;
    // `work` is a snapshot that is never structurally modified while it is
    // iterated (a removal inside a for-in over it throws
    // ConcurrentModificationError). `done` counts the frames written since the
    // last durable prune of `a.pending`, which is the offset of the unpruned
    // head of the snapshot.
    final work = List<_Pending>.of(a.pending);
    final last = work.isEmpty ? null : work.last;
    var done = 0;
    for (var i = 0; i < work.length; i++) {
      final p = work[i];
      if (a.handle == null) {
        // The number advances only once the file is open: a failed open (disk
        // full) must not leave a hole in the segment numbering, which the
        // reader reports as a missing middle segment.
        final next = a.segNo + 1;
        a.handle = await _fs.openWrite('${a.dir}/${_segName(next)}', append: true);
        a.segNo = next;
        a.segFrames = 0;
      }
      n += 1;
      await a.handle!.write(encodeFrame(a.cipher, p.build(n)));
      a.segFrames += 1;
      done += 1;
      if (a.segFrames >= kFramesPerSegment && !identical(p, last)) {
        await a.handle!.flush();
        await a.handle!.fsync();
        await _closeHandle(a);
        // Durable: advance the counter and prune per closed segment so a later
        // failure re-reads against the right frame numbers (review C14). Only
        // `a.pending` shrinks; the snapshot keeps its length.
        a.counter = n;
        a.pending.removeRange(0, done);
        done = 0;
      }
    }
    final h = a.handle;
    if (h != null) {
      await h.flush();
      await h.fsync();
    }
    a.counter = n;
    // Frames appended while this drain ran stay queued.
    a.pending.removeRange(0, done);
    if (a.segFrames >= kFramesPerSegment) await _closeHandle(a);
  }

  Future<void> _rotateAfterError(_Active a) async {
    final seg = a.suspectSeg!;
    final path = '${a.dir}/${_segName(seg)}';
    final scan = await _fs.exists(path)
        ? countValidFrames(a.cipher, await _fs.readBytes(path))
        : (frames: 0, lastCounter: a.counter);
    final onDisk = scan.lastCounter < a.counter ? a.counter : scan.lastCounter;
    var drop = onDisk - a.counter;
    while (drop > 0 && a.pending.isNotEmpty) {
      a.pending.removeAt(0);
      drop--;
    }
    a.counter = onDisk;
    a.pending.removeWhere((p) => p.isBreak);
    final off = a.lastOffset;
    final frames = scan.frames;
    a.pending.insert(
        0,
        _Pending((n) => eventPayload(n, 'segmentBreak', off, prevSegment: seg, prevFrames: frames),
            isBreak: true));
    a.suspectSeg = null;
    a.segFrames = 0;
  }

  // ------------------------------------------------------------ seal

  @override
  Future<void> seal(String recordingId, SealRequest request) =>
      _mutexFor(recordingId).run(() => _sealLocked(recordingId, request));

  Future<void> _sealLocked(String recordingId, SealRequest request) async {
        final s = await _needScope();
        final dir = '${s.recDir}/$recordingId';
        final meta = await _readMeta(s, recordingId);
        if (meta == null) throw const RecordingJournalError('unreadable');
        if (meta.scopeId != s.scopeId) throw const RecordingJournalError('ownerScopeLost');
        final a = _active;
        if (a != null && a.id == recordingId) {
          _closeBatch(a);
          await _drain(a);
          if (a.pending.isNotEmpty) {
            // The flush failed: detach so Start is not blocked; the data on
            // disk stays an unfinished recording (review C2).
            await _detach(a);
            throw const RecordingJournalError('flushFailed');
          }
          // `closed` is set under the lock before the final close (C11).
          await _detach(a);
        }
        if (await _fs.exists('$dir/$kSealedFile')) return; // idempotent
        final r = await _analyse(s, dir, startUtcMs: meta.startUtcMs);
        if (!r.readable) throw const RecordingJournalError('unreadable');
        var last = request.lastOffsetMs ?? r.lastOffsetMs;
        if (last < r.lastOffsetMs) last = r.lastOffsetMs;
        // importedAt is fixed here once and read back later, never recomputed.
        await _atomicWrite(
          '$dir/$kSealedFile',
          s.cipher!.seal(_utf(jsonEncode({
            'v': 1,
            'samples': r.sampleCount,
            'frames': r.frameCount,
            'last': last,
            'reason': request.reason.name,
            'imported': _now(),
            'lastSeg': r.lastSegment,
          }))),
        );
  }

  Future<Map<String, dynamic>?> _readSealed(_Scope s, String dir) async {
    final c = s.cipher;
    if (c == null) return null;
    final raw = await _readOpt('$dir/$kSealedFile');
    if (raw == null) return null;
    try {
      final m = jsonDecode(utf8.decode(c.open(raw)));
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ hand-off

  @override
  Future<HandOffResult> handOff(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        try {
          return await _handOffLocked(recordingId);
        } catch (_) {
          return HandOffResult.failedKept;
        }
      });

  Future<HandOffResult> _handOffLocked(String id) async {
    final s = await _scope();
    if (s == null) return HandOffResult.failedKept;
    final dir = '${s.recDir}/$id';
    final meta = await _readMeta(s, id);
    final sealed = await _readSealed(s, dir);
    if (meta == null || sealed == null || meta.scopeId != s.scopeId) {
      // A repeated call (double tap) after a completed hand-off: the recording
      // directory is gone and the activity with the deterministic id exists.
      // That is "done" (port contract: idempotent), not a failure the UI would
      // report as "could not save".
      if (!await _fs.exists(dir)) {
        final doneId = nativeActivityId(id);
        if ((await _activity.list()).any((e) => e.session.id == doneId)) {
          return HandOffResult.done;
        }
        if ((await _activity.listTombstones())
            .any((e) => e.session.id == doneId)) {
          return HandOffResult.tombstoned;
        }
      }
      return HandOffResult.failedKept;
    }
    final activityId = nativeActivityId(id);
    // "Exists" means VERIFIED (design 4.3 step 5): the stored entry reads back
    // with its streams. An entry that lost its streams is not a hand-off: the
    // recording is kept and the put is repeated from it.
    var existing = false;
    if ((await _activity.list()).any((e) => e.session.id == activityId)) {
      final stored = await _activity.read(activityId);
      existing = stored != null && !stored.streamLost && stored.streamsLoaded;
    }
    final tombstoned = (await _activity.listTombstones()).any((e) => e.session.id == activityId);
    if (!existing && !tombstoned) {
      final r = await _analyse(s, dir,
          track: true,
          metrics: true,
          startUtcMs: meta.startUtcMs,
          elapsed: sealed['last'] as int?);
      if (!r.readable ||
          r.sampleCount != sealed['samples'] ||
          r.frameCount != sealed['frames'] ||
          !r.metricsOk) {
        return HandOffResult.failedKept; // flagged or mismatching: never written clamped
      }
      final start = DateTime.fromMillisecondsSinceEpoch(meta.startUtcMs, isUtc: true);
      final streams = <StreamKind, SampleStream>{
        if (r.offsets!.isNotEmpty)
          StreamKind.gps: SampleStream.checked(
              kind: StreamKind.gps,
              sourceId: kNativeSourceId,
              offsetsMs: r.offsets!,
              lats: r.lats!,
              lons: r.lons!,
              accuracies: r.accuracies!),
        if (r.altOffsets!.isNotEmpty)
          StreamKind.altitude: SampleStream.checked(
              kind: StreamKind.altitude,
              sourceId: kNativeSourceId,
              offsetsMs: r.altOffsets!,
              values: r.alts!),
        if (r.spdOffsets!.isNotEmpty)
          StreamKind.speed: SampleStream.checked(
              kind: StreamKind.speed,
              sourceId: kNativeSourceId,
              offsetsMs: r.spdOffsets!,
              values: r.spds!),
      };
      final session = ActivitySession(
        id: activityId,
        sport: meta.sport,
        startUtc: start,
        endUtc: start.add(Duration(milliseconds: r.elapsedMs)),
        utcOffsetMinutes: meta.offsetMin,
        movingTimeS: r.movingTimeS,
        summary: ActivitySummary(
          distanceM: r.distanceM,
          ascentM: r.ascentM,
          descentM: r.descentM,
          avgSpeedMps: r.avgSpeedMps,
        ),
        streams: streams,
        provenance: [
          nativeSourceRecord(
            recordingUuid: id,
            importedAt: DateTime.fromMillisecondsSinceEpoch(
                (sealed['imported'] as int?) ?? meta.startUtcMs,
                isUtc: true),
            fieldsContributed: const ['gps'],
          ),
        ],
        formulaVersion: r.formulaVersion,
        metricDefinitionVersion: r.metricDefinitionVersion,
      );
      // Owner check immediately before the put (X2, ARCH1).
      final again = await _scope();
      if (again == null || again.scopeId != meta.scopeId) {
        return HandOffResult.failedKept;
      }
      if (_handOffCancelled?.call() ?? false) return HandOffResult.failedKept;
      try {
        // Owner check and write are ONE synchronous step in the scoped journal
        // (review S2); other journals fall back to the plain put.
        final act = _activity;
        if (act is OwnerCheckedPut) {
          await (act as OwnerCheckedPut).putForOwner(meta.uid, session);
        } else {
          await _activity.put(session);
        }
      } on JournalTombstonedException {
        // Deleted by the user meanwhile: delete wins; cleanup still runs.
      }
      final back = await _activity.read(activityId);
      final nowTomb =
          (await _activity.listTombstones()).any((e) => e.session.id == activityId);
      if (!nowTomb &&
          (back == null || back.streamLost || !back.streamsLoaded)) {
        return HandOffResult.failedKept;
      }
    }
    final fin = await _scope();
    final stillTombstoned =
        (await _activity.listTombstones()).any((e) => e.session.id == activityId);
    if (fin == null || fin.scopeId != meta.scopeId) {
      // activity exists; cleanup deferred, nothing written
      return stillTombstoned ? HandOffResult.tombstoned : HandOffResult.done;
    }
    try {
      await _cleanupVerified(s, id);
    } catch (_) {
      // The activity is verified: the hand-off is done. A leftover directory is
      // finished silently by the next recovery pass (review C9).
    }
    if (stillTombstoned) return HandOffResult.tombstoned;
    _onHandedOff?.call();
    return HandOffResult.done;
  }

  /// Recovery-time hand-off: a failing store (storage full, key unavailable)
  /// keeps the recording offered; it must never turn a healthy recording into
  /// an unreadable one.
  Future<HandOffResult> _tryHandOffLocked(String id) async {
    try {
      return await _handOffLocked(id);
    } catch (_) {
      return HandOffResult.failedKept;
    }
  }

  static bool _handOffComplete(HandOffResult r) =>
      r == HandOffResult.done || r == HandOffResult.tombstoned;

  /// KEEP / normal cleanup: ONE atomic rename, then content deletion (design
  /// 4.3 step 6).
  Future<void> _cleanupVerified(_Scope s, String id) async {
    final dir = '${s.recDir}/$id';
    final tomb = '$dir$kCleanupSuffix';
    if (await _fs.exists(dir)) {
      try {
        await _ops.renameDir(dir, tomb);
      } catch (_) {
        // A vanished directory (a concurrent cleanup) is already done.
        if (await _fs.exists(dir)) throw const RecordingJournalError('io');
      }
      await _ops.fsyncDir(s.recDir);
    }
    await _fs.deleteDir(tomb);
  }

  // ------------------------------------------------------------ decisions

  Future<String?> _readDecision(String dir) async {
    final path = '$dir/$kDecisionFile';
    if (!await _fs.exists(path)) return null;
    var raw = await _fs.readBytes(path);
    if (raw.isEmpty) {
      final id = dir.substring(dir.lastIndexOf('/') + 1);
      final w = _publishing[id];
      if (w != null) {
        await w.timeout(const Duration(milliseconds: kDecisionWaitMs), onTimeout: () {});
        raw = await _fs.readBytes(path);
      }
    }
    final t = utf8.decode(raw, allowMalformed: true);
    return (t == 'KEEP' || t == 'DELETE') ? t : 'INVALID';
  }

  /// Publishes `DECISION` whole: temp file + fsync + exclusive hard link, with
  /// the exclusive-create fallback only under the process-wide journal lock
  /// and the per-recording publication mutex (design 4.3, Z7, Z10, Z17).
  /// Returns the token that is durable afterwards.
  Future<String> _publishDecision(_Scope s, String id, String token) async {
    final dir = '${s.recDir}/$id';
    final target = '$dir/$kDecisionFile';
    final existing = await _readDecision(dir);
    if (existing != null) {
      if (existing == 'INVALID') throw const RecordingJournalError('decisionInProgress');
      return existing;
    }
    final tmp = '$dir/$kDecisionFile.${math.Random.secure().nextInt(1 << 30)}$kTempSuffix';
    final bytes = _utf(token);
    final done = Completer<void>();
    _publishing[id] = done.future;
    try {
      final h = await _fs.openWrite(tmp);
      try {
        await h.write(bytes);
        await h.flush();
        await h.fsync();
      } finally {
        await h.close();
      }
      var outcome = await _ops.linkExclusive(tmp, target);
      if (outcome == LinkOutcome.unsupported) {
        // Without hard links: publish by rename of the already durable temp
        // file, only while the target is absent, under the process lock and the
        // per-recording mutex. No empty DECISION window exists (review C6).
        if (!_locks.containsKey(s.scopeId)) throw const RecordingJournalError('lockMissing');
        if (await _fs.exists(target)) {
          outcome = LinkOutcome.exists;
        } else {
          await _fs.rename(tmp, target);
          outcome = LinkOutcome.created;
        }
      }
      await _ops.fsyncDir(dir);
      try {
        await _fs.deleteFile(tmp);
      } catch (_) {}
      if (outcome == LinkOutcome.created) return token;
      return (await _readDecision(dir)) ?? token;
    } finally {
      done.complete();
      _publishing.remove(id);
    }
  }

  @override
  Future<DecisionOutcome> decideKeep(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        final s = await _needScope();
        final got = await _publishDecision(s, recordingId, 'KEEP');
        return got == 'KEEP' ? DecisionOutcome.committed : DecisionOutcome.alreadyDecided;
      });

  @override
  Future<DecisionOutcome> decideDelete(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        final s = await _needScope();
        final got = await _publishDecision(s, recordingId, 'DELETE');
        if (got != 'DELETE') return DecisionOutcome.alreadyDecided;
        final a = _active;
        if (a != null && a.id == recordingId) await _detach(a);
        await _executeDelete(s, recordingId);
        return DecisionOutcome.committed;
      });

  /// Ordered delete (design 4.5): DISCARDING (plain), segments, SEALED and
  /// markers, meta.json LAST, then the directory. Only after a durable
  /// `DECISION=DELETE`.
  Future<void> _executeDelete(_Scope s, String id) =>
      _executeDeleteAt('${s.recDir}/$id');

  Future<void> _executeDeleteAt(String dir) async {
    if (!await _fs.exists('$dir/$kDiscardingFile')) {
      await _atomicWrite('$dir/$kDiscardingFile', _utf('1'));
    }
    for (final n in await _segments(dir)) {
      await _fs.deleteFile('$dir/${_segName(n)}');
    }
    for (final f in [kSealedFile, kQuarantinedFile, kFallbackFile]) {
      await _fs.deleteFile('$dir/$f');
    }
    await _fs.deleteFile('$dir/$kMetaFile');
    await _fs.deleteDir(dir);
  }

  @override
  Future<void> quarantine(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        final s = await _needScope();
        await _writeQuarantine(s, '${s.recDir}/$recordingId');
      });

  Future<void> _writeQuarantine(_Scope s, String dir) async {
    if (await _fs.exists('$dir/$kQuarantinedFile')) return;
    final body = _utf(jsonEncode({'q': _now()}));
    Uint8List out;
    try {
      out = s.cipher != null ? s.cipher!.seal(body) : _utf('${_now()}');
    } catch (_) {
      out = _utf('${_now()}');
    }
    await _atomicWrite('$dir/$kQuarantinedFile', out);
  }

  /// The age reference of a marker: the LATER of the time written inside and
  /// the file's modification time, so a wall-clock jump alone cannot expire a
  /// recording (review C12).
  Future<int?> _markerTime(_Scope? s, String dir, String name) async {
    int? inside;
    try {
      final raw = await _readOpt('$dir/$name');
      if (raw == null) return null;
      try {
        final m = jsonDecode(utf8.decode(s!.cipher!.open(raw)));
        if (m is Map && m['q'] is int) inside = m['q'] as int;
      } catch (_) {}
      inside ??= int.tryParse(utf8.decode(raw, allowMalformed: true));
    } catch (_) {}
    int? mtime;
    try {
      mtime = (await _fs.modified('$dir/$name'))?.millisecondsSinceEpoch;
    } catch (_) {}
    if (inside != null && mtime != null) return math.max(inside, mtime);
    return inside ?? mtime ?? _now();
  }

  bool _expired(int markerMs) => _now() - markerMs >= kRecordingExpiryMs;

  /// Expiry delete: a direct ordered delete, never a DECISION publication
  /// (review C5); content-free log.
  Future<void> _expireDelete(_Scope s, String id) async {
    await _executeDelete(s, id);
  }

  // ------------------------------------------------------------ recovery

  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    final s = await _scope();
    if (s == null) return const [];
    final out = <UnfinishedRecording>[];
    final entries = await _fs.list(s.recDir);
    for (final e in entries) {
      if (e.isDirectory && e.name.endsWith(kCleanupSuffix)) {
        // Garbage of a verified KEEP or a completed DELETE: no checks at all.
        // Under the per-recording mutex so it cannot race a KEEP cleanup (C10).
        final id = e.name.substring(0, e.name.length - kCleanupSuffix.length);
        try {
          await _mutexFor(id)
              .run(() => _fs.deleteDir('${s.recDir}/${e.name}'));
        } catch (_) {}
      }
    }
    for (final e in entries) {
      if (!e.isDirectory || e.name.endsWith(kCleanupSuffix)) continue;
      if (!kJournalIdPattern.hasMatch(e.name)) continue;
      if (_isActive(e.name)) continue;
      try {
        final u = await _mutexFor(e.name).run(() => _recoverOne(s, e.name));
        if (u != null) out.add(u);
      } catch (_) {
        // Could not be read NOW (I/O, key store): retryable, never quarantined
        // and never expired (review C3).
        out.add(UnfinishedRecording(
            recordingId: e.name, status: UnfinishedStatus.unavailable));
      }
    }
    return out;
  }

  static StopReason? _stopReasonOfEvent(String? event) => switch (event) {
        'stoppedBattery' => StopReason.battery,
        'stoppedStorage' => StopReason.storage,
        'stoppedAccount' => StopReason.account,
        'stoppedConsent' => StopReason.consentWithdrawn,
        'stoppedCap' => StopReason.sampleCap,
        'permissionRevoked' => StopReason.permissionRevoked,
        _ => null,
      };

  Future<UnfinishedRecording?> _quarantinedOrExpired(
      _Scope s, String id, String dir) async {
    final t = await _markerTime(s, dir, kQuarantinedFile) ?? _now();
    if (_expired(t)) {
      await _expireDelete(s, id);
      return null;
    }
    return UnfinishedRecording(
        recordingId: id, status: UnfinishedStatus.quarantined);
  }

  Future<UnfinishedRecording?> _recoverOne(_Scope s, String id) async {
    final dir = '${s.recDir}/$id';
    final decision = await _readDecision(dir);
    final discarding = await _fs.exists('$dir/$kDiscardingFile');

    if (decision == 'INVALID' ||
        (decision == 'KEEP' && discarding) ||
        (discarding && decision != 'DELETE')) {
      await _writeQuarantine(s, dir); // no delete, no hand-off
      // The 30-day expiry applies here too (review C5): a direct ordered delete,
      // never a DELETE publication over an invalid decision.
      return _quarantinedOrExpired(s, id, dir);
    }
    if (decision == 'DELETE') {
      await _executeDelete(s, id);
      return null;
    }
    final meta = await _readMeta(s, id);
    if (meta != null && meta.scopeId != s.scopeId) return null; // never offered
    if (decision == 'KEEP') {
      if (_handOffComplete(await _tryHandOffLocked(id))) return null;
      return UnfinishedRecording(recordingId: id, status: UnfinishedStatus.readable);
    }
    if (await _fs.exists('$dir/$kQuarantinedFile')) {
      return _quarantinedOrExpired(s, id, dir);
    }
    // FALLBACK expiry runs BEFORE the meta check: an unreadable FALLBACK
    // recording must still expire (review C12).
    if (await _fs.exists('$dir/$kFallbackFile')) {
      final t = await _markerTime(s, dir, kFallbackFile) ?? _now();
      if (_expired(t)) {
        await _expireDelete(s, id);
        return null;
      }
    }
    if (meta == null) {
      return UnfinishedRecording(recordingId: id, status: UnfinishedStatus.unreadable);
    }
    var sealed = await _readSealed(s, dir);
    var isSealed = await _fs.exists('$dir/$kSealedFile');
    final r = await _analyse(s, dir, metrics: true, startUtcMs: meta.startUtcMs);
    if (r.damage == Damage.unavailable) {
      return UnfinishedRecording(recordingId: id, status: UnfinishedStatus.unavailable);
    }
    if (!r.readable || (isSealed && sealed == null)) {
      return UnfinishedRecording(recordingId: id, status: UnfinishedStatus.unreadable);
    }
    if (isSealed &&
        (sealed!['samples'] != r.sampleCount || sealed['frames'] != r.frameCount)) {
      return UnfinishedRecording(recordingId: id, status: UnfinishedStatus.unreadable);
    }
    if (r.sampleCount == 0) {
      // Readable but empty: silent delete through the same ordered path.
      await _publishDecision(s, id, 'DELETE');
      await _executeDelete(s, id);
      return null;
    }
    if (!isSealed) {
      // Killed between the stop event and SEALED: seal with that stop reason
      // (design 4.3 step 2, review C15).
      final reason = _stopReasonOfEvent(r.lastEvent);
      if (reason != null) {
        await _sealLocked(id, SealRequest(reason: reason));
        sealed = await _readSealed(s, dir);
        isSealed = sealed != null;
      }
    }
    if (isSealed && sealed!['reason'] != StopReason.permissionRevoked.name) {
      // Killed between SEALED and the end of the hand-off: finish silently.
      if (_handOffComplete(await _tryHandOffLocked(id))) return null;
    }
    return UnfinishedRecording(
      recordingId: id,
      status: UnfinishedStatus.readable,
      startUtcMs: meta.startUtcMs,
      sport: meta.sport,
      lastOffsetMs: r.lastOffsetMs,
      sampleCount: r.sampleCount,
      distanceM: r.metricsOk ? r.distanceM : null,
      movingTimeMs: r.metricsOk ? (r.movingTimeS * 1000).round() : null,
      pendingDecision:
          isSealed && sealed!['reason'] == StopReason.permissionRevoked.name,
    );
  }

  @override
  Future<RecoveredRecording> openForResume(String recordingId) =>
      _mutexFor(recordingId).run(() async {
        if (_active != null) throw const RecordingJournalError('alreadyActive');
        final s = await _needScope();
        final dir = '${s.recDir}/$recordingId';
        final meta = await _readMeta(s, recordingId);
        if (meta == null || meta.scopeId != s.scopeId) {
          throw const RecordingJournalError('unreadable');
        }
        if (await _fs.exists('$dir/$kSealedFile') ||
            await _fs.exists('$dir/$kDecisionFile') ||
            await _fs.exists('$dir/$kQuarantinedFile')) {
          throw const RecordingJournalError('notResumable');
        }
        final r = await _analyse(s, dir,
            metrics: true, startUtcMs: meta.startUtcMs);
        if (!r.readable) throw const RecordingJournalError('unreadable');
        final a = _Active(recordingId, s.scopeId, s.uid, s.cipher!, dir)
          ..counter = r.frameCount
          ..segNo = r.lastSegment
          ..lastOffset = r.lastOffsetMs;
        final restartAt = math.max(_now() - meta.startUtcMs, r.lastOffsetMs);
        final prevSeg = r.lastSegment;
        final prevFrames = r.lastSegmentFrames;
        final last = r.lastOffsetMs;
        a.pending
          ..add(_Pending((n) => eventPayload(n, 'segmentBreak', last,
              prevSegment: prevSeg, prevFrames: prevFrames), isBreak: true))
          ..add(_Pending((n) => eventPayload(n, 'restart', restartAt)))
          ..add(_Pending((n) => eventPayload(n, 'gapStart', last)))
          ..add(_Pending((n) => eventPayload(n, 'gapEnd', restartAt)));
        a.lastOffset = restartAt;
        _activate(a);
        await _drain(a);
        if (a.pending.isNotEmpty) {
          await _detach(a);
          throw const RecordingJournalError('flushFailed');
        }
        return RecoveredRecording(
          meta: meta.toPort(),
          lastOffsetMs: last,
          distanceM: r.distanceM,
          movingTimeMs: (r.movingTimeS * 1000).round(),
          keptCount: r.sampleCount,
        );
      });

  // ------------------------------------------------------------ account events

  /// Step 1 of the pre-unbind hook (review C4): the cheap 30-day `FALLBACK`
  /// marker for EVERY remaining recording of [ownerUid] (also the ones the slow
  /// seal skips: pending decisions, KEEP decisions). A recording that is handed
  /// off afterwards disappears with its directory; one that is not keeps its
  /// expiry. Returns the number of recordings marked.
  Future<int> markFallbackForOwner(String ownerUid) async {
    final s = await _scope();
    if (s == null || s.uid != ownerUid) return 0;
    var marked = 0;
    final ids = <String>{if (_active != null) _active!.id};
    for (final e in await _fs.list(s.recDir)) {
      if (e.isDirectory &&
          !e.name.endsWith(kCleanupSuffix) &&
          kJournalIdPattern.hasMatch(e.name)) {
        ids.add(e.name);
      }
    }
    for (final id in ids) {
      final dir = '${s.recDir}/$id';
      try {
        if (!await _fs.exists(dir)) continue;
        if (await _fs.exists('$dir/$kQuarantinedFile')) continue;
        if (!await _fs.exists('$dir/$kFallbackFile')) {
          await _atomicWrite('$dir/$kFallbackFile', _utf('${_now()}'));
        }
        marked++;
      } catch (_) {}
    }
    return marked;
  }

  /// Recordings of the bound scope that wait under a `FALLBACK` marker. The
  /// markers are on disk, so the next launch of the account can show the notice
  /// even when the hook outcome was discarded (review S6).
  Future<int> fallbackCount() async {
    final s = await _scope();
    if (s == null) return 0;
    var n = 0;
    for (final e in await _fs.list(s.recDir)) {
      if (e.isDirectory &&
          !e.name.endsWith(kCleanupSuffix) &&
          await _fs.exists('${s.recDir}/${e.name}/$kFallbackFile')) {
        n++;
      }
    }
    return n;
  }

  /// App-start sweep (review S1, C4): deletes expired `FALLBACK` and
  /// `QUARANTINED` recordings of EVERY scope under the scopes root, whichever
  /// uid is bound. Needs no key: the marker time is read as plain text with the
  /// file modification time as the other reference, and the delete is the
  /// ordered file delete. The active recording is never touched.
  ///
  /// A scope this instance owns (it holds that scope's process-wide lock) is
  /// swept under the per-recording mutex. A foreign scope is swept only while
  /// this call holds that scope's own process-wide lock file
  /// (`recording.lock`, the same mechanism as [_acquireScopeLock]); when the
  /// lock cannot be taken (another instance or process holds it) the scope is
  /// skipped and retried on the next start.
  Future<int> sweepExpiredAllScopes() async {
    final base = await _scopesRoot();
    var removed = 0;
    for (final scope in await _fs.list(base)) {
      if (!scope.isDirectory) continue;
      final recDir = '$base/${scope.name}/$kRecordingDirName';
      final candidates = <String>[
        for (final e in await _fs.list(recDir))
          if (e.isDirectory &&
              !e.name.endsWith(kCleanupSuffix) &&
              kJournalIdPattern.hasMatch(e.name))
            e.name,
      ];
      if (candidates.isEmpty) continue;

      // A first acquisition of this scope may be in flight: let it finish so
      // this call does not race it for the same lock file.
      final pending = _lockFutures[scope.name];
      if (pending != null) {
        try {
          await pending;
        } catch (_) {}
      }
      Object? foreignLock;
      if (!_locks.containsKey(scope.name)) {
        try {
          foreignLock = await _ops.acquireLock('$recDir/$kRecordingLockFile');
        } catch (_) {
          continue; // held elsewhere (or unavailable): retry on the next start
        }
      }
      try {
        for (final id in candidates) {
          if (_isActive(id)) continue;
          final dir = '$recDir/$id';
          try {
            final done = await _mutexFor(id).run(() async {
              for (final marker in [kQuarantinedFile, kFallbackFile]) {
                if (!await _fs.exists('$dir/$marker')) continue;
                final t = await _markerTime(null, dir, marker) ?? _now();
                if (!_expired(t)) continue;
                await _executeDeleteAt(dir);
                return true;
              }
              return false;
            });
            if (done) removed++;
          } catch (_) {}
        }
      } finally {
        if (foreignLock != null) {
          try {
            await _ops.releaseLock(foreignLock);
          } catch (_) {}
        }
      }
    }
    return removed;
  }

  /// Strict path of the pre-unbind hook (design 4.7): seal and hand off every
  /// unfinished recording of [ownerUid]; whatever cannot be handed off stays
  /// ENCRYPTED in its scope under the 30-day `FALLBACK` marker. [cancelled] is
  /// polled between steps and inside the hand-off so a timed-out hook stops
  /// (review C4, S2).
  Future<FinishAllReport> finishAllForOwner(String ownerUid,
      {bool Function()? cancelled}) async {
    final s = await _scope();
    if (s == null || s.uid != ownerUid) return const FinishAllReport(0, 0);
    var ok = 0, kept = 0;
    final a = _active;
    final ids = <String>{if (a != null) a.id};
    for (final e in await _fs.list(s.recDir)) {
      if (e.isDirectory &&
          !e.name.endsWith(kCleanupSuffix) &&
          kJournalIdPattern.hasMatch(e.name)) {
        ids.add(e.name);
      }
    }
    final previous = _handOffCancelled;
    _handOffCancelled = cancelled;
    try {
      for (final id in ids) {
        if (cancelled?.call() ?? false) break;
        final dir = '${s.recDir}/$id';
        try {
          if (await _fs.exists('$dir/$kDecisionFile') ||
              await _fs.exists('$dir/$kQuarantinedFile')) {
            if (await _fs.exists('$dir/$kFallbackFile')) kept++;
            continue;
          }
          final sealed = await _readSealed(s, dir);
          if (sealed != null &&
              sealed['reason'] == StopReason.permissionRevoked.name) {
            if (await _fs.exists('$dir/$kFallbackFile')) kept++;
            continue; // pending decision of the user: stays as is
          }
          await seal(id, const SealRequest(reason: StopReason.account));
          if (cancelled?.call() ?? false) break;
          if (_handOffComplete(await handOff(id))) {
            ok++;
            continue;
          }
        } catch (_) {}
        kept++;
        try {
          if (await _fs.exists(dir) && !await _fs.exists('$dir/$kFallbackFile')) {
            await _atomicWrite('$dir/$kFallbackFile', _utf('${_now()}'));
          }
        } catch (_) {}
      }
    } finally {
      _handOffCancelled = previous;
    }
    return FinishAllReport(ok, kept);
  }
}

/// The recorder-facing pre-unbind hook: writes the cheap FALLBACK markers
/// first, shuts the recorder down through [shutdownRecorder] (which awaits an
/// in-flight stop), then runs the strict path. Cooperative: after
/// [cancel] (the registry calls it on a timeout) no further step starts.
class RecordingPreUnbindHook implements PreUnbindHook, CancellablePreUnbindHook {
  RecordingPreUnbindHook({
    required this.journal,
    required this.shutdownRecorder,
    this.onFallbackKept,
  });

  final FileRecordingJournal journal;
  final Future<void> Function() shutdownRecorder;

  /// Called with the number of recordings left in the 30-day fallback so the
  /// sign-out UI can tell the user (S04-30 AC-3).
  final void Function(int kept)? onFallbackKept;

  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  Future<void> run(String ownerUid, UnbindReason reason) async {
    _cancelled = false;
    if (reason != UnbindReason.accountDeleted) {
      try {
        await journal.markFallbackForOwner(ownerUid);
      } catch (_) {}
    }
    await shutdownRecorder();
    if (reason == UnbindReason.accountDeleted || _cancelled) return;
    final r = await journal.finishAllForOwner(ownerUid, cancelled: () => _cancelled);
    if (r.keptInFallback > 0) onFallbackKept?.call(r.keptInFallback);
  }
}
