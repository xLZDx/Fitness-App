// Harness for the S02 local-journal integration tests (test plan I01-I10,
// I18-I25, I35, I36, I40, I41, I45-I49, I54, I55). Test-only.
//
// One harness = one journal root, one fake clock, one fixed encryption key and
// an injectable file system. `restart()` opens a NEW repository on the same
// directory (the previous instance is closed first, which touches no file), so
// a test always reads what is on disk, never what a previous instance cached.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_file_system.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';

import 's02_fixtures.dart';
import 'journal_fault_fs.dart';

class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 16, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);

  void set(DateTime t) => now = t;
}

/// A secure-storage fake with the three outcomes the key provider must tell
/// apart: a value, no value, and a store that does not answer.
class FakeJournalSecureStorage implements JournalSecureStorage {
  final Map<String, String> values = {};
  bool failReads = false;
  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    if (failReads) throw StateError('secure storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    values.remove(key);
  }
}

Uint8List fixedJournalKey([int salt = 1]) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + salt) & 0xFF));

int _harnessCounter = 0;

class JournalHarness {
  JournalHarness._(
    this.delegate,
    this.root,
    this.clock,
    this.keys,
    this.mem,
    this.orphanMaxAge,
    this.quarantineMaxCount,
  );

  /// In-memory file system; the directory modification times follow [clock].
  factory JournalHarness.memory({
    JournalKeyProvider? keys,
    Duration orphanMaxAge = const Duration(days: 7),
    int quarantineMaxCount = 20,
  }) {
    final clock = FakeClock();
    final mem = MemoryJournalFileSystem(clock.call);
    return JournalHarness._(
      mem,
      '/app${_harnessCounter++}',
      clock,
      keys ?? InMemoryJournalKeyProvider(fixedJournalKey()),
      mem,
      orphanMaxAge,
      quarantineMaxCount,
    );
  }

  /// Real files under [dir] through the production `dart:io` implementation.
  factory JournalHarness.onDisk(
    Directory dir, {
    JournalKeyProvider? keys,
    Duration orphanMaxAge = const Duration(days: 7),
    int quarantineMaxCount = 20,
  }) {
    return JournalHarness._(
      const IoJournalFileSystem(),
      dir.path.replaceAll('\\', '/'),
      FakeClock(),
      keys ?? InMemoryJournalKeyProvider(fixedJournalKey()),
      null,
      orphanMaxAge,
      quarantineMaxCount,
    );
  }

  final JournalFileSystem delegate;
  final MemoryJournalFileSystem? mem;
  final String root;
  final FakeClock clock;
  final JournalKeyProvider keys;
  final Duration orphanMaxAge;
  final int quarantineMaxCount;

  late FaultInjectingJournalFileSystem fs;
  late FileActivityJournal journal;
  final List<(String, int)> acks = [];

  /// Operations of the last start/recovery pass.
  List<FsOp> recoveryLog = const [];

  /// The report of the last start.
  late JournalRecoveryReport report;

  /// Opens a new repository on the directory (no earlier instance may be
  /// open) and runs its recovery pass. The operation log is cleared after the
  /// start; the recovery operations stay in [recoveryLog].
  Future<JournalRecoveryReport> open({
    DateTime Function()? clockOverride,
  }) async {
    fs = FaultInjectingJournalFileSystem(delegate);
    journal = FileActivityJournal(
      rootPath: root,
      fileSystem: fs,
      keyProvider: keys,
      clock: clockOverride ?? clock.call,
      orphanMaxAge: orphanMaxAge,
      quarantineMaxCount: quarantineMaxCount,
      onAcknowledged: (id, seq) {
        acks.add((id, seq));
        fs.note('ack $id $seq');
      },
    );
    report = await journal.start();
    recoveryLog = List.of(fs.log);
    fs.clearLog();
    return report;
  }

  /// Closes the current instance (no file is touched) and opens a new one on
  /// the same directory. Also the restart after a simulated crash.
  Future<JournalRecoveryReport> restart() async {
    await journal.close();
    return open();
  }

  Future<void> dispose() async {
    try {
      await journal.close();
    } catch (_) {}
  }

  // ---- paths and raw files -------------------------------------------------

  String path(String rel) => '$root/$rel';

  String gen(String id, int seq, [String file = '']) =>
      'journal/$id/g$seq${file.isEmpty ? '' : '/$file'}';

  Future<Uint8List?> bytes(String rel) async {
    try {
      return await delegate.readBytes(path(rel));
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> exists(String rel) => delegate.exists(path(rel));

  Future<void> writeRaw(String rel, List<int> data) async {
    final p = path(rel);
    await delegate.createDir(p.substring(0, p.lastIndexOf('/')));
    final h = await delegate.openWrite(p);
    await h.write(Uint8List.fromList(data));
    await h.flush();
    await h.fsync();
    await h.close();
  }

  Future<void> writeText(String rel, String text) =>
      writeRaw(rel, utf8.encode(text));

  Future<void> deleteRawFile(String rel) => delegate.deleteFile(path(rel));

  Future<void> deleteRawDir(String rel) => delegate.deleteDir(path(rel));

  /// Sorted child names of [rel] (empty when missing).
  Future<List<String>> names(String rel) async =>
      ([for (final e in await delegate.list(path(rel))) e.name]..sort());

  /// Generation numbers present in `journal/<id>/`, ascending.
  Future<List<int>> generations(String id) async {
    final out = <int>[];
    for (final n in await names('journal/$id')) {
      final m = RegExp(r'^g([0-9]+)$').firstMatch(n);
      if (m != null) out.add(int.parse(m.group(1)!));
    }
    return out..sort();
  }

  /// Relative path -> sha256 of every file under [rel] (recursive).
  Future<Map<String, String>> snapshot([String rel = 'journal']) async {
    final out = <String, String>{};
    Future<void> walk(String r) async {
      for (final e in await delegate.list(path(r))) {
        final child = '$r/${e.name}';
        if (e.isDirectory) {
          await walk(child);
        } else {
          out[child] =
              sha256.convert(await delegate.readBytes(path(child))).toString();
        }
      }
    }

    await walk(rel);
    return out;
  }

  Future<Map<String, dynamic>> recordJson(String id, int seq) async {
    final b = await bytes(gen(id, seq, 'record.json'));
    return jsonDecode(utf8.decode(b!)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> commitJson(String id, int seq) async {
    final b = await bytes(gen(id, seq, 'COMMIT'));
    if (b == null) return null;
    return jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> currentJson(String id) async {
    final b = await bytes('journal/$id/CURRENT');
    if (b == null) return null;
    try {
      return jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Flips one bit of the file at [rel].
  Future<void> flipBit(String rel, [int offset = 10]) async {
    final b = (await bytes(rel))!;
    b[offset % b.length] ^= 0x01;
    await writeRaw(rel, b);
  }

  Future<List<String>> listIds() async =>
      [for (final e in await journal.list()) e.id];

  Future<List<String>> indexLines() async {
    final b = await bytes('journal/index.jsonl');
    if (b == null) return const [];
    return const LineSplitter()
        .convert(utf8.decode(b, allowMalformed: true))
        .where((l) => l.trim().isNotEmpty)
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Sessions

/// A small session with a GPS stream (latitudes end in the sentinel digits
/// `7351`, plan 2.1) and a heart-rate stream (values end in `.25`). [seed]
/// makes the stream bytes of two versions of the same activity distinct.
ActivitySession journalSession(
  String id, {
  int seed = 0,
  int samples = 20,
  bool withGps = true,
  bool withHr = true,
  double distanceM = 4800,
  SportType sport = SportType.running,
}) {
  final offs = [for (var i = 0; i < samples; i++) i * 1000];
  final streams = <StreamKind, SampleStream>{};
  if (withGps) {
    streams[StreamKind.gps] = SampleStream.checked(
      kind: StreamKind.gps,
      sourceId: 'app',
      offsetsMs: offs,
      lats: [
        for (var i = 0; i < samples; i++)
          ((1 + seed) * 10000000000 + i * 50000 + 7351) / 1e10,
      ],
      lons: [for (var i = 0; i < samples; i++) -27.5 + i * 0.0001],
      accuracies: [for (var i = 0; i < samples; i++) 4.5],
    );
  }
  if (withHr) {
    streams[StreamKind.heartRate] = SampleStream.checked(
      kind: StreamKind.heartRate,
      sourceId: 'app',
      offsetsMs: offs,
      values: [for (var i = 0; i < samples; i++) 100.25 + seed + i],
    );
  }
  final start = DateTime.utc(2026, 5, 1, 6).add(Duration(hours: seed));
  return ActivitySession(
    id: id,
    sport: sport,
    startUtc: start,
    endUtc: start.add(const Duration(minutes: 30)),
    movingTimeS: 1700,
    summary: ActivitySummary(distanceM: distanceM),
    streams: streams,
    provenance: [miniSource(externalId: 'e$seed')],
  );
}

/// The stored JSON of a session, for whole-object comparison.
String sessionJson(ActivitySession s) => jsonEncode(s.toJson());

/// The streams of a session as a plain comparable structure.
List<Object?> streamsOf(ActivitySession s) => [
      for (final k in StreamKind.values)
        if (s.streams[k] != null) s.streams[k]!.toJson(),
    ];

String idFor(int n) => 'act_${n.toString().padLeft(40, '0')}';
