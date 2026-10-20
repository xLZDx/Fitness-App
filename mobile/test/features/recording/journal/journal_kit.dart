// Shared test kit of the S04 recording-journal tests (group EP_D). Test-only.
//
// One [RecKit] = one "device": an in-memory file system, a fault-injecting
// wrapper, a recording of the file-ops seam, a real S02 FileActivityJournal on
// the same memory file system, per-scope in-memory keys (the "secure store",
// which survives a kill) and the journal under test. [RecKit.kill] simulates a
// process death: the old journal object is dropped without any flush and a NEW
// set of objects is opened over the SAME bytes.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'dart:io' show FileSystemException, OSError;

import 'package:fitness_app/features/activity/repository/journal_file_system.dart';
import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart'
    show activityJournalScopeId;
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/journal/recording_codec.dart';
import 'package:fitness_app/features/recording/journal/recording_file_ops.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart' show FakeClock, fixedJournalKey;

/// Sentinel coordinates of the privacy rows (plan F-sentinel).
const double kSentinelLat = 12.3456789;
const double kSentinelLon = -98.7654321;

/// 36-char style recording ids (the pattern allows `[A-Za-z0-9_-]{1,64}`).
String recId(int n) => 'rec-${n.toString().padLeft(4, '0')}';

/// A deterministic kept sample at second [i] (about 3.3 m per second).
PipelineSample smp(int i, {bool alt = true, bool spd = true}) => PipelineSample(
      offsetMs: i * 1000,
      lat: 47.0 + i * 0.00003,
      lon: 8.0 + i * 0.00002,
      accuracyM: 5.0,
      altitudeM: alt ? 400.0 + i * 0.1 : null,
      speedMps: spd ? 3.0 : null,
    );

RecordingMeta metaFor(
  String id, {
  required String uid,
  required int startUtcMs,
  SportType sport = SportType.running,
}) =>
    RecordingMeta(
      recordingId: id,
      startUtcMs: startUtcMs,
      utcOffsetMinutes: 60,
      sport: sport,
      autoPauseEnabled: true,
      ownerUid: uid,
    );

/// In-memory implementation of the extra file-ops seam over the shared memory
/// file system. Supports exclusive hard-link publish (switchable), exclusive
/// create, directory rename and the process-wide lock; logs every call.
class MemRecordingOps implements RecordingFileOps {
  MemRecordingOps(this.mem, this.mark, {this.fsDead});

  final MemoryJournalFileSystem mem;
  final void Function(String) mark;
  final bool Function()? fsDead;

  /// Awaited inside linkExclusive AFTER the temp file is durable and BEFORE the
  /// link is made (the barrier of the two-writer interleaving rows).
  Future<void> Function()? beforeLink;

  /// Fallback path: after the empty DECISION file exists and before its
  /// content is written (the window an unmutexed reader could see).
  Future<void> Function()? afterEmptyCreate;

  /// Dies right AFTER the first call whose log line starts with this prefix.
  String? crashAfterPrefix;
  bool dead = false;

  void _done(String line) {
    mark(line);
    final p = crashAfterPrefix;
    if (p != null && line.startsWith(p)) {
      dead = true;
      crashAfterPrefix = null;
      throw SimulatedCrash(line);
    }
  }

  bool linkSupported = true;
  int fsyncDirCalls = 0;
  Object? renameDirError;
  final Set<String> _held = {};

  void _alive() {
    if (dead || (fsDead?.call() ?? false)) throw SimulatedCrash('ops after crash');
  }

  @override
  Future<LinkOutcome> linkExclusive(String from, String to) async {
    _alive();
    if (!linkSupported) {
      mark('ops.link-unsupported $to');
      return LinkOutcome.unsupported;
    }
    final gate = beforeLink;
    if (gate != null) await gate();
    final parent = to.substring(0, to.lastIndexOf('/'));
    if (!mem.dirs.contains(parent)) {
      throw FileSystemExceptionLike('link target directory missing');
    }
    if (mem.files.containsKey(to)) {
      mark('ops.link-exists $to');
      return LinkOutcome.exists;
    }
    mem.files[to] = Uint8List.fromList(mem.files[from]!);
    _done('ops.link $from -> $to');
    return LinkOutcome.created;
  }

  @override
  Future<bool> createExclusive(String path, Uint8List bytes) async {
    _alive();
    if (mem.files.containsKey(path)) {
      mark('ops.createExclusive-exists $path');
      return false;
    }
    final pause = afterEmptyCreate;
    if (pause != null) {
      mem.files[path] = Uint8List(0);
      await pause();
    }
    mem.files[path] = Uint8List.fromList(bytes);
    _done('ops.createExclusive $path');
    return true;
  }

  @override
  Future<void> renameDir(String from, String to) async {
    _alive();
    if (renameDirError != null) throw renameDirError!;
    final prefix = '$from/';
    final moves = <String, Uint8List>{
      for (final e in mem.files.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
    for (final e in moves.entries) {
      mem.files.remove(e.key);
      mem.files['$to/${e.key.substring(prefix.length)}'] = e.value;
    }
    final dirs = mem.dirs.where((d) => d == from || d.startsWith(prefix)).toList();
    for (final d in dirs) {
      mem.dirs.remove(d);
      mem.dirs.add(d == from ? to : '$to/${d.substring(prefix.length)}');
    }
    _done('ops.renameDir $from -> $to');
  }

  @override
  Future<void> fsyncDir(String path) async {
    _alive();
    fsyncDirCalls++;
    _done('ops.fsyncDir $path');
  }

  @override
  Future<Object> acquireLock(String path) async {
    _alive();
    if (_held.contains(path)) throw const FileSystemExceptionLike('lock held');
    _held.add(path);
    return path;
  }

  @override
  Future<void> releaseLock(Object handle) async {
    _held.remove(handle);
  }
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike(this.message);
  final String message;
}

/// Activity journal wrapper: forwards to a real journal and exposes hooks so a
/// test can fail or "crash" around the put and record the call order.
class HookedActivity extends Fake implements ActivityJournal {
  HookedActivity(this.inner, this.mark);

  final ActivityJournal inner;
  final void Function(String) mark;

  Object? putError;
  Object? crashBeforePut;
  Object? crashAfterPut;
  Completer<void>? putGate;
  Object? readError;
  bool readAbsent = false;
  int puts = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  ActivitySession? lastPut;

  @override
  Future<JournalEntry> put(ActivitySession session,
      {JournalSyncState? syncState,
      int? baseRev,
      Map<String, Object?>? baseSummary}) async {
    puts++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      mark('activity.put');
      if (crashBeforePut != null) throw crashBeforePut!;
      if (putGate != null) await putGate!.future;
      if (putError != null) throw putError!;
      lastPut = session;
      final r = await inner.put(session,
          syncState: syncState, baseRev: baseRev, baseSummary: baseSummary);
      if (crashAfterPut != null) throw crashAfterPut!;
      return r;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<JournalEntry?> read(String id) async {
    mark('activity.read');
    if (readError != null) throw readError!;
    if (readAbsent) return null;
    return inner.read(id);
  }

  @override
  Future<List<JournalEntry>> list() => inner.list();

  @override
  Future<List<JournalEntry>> listTombstones() => inner.listTombstones();

  @override
  Future<void> delete(String id) => inner.delete(id);
}

/// One simulated device.
class RecKit {
  RecKit._(this.uid) : clock = FakeClock(DateTime.utc(2026, 10, 17, 8));

  static const String scopesRoot = '/scopes';
  static int _n = 0;
  final String _actRoot = '/act${_n++}';

  String? uid;
  final FakeClock clock;
  late final MemoryJournalFileSystem mem = MemoryJournalFileSystem(clock.call);
  final Map<String, InMemoryJournalKeyProvider> keys = {};
  final List<String> log = [];

  late GatedFs fs;
  late MemRecordingOps ops;
  late FileActivityJournal activityReal;
  late HookedActivity activity;
  late InlineHeavyWorkRunner runner;
  late InlineHeavyWorkRunner activityRunner;

  /// Replaces the heavy-work runner of the journal on the NEXT open/kill.
  HeavyWorkRunner? runnerOverride;
  late FileRecordingJournal journal;
  final List<int> handedOff = [];
  int get handedOffCount => handedOff.length;
  final List<JournalFault> faults = [];
  StreamSubscription<JournalFault>? _sub;

  /// Key provider factory used by the journal; tests can swap entries.
  JournalKeyProvider Function(String scopeId)? keyOverride;

  static Future<RecKit> create({String? uid = 'user-a'}) async {
    final k = RecKit._(uid);
    await k._open();
    return k;
  }

  int get nowMs => clock.now.millisecondsSinceEpoch;
  String get scopeId => activityJournalScopeId(uid!);
  String scopeIdOf(String u) => activityJournalScopeId(u);
  String get recDir => '$scopesRoot/$scopeId/$kRecordingDirName';
  String recDirOf(String u) => '$scopesRoot/${scopeIdOf(u)}/$kRecordingDirName';
  String dirOf(String id) => '$recDir/$id';

  JournalKeyProvider _keyFor(String scopeId) =>
      keyOverride?.call(scopeId) ??
      keys.putIfAbsent(
          scopeId,
          () => InMemoryJournalKeyProvider(
              fixedJournalKey(scopeId.codeUnitAt(0) + scopeId.codeUnitAt(1))));

  Future<void> _open({DateTime Function()? clk}) async {
    log.clear();
    fs = GatedFs(mem);
    void mark(String m) {
      log.add(m);
      fs.note(m);
    }

    ops = MemRecordingOps(mem, mark, fsDead: () => fs.dead);
    activityRunner = InlineHeavyWorkRunner();
    activityReal = FileActivityJournal(
      rootPath: _actRoot,
      fileSystem: mem,
      keyProvider: InMemoryJournalKeyProvider(fixedJournalKey(9)),
      clock: clock.call,
      heavyWorkRunner: activityRunner,
      workerMinSamples: 1,
    );
    await activityReal.start();
    activity = HookedActivity(activityReal, mark);
    runner = InlineHeavyWorkRunner();
    journal = FileRecordingJournal(
      activity: activity,
      boundUid: () => uid,
      scopesRoot: () async => scopesRoot,
      keyProviderFor: _keyFor,
      fileSystem: fs,
      fileOps: ops,
      runner: runnerOverride ?? runner,
      nowUtcMs: () => nowMs,
      onHandedOff: () => handedOff.add(nowMs),
    );
    faults.clear();
    unawaited(_sub?.cancel());
    _sub = journal.faults.listen(faults.add);
  }

  /// Simulates a process death and a restart: nothing is flushed, the old
  /// objects are abandoned, NEW objects are opened over the same bytes.
  Future<void> kill() async {
    final old = journal;
    final oldAct = activityReal;
    // Cancels the flush timer without writing (closeScope never drains).
    try {
      await old.closeScope(uid == null ? '' : scopeId);
    } catch (_) {}
    try {
      await oldAct.close();
    } catch (_) {}
    await _open();

  }

  /// A restart that keeps the same fault-wrapper dead flag cleared (alias).
  Future<void> restart() => kill();

  Future<void> dispose() async {
    unawaited(_sub?.cancel());
    try {
      await journal.closeScope(uid == null ? '' : scopeId);
    } catch (_) {}
    try {
      await activityReal.close();
    } catch (_) {}
  }

  RecordingMeta meta(String id, {SportType sport = SportType.running}) =>
      metaFor(id, uid: uid!, startUtcMs: nowMs, sport: sport);

  /// begin + enqueue [count] samples (seconds 1..count) + a flush.
  Future<void> record(String id, int count,
      {bool flush = true, int from = 1}) async {
    await journal.begin(meta(id));
    for (var i = from; i < from + count; i++) {
      journal.enqueueSample(smp(i), GateCounters.zero);
    }
    if (flush) await journal.flush();
  }

  // ---- raw file helpers -------------------------------------------------

  Uint8List? bytesOf(String path) => mem.files[path];

  List<String> filesOf(String id) {
    final p = '${dirOf(id)}/';
    return [
      for (final f in mem.files.keys)
        if (f.startsWith(p)) f.substring(p.length)
    ]..sort();
  }

  String segPath(String id, int n) =>
      '${dirOf(id)}/seg-${n.toString().padLeft(4, '0')}.log';

  /// Hash-like snapshot of every byte under the recording directory.
  Map<String, String> snapshot(String id) {
    final p = '${dirOf(id)}/';
    return {
      for (final e in mem.files.entries)
        if (e.key.startsWith(p)) e.key: base64Encode(e.value)
    };
  }

  /// Every file under the whole `recording/` tree of the bound scope.
  List<String> treeFiles() => [
        for (final f in mem.files.keys)
          if (f.startsWith(recDir)) f
      ]..sort();

  Uint8List keyBytes([String? scope]) {
    final s = scope ?? scopeId;
    return fixedJournalKey(s.codeUnitAt(0) + s.codeUnitAt(1));
  }

  AesGcmJournalCipher cipher([String? scope]) {
    final s = scope ?? scopeId;
    return AesGcmJournalCipher(
        fixedJournalKey(s.codeUnitAt(0) + s.codeUnitAt(1)));
  }

  /// Decrypts every frame of segment [n] (test oracle independent of the
  /// journal's own reader): returns the plain JSON maps.
  List<Map<String, dynamic>> frames(String id, int n, {String? scope}) {
    final b = bytesOf(segPath(id, n))!;
    final bd = ByteData.sublistView(b);
    final c = cipher(scope);
    final out = <Map<String, dynamic>>[];
    var pos = 0;
    while (b.length - pos >= kFrameHeaderBytes) {
      final len = bd.getUint32(pos);
      if (pos + kFrameHeaderBytes + len > b.length) break;
      final sealed = Uint8List.sublistView(
          b, pos + kFrameHeaderBytes, pos + kFrameHeaderBytes + len);
      out.add(jsonDecode(utf8.decode(c.open(sealed))) as Map<String, dynamic>);
      pos += kFrameHeaderBytes + len;
    }
    return out;
  }

  List<String> segNames(String id) => [
        for (final f in filesOf(id))
          if (RegExp(r'^seg-\d{4}\.log$').hasMatch(f)) f
      ];

  /// Number of kept samples visible to an independent decode of all segments.
  int sampleCountOnDisk(String id) {
    var n = 0;
    for (var s = 1; s <= segNames(id).length; s++) {
      for (final f in frames(id, s)) {
        if (f['k'] == 's') n += (f['t'] as List).length;
      }
    }
    return n;
  }

  /// Rewrites a file in place (bypasses the fault wrapper).
  void put(String path, List<int> data) {
    mem.files[path] = Uint8List.fromList(data);
  }

  /// Drops the process' own handle state and reopens only the journal object
  /// (same fs wrapper, same ops): "the app was restarted in the same process".
  FileRecordingJournal secondJournal() => FileRecordingJournal(
        activity: activity,
        boundUid: () => uid,
        scopesRoot: () async => scopesRoot,
        keyProviderFor: _keyFor,
        fileSystem: fs,
        fileOps: ops,
        runner: runner,
        nowUtcMs: () => nowMs,
      );

  /// A second journal object with its OWN process lock set: the in-process
  /// mutexes and the lock are bypassed so the file arbitration stands alone.
  (FileRecordingJournal, MemRecordingOps) journalWithOwnOps() {
    final o = MemRecordingOps(mem, (m) {
      log.add(m);
      fs.note(m);
    }, fsDead: () => fs.dead);
    final j = FileRecordingJournal(
      activity: activity,
      boundUid: () => uid,
      scopesRoot: () async => scopesRoot,
      keyProviderFor: _keyFor,
      fileSystem: fs,
      fileOps: o,
      runner: runner,
      nowUtcMs: () => nowMs,
    );
    return (j, o);
  }

  Future<List<UnfinishedRecording>> unfinished() => journal.listUnfinished();

  /// Seal + hand-off as the recorder's Stop does.
  Future<HandOffResult> finish(String id,
      {StopReason reason = StopReason.user, int? lastOffsetMs}) async {
    await journal.seal(id, SealRequest(reason: reason, lastOffsetMs: lastOffsetMs));
    return journal.handOff(id);
  }
}

/// Drives an async call to completion inside a [FakeAsync] zone. All journal
/// I/O is microtask based, so one flush completes it.
T settle<T>(FakeAsync fa, Future<T> f) {
  T? value;
  Object? err;
  StackTrace? st;
  var done = false;
  f.then((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    err = e;
    st = s;
    done = true;
  });
  fa.flushMicrotasks();
  for (var i = 0; i < 20 && !done; i++) {
    fa.elapse(Duration.zero); // zero-length timers (stream plumbing)
    fa.flushMicrotasks();
  }
  if (err != null) Error.throwWithStackTrace(err!, st!);
  expect(done, isTrue, reason: 'future did not complete under fake time');
  return value as T;
}

/// Advances the fake time source of the journal AND the fake timer zone.
void tick(FakeAsync fa, RecKit k, int ms) {
  k.clock.advance(Duration(milliseconds: ms));
  fa.elapse(Duration(milliseconds: ms));
  fa.flushMicrotasks();
}

/// Fixed LCG so the 50 kill points are reproducible (TP-S04-13): no Random.
class Lcg {
  Lcg(this._s);
  int _s;
  int next(int bound) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % bound;
  }
}

Matcher throwsJournalCode(String code) => throwsA(
    isA<RecordingJournalError>().having((e) => e.code, 'code', code));

/// Latest event kinds (in order) of the whole recording, decoded independently.
List<String> eventKinds(RecKit k, String id) {
  final out = <String>[];
  for (var s = 1; s <= k.segNames(id).length; s++) {
    for (final f in k.frames(id, s)) {
      if (f['k'] == 'e') out.add(f['e'] as String);
    }
  }
  return out;
}

/// Every fs operation (and mark) of [action] after [prepare], in order.
Future<List<FsOp>> opsOf(
    Future<void> Function(RecKit) prepare, Future<void> Function(RecKit) action) async {
  final s = await RecKit.create();
  try {
    await prepare(s);
    s.fs.clearLog();
    try {
      await action(s);
    } catch (_) {}
    return List.of(s.fs.log);
  } finally {
    await s.dispose();
  }
}

/// A fresh device, [prepare], the process dies right after fs operation
/// [crashAt] of [action], then a NEW process (kill) is started.
Future<RecKit> crashRun(Future<void> Function(RecKit) prepare,
    Future<void> Function(RecKit) action, int crashAt) async {
  final k = await RecKit.create();
  await prepare(k);
  k.fs.clearLog();
  k.fs.arm(FaultPlan(crashAt, FaultMode.crashAfter));
  try {
    await action(k);
  } catch (_) {}
  await k.kill();
  return k;
}

/// Number of activities in the S02 store of the kit (live entries).
Future<int> activityCount(RecKit k) async => (await k.activityReal.list()).length;

/// Fault-injecting file system with two extra, switchable behaviours:
/// a gate on opening a segment (a flush "in flight") and a persistent
/// "no space left" failure of every segment write.
class GatedFs extends FaultInjectingJournalFileSystem {
  GatedFs(super.inner);

  Completer<void>? gate;
  bool failSegWrites = false;
  Completer<void>? reached;

  @override
  Future<JournalWriteHandle> openWrite(String path, {bool append = false}) async {
    if (path.endsWith('.log')) {
      final g = gate;
      if (g != null) {
        reached?.complete();
        await g.future;
      }
      if (failSegWrites) {
        throw const FileSystemException(
            'No space left on device', '', OSError('No space left on device', 28));
      }
    }
    final h = await super.openWrite(path, append: append);
    return path.endsWith('.log') ? _SwitchHandle(this, h) : h;
  }
}

class _SwitchHandle implements JournalWriteHandle {
  _SwitchHandle(this._fs, this._h);
  final GatedFs _fs;
  final JournalWriteHandle _h;

  @override
  Future<void> write(Uint8List bytes) async {
    if (_fs.failSegWrites) {
      throw const FileSystemException(
          'No space left on device', '', OSError('No space left on device', 28));
    }
    await _h.write(bytes);
  }

  @override
  Future<void> flush() => _h.flush();
  @override
  Future<void> fsync() => _h.fsync();
  @override
  Future<void> close() => _h.close();
}
