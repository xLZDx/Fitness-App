// Shared helpers of the offline command (V0 CompleteSet) functional tests.
// Not a test file: it has no main().
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fitness_app/features/workouts/offline/canonical.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/complete_set_acceptor.dart';
import 'package:fitness_app/features/workouts/offline/file_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/in_memory_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/queue_file_ops.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';

const String kUid = 'uid-alice';
const String kOtherUid = 'uid-bob';
const String kDevice = 'device-install-1';

/// A valid 30 character operation id for hand-built records.
String fixedOpId(String tag) => tag.padRight(30, '0').substring(0, 30);

/// A valid CompleteSet body for [setIndex].
Map<String, Object?> setBody(int setIndex,
        {int reps = 8, int? loadGrams = 60000, int at = 1700000000000}) =>
    <String, Object?>{
      'mode': 'APPEND',
      'setId': displaySetId(setIndex),
      'performedConfirmed': true,
      'actualReps': reps,
      'actualRepsConfirmed': true,
      'targetReps': 8,
      'loadGrams': loadGrams,
      'source': 'manual',
      'performedAtClientMs': at,
    };

CompleteSetIntent intentOf(
  String intentKey, {
  String sessionId = 'sess-1',
  String exerciseId = 'ex-squat',
  int setIndex = 1,
  int reps = 8,
}) =>
    CompleteSetIntent(
      sessionId: sessionId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      intentKey: intentKey,
      body: setBody(setIndex, reps: reps),
    );

/// Default writer proof of [senderFor]; the sender requires a provider.
Future<String?> kDefaultTestProof(String uid, String sessionId) async =>
    'test-proof';

/// Deterministic mutable clock shared by store, acceptor and sender.
class TestClock {
  TestClock([int startMs = 1700000000000]) : ms = startMs;
  int ms;
  int nowMs() => ms;
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  void advance(Duration d) => ms += d.inMilliseconds;
}

/// Deterministic, unique, valid operation ids.
class IdMinter {
  int _n = 0;
  int get mintedCount => _n;
  String call(String uid) {
    _n++;
    return '${uidTagOf(uid)}${_n.toString().padLeft(22, '0')}';
  }
}

CompleteSetAcceptor acceptorFor(CommandQueueStore store, TestClock clock,
        {IdMinter? minter, String device = kDevice}) =>
    CompleteSetAcceptor(
      store: store,
      originDeviceInstallId: device,
      wallMs: clock.nowMs,
      monotonicMs: clock.nowMs,
      mintId: (minter ?? IdMinter()).call,
    );

/// One server-side effect of the fake server.
class ServerEffect {
  ServerEffect(this.operationId, this.hash, this.bytes);
  final String operationId;
  final String hash;
  final Uint8List bytes;
}

enum Fault { none, applyThenThrow, applyThenHang, throwWithoutApplying }

/// A tiny in-process server with the idempotency contract of section 4:
/// first sight of an operationId applies it (one effect), a replay with the
/// same hash answers ALREADY_COMMITTED, a replay with a different hash answers
/// ID_PAYLOAD_MISMATCH, bytes that do not hash to the claimed hash are
/// INVALID_PAYLOAD.
class FakeServer implements CommandTransport {
  final List<ServerEffect> effects = <ServerEffect>[];
  final List<CommandEnvelope> received = <CommandEnvelope>[];
  final Map<String, String> _receipts = <String, String>{};

  /// Per call faults, consumed in order; [Fault.none] once exhausted.
  final List<Fault> faults = <Fault>[];

  /// If set, overrides the answer code for the next call (consumed once)
  /// WITHOUT applying anything.
  final List<String> scriptedCodes = <String>[];

  /// Applied exactly once per operationId, by operationId.
  int effectCount(String operationId) =>
      effects.where((e) => e.operationId == operationId).length;

  Completer<TransportAnswer>? gate;

  @override
  Future<TransportAnswer> send(CommandEnvelope envelope) async {
    received.add(envelope);
    if (gate != null) return gate!.future;
    final fault = faults.isEmpty ? Fault.none : faults.removeAt(0);
    if (fault == Fault.throwWithoutApplying) {
      throw const SocketException('offline');
    }
    if (scriptedCodes.isNotEmpty) {
      return TransportAnswer(code: scriptedCodes.removeAt(0));
    }
    final answer = _apply(envelope);
    switch (fault) {
      case Fault.applyThenThrow:
        throw const SocketException('connection reset after apply');
      case Fault.applyThenHang:
        return Completer<TransportAnswer>().future; // never completes
      case Fault.none:
      case Fault.throwWithoutApplying:
        return answer;
    }
  }

  TransportAnswer _apply(CommandEnvelope e) {
    // The real callable rejects a command without a writer proof.
    final proof = e.writerProof;
    if (proof == null || proof.isEmpty) {
      return const TransportAnswer(code: 'INVALID_PAYLOAD');
    }
    if (payloadHashHex(e.payloadBytes) != e.payloadHash) {
      return const TransportAnswer(code: 'INVALID_PAYLOAD');
    }
    final prior = _receipts[e.operationId];
    if (prior != null) {
      return TransportAnswer(
          code: prior == e.payloadHash
              ? 'ALREADY_COMMITTED'
              : 'ID_PAYLOAD_MISMATCH');
    }
    _receipts[e.operationId] = e.payloadHash;
    effects.add(ServerEffect(
        e.operationId, e.payloadHash, Uint8List.fromList(e.payloadBytes)));
    return TransportAnswer(
        code: 'COMMITTED', revisionAfter: effects.length, serverTimeMs: 42);
  }
}

CommandSender senderFor(
  CommandQueueStore store,
  CommandTransport transport,
  TestClock clock, {
  Duration sendTimeout = const Duration(seconds: 5),
  WriterProofProvider? proof,
  int seed = 7,
}) =>
    CommandSender(
      store: store,
      transport: transport,
      deviceInstallId: kDevice,
      clientBuild: 'test-build',
      writerProof: proof ?? kDefaultTestProof,
      sendTimeout: sendTimeout,
      now: clock.now,
      random: _SeededRandom(seed),
    );

class _SeededRandom implements Random {
  _SeededRandom(this._s);
  int _s;
  @override
  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }

  @override
  bool nextBool() => nextInt(2) == 1;
  @override
  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}

/// A temp directory per test, removed afterwards.
Future<Directory> makeTempRoot() =>
    Directory.systemTemp.createTemp('offline_queue_test_');

Future<void> removeTempRoot(Directory d) async {
  if (await d.exists()) await d.delete(recursive: true);
}

/// Delegating file ops with fault injection. A fault fires when [failWhen]
/// returns true for the target path of a [writeAtomic].
///
/// [FaultMode.afterTempWrite] writes the (optionally truncated) temp file next
/// to the target and throws before the rename, which is exactly the state a
/// crash between flush and rename leaves behind.
enum FaultMode { afterTempWrite, beforeTempWrite }

class FaultyFileOps implements QueueFileOps {
  FaultyFileOps([QueueFileOps? inner]) : _inner = inner ?? const IoQueueFileOps();
  final QueueFileOps _inner;

  bool Function(String path)? failWhen;
  FaultMode mode = FaultMode.afterTempWrite;
  bool truncateTemp = true;
  int failures = 0;
  final List<String> writtenPaths = <String>[];

  void armFor(bool Function(String path) when,
      {FaultMode m = FaultMode.afterTempWrite, bool truncate = true}) {
    failWhen = when;
    mode = m;
    truncateTemp = truncate;
  }

  void disarm() => failWhen = null;

  @override
  Future<void> ensureDir(String path) => _inner.ensureDir(path);

  @override
  Future<void> writeAtomic(String path, Uint8List bytes) async {
    final f = failWhen;
    if (f != null && f(path)) {
      failures++;
      if (mode == FaultMode.afterTempWrite) {
        final cut = truncateTemp ? bytes.sublist(0, bytes.length ~/ 2) : bytes;
        await File('$path${IoQueueFileOps.tempSuffix}').writeAsBytes(cut);
      }
      throw const FileSystemException('injected crash before rename');
    }
    writtenPaths.add(path);
    await _inner.writeAtomic(path, bytes);
  }

  @override
  Future<Uint8List?> read(String path) => _inner.read(path);

  @override
  Future<List<String>> listFileNames(String dir) => _inner.listFileNames(dir);

  @override
  Future<void> delete(String path) => _inner.delete(path);
}

bool isRecordPath(String p) => p.contains('/records/') && p.endsWith('.json');
bool isSeqPath(String p) =>
    p.endsWith('/meta.a.json') || p.endsWith('/meta.b.json');

/// A store flavour for the parametrised suites.
class StoreKind {
  StoreKind(this.name, this.durable);
  final String name;
  final bool durable;
}

/// Makes stores of one kind over a shared backing (the dir for files).
class StoreFactory {
  StoreFactory.memory(this.clock)
      : kind = StoreKind('in-memory', false),
        root = null;
  StoreFactory.file(this.clock, Directory this.root)
      : kind = StoreKind('file', true);

  final StoreKind kind;
  final TestClock clock;
  final Directory? root;

  /// Shared in-memory instance per uid (an in-memory store has no reopen).
  final Map<String, CommandQueueStore> _mem = <String, CommandQueueStore>{};

  final Map<String, CommandQueueStore> _file = <String, CommandQueueStore>{};

  /// Opens a store. For files this simulates a process restart: a previously
  /// opened instance of the same uid is disposed first (one live instance per
  /// scope is enforced by the store).
  Future<CommandQueueStore> open([String uid = kUid, QueueFileOps? ops]) async {
    if (!kind.durable) {
      return _mem[uid] ??=
          InMemoryCommandQueueStore(uid: uid, nowMs: clock.nowMs);
    }
    await _file.remove(uid)?.dispose();
    return _file[uid] = await FileCommandQueueStore.open(
      uid: uid,
      rootDir: root!.path.replaceAll('\\', '/'),
      ops: ops ?? const IoQueueFileOps(),
      nowMs: clock.nowMs,
    );
  }
}

String rootPathOf(Directory d) => d.path.replaceAll('\\', '/');

/// Reads every file under [dir] recursively as text (latin1-safe).
Future<String> dumpTree(Directory dir) async {
  final b = StringBuffer();
  if (!await dir.exists()) return '';
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File) {
      b.writeln(e.path);
      b.writeln(utf8.decode(await e.readAsBytes(), allowMalformed: true));
    }
  }
  return b.toString();
}

bool isMetaPath(String p) {
  final name = p.substring(p.lastIndexOf('/') + 1);
  return name == 'meta.a.json' || name == 'meta.b.json';
}

String scopeOf(Directory root, [String uid = kUid]) =>
    '${rootPathOf(root)}/${queueScopeDirName(uid)}';

/// Parsed metadata document of a slot ('a' or 'b'), null if the file is
/// missing or not a framed document.
Map<String, Object?>? slotDoc(String scope, String slot) {
  final f = File('$scope/meta.$slot.json');
  if (!f.existsSync()) return null;
  final text = f.readAsStringSync().trimRight();
  final i = text.lastIndexOf('\n#sha256:');
  final body = i < 0 ? text : text.substring(0, i);
  try {
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } catch (_) {
    return null;
  }
}

/// 'a' or 'b': the slot with the highest gen.
String newestSlot(String scope) {
  final a = (slotDoc(scope, 'a')?['gen'] as int?) ?? -1;
  final b = (slotDoc(scope, 'b')?['gen'] as int?) ?? -1;
  return a >= b ? 'a' : 'b';
}

String olderSlot(String scope) => newestSlot(scope) == 'a' ? 'b' : 'a';

/// Bytes of every file under [dir] keyed by path (for "nothing changed").
Map<String, String> treeSnapshot(String dir) => <String, String>{
      for (final e in Directory(dir).listSync(recursive: true))
        if (e is File)
          e.path.replaceAll('\\', '/'): base64.encode(e.readAsBytesSync()),
    };

/// FaultyFileOps that can also fail deletes of record files.
class DeleteFaultOps extends FaultyFileOps {
  bool failRecordDeletes = false;
  int deleteFailures = 0;
  @override
  Future<void> delete(String path) {
    if (failRecordDeletes && isRecordPath(path)) {
      deleteFailures++;
      throw const FileSystemException('injected delete failure');
    }
    return super.delete(path);
  }
}
