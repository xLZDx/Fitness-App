// S02-02 I19: the write order of one `put` (design 10) as an exact operation
// log over the fault-injection seam. The expected list is hand written here,
// not derived from the production code.
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

/// `kind path` with the root removed; a rename shows `from -> to`.
List<String> render(JournalHarness h, List<FsOp> log) => [
      for (final o in log)
        if (o.kind == FsOpKind.note)
          'note ${o.path}'
        else
          '${o.kind.name} ${o.path.substring(h.root.length + 1)}'
              '${o.to == null ? '' : ' -> ${o.to!.substring(h.root.length + 1)}'}',
    ];

List<String> tempWrite(String file) => [
      'openWrite $file.tmp',
      'write $file.tmp',
      'flush $file.tmp',
      'fsync $file.tmp',
      'close $file.tmp',
    ];

List<String> atomic(String file) =>
    [...tempWrite(file), 'rename $file.tmp -> $file'];

/// The literal order of design 10 for activity [id], generation [seq].
List<String> expectedPut(String id, int seq) {
  final g = 'journal/$id/g$seq';
  return [
    'createDir $g',
    ...atomic('$g/streams.bin'),
    ...atomic('$g/record.json'),
    'readBytes $g/streams.bin', // read-back, streamHash verification
    'readBytes $g/record.json',
    ...atomic('$g/COMMIT'),
    // THE COMMIT POINT is the rename above; the acknowledgement note is
    // checked separately. CURRENT and the index follow it.
    ...atomic('journal/$id/CURRENT'),
    'openWrite journal/index.jsonl',
    'write journal/index.jsonl',
    'flush journal/index.jsonl',
    'fsync journal/index.jsonl',
    'close journal/index.jsonl',
  ];
}

void main() {
  late JournalHarness h;
  final id = idFor(1);

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
  });

  tearDown(() => h.dispose());

  void expectNoOverwriteOfCommitted(List<FsOp> log) {
    final committed = <String>{};
    for (final o in log) {
      if (o.kind == FsOpKind.note) continue;
      for (final dir in committed) {
        final touches = (o.path.startsWith('$dir/') || o.path == dir) ||
            (o.to != null && o.to!.startsWith('$dir/'));
        final writes = {
          FsOpKind.openWrite,
          FsOpKind.write,
          FsOpKind.rename,
          FsOpKind.deleteFile,
          FsOpKind.deleteDir,
        }.contains(o.kind);
        expect(touches && writes, isFalse,
            reason: 'an operation changed a committed generation: $o');
      }
      if (o.kind == FsOpKind.rename && o.to!.endsWith('/COMMIT')) {
        committed.add(o.to!.substring(0, o.to!.lastIndexOf('/')));
      }
    }
  }

  test('first write: the operation log is exactly the design-10 order', () async {
    await h.journal.put(journalSession(id));
    final ops = [for (final o in h.fs.log) if (o.kind != FsOpKind.note) o];
    expect(render(h, ops), expectedPut(id, 1));
  });

  test('overwrite: same order in a NEW generation, nothing of the previous '
      'generation is touched or deleted', () async {
    await h.journal.put(journalSession(id));
    h.fs.clearLog();
    await h.journal.put(journalSession(id, seed: 2));
    final ops = [for (final o in h.fs.log) if (o.kind != FsOpKind.note) o];
    expect(render(h, ops), expectedPut(id, 2));
    expect(h.fs.log.any((o) => o.kind == FsOpKind.deleteFile || o.kind == FsOpKind.deleteDir),
        isFalse, reason: 'the put log contains no delete');
    expect(await h.generations(id), [1, 2],
        reason: 'the old generation stays until the next verified read');
  });

  test('the acknowledgement is logged after the COMMIT rename and never '
      'before it (nor between the read-back and the COMMIT)', () async {
    await h.journal.put(journalSession(id));
    final all = render(h, h.fs.log);
    final ack = all.indexWhere((l) => l.startsWith('note ack'));
    final commit = all.indexWhere((l) => l.contains('COMMIT.tmp -> '));
    final readBack = all.lastIndexWhere((l) => l.startsWith('readBytes'));
    expect(ack, isNonNegative);
    expect(commit, isNonNegative);
    expect(ack, greaterThan(commit));
    expect(commit, greaterThan(readBack), reason: 'COMMIT only after the read-back');
    expect(h.acks, [(id, 1)]);
  });

  test('no operation writes, renames over or deletes inside a generation '
      'that already has a COMMIT marker (first write and overwrite)', () async {
    await h.journal.put(journalSession(id));
    expectNoOverwriteOfCommitted(h.fs.log);
    await h.journal.put(journalSession(id, seed: 2));
    expectNoOverwriteOfCommitted(h.fs.log);
    // The checker itself must be able to fail: a synthetic bad log.
    final bad = [
      FsOp(FsOpKind.rename, '/r/j/a/g1/COMMIT.tmp', to: '/r/j/a/g1/COMMIT', index: 0),
      FsOp(FsOpKind.rename, '/r/j/a/g1/record.json.tmp',
          to: '/r/j/a/g1/record.json', index: 1),
    ];
    expect(() => expectNoOverwriteOfCommitted(bad), throwsA(anything));
  });

  test('every temp file is written, flushed, fsynced and closed BEFORE its '
      'rename; there is no directory sync operation', () async {
    await h.journal.put(journalSession(id));
    final ops = [for (final o in h.fs.log) if (o.kind != FsOpKind.note) o];
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].kind != FsOpKind.rename) continue;
      final tmp = ops[i].path;
      final seen = [
        for (var j = 0; j < i; j++)
          if (ops[j].path == tmp) ops[j].kind,
      ];
      expect(seen, [
        FsOpKind.openWrite,
        FsOpKind.write,
        FsOpKind.flush,
        FsOpKind.fsync,
        FsOpKind.close,
      ], reason: 'temp file $tmp');
    }
    // The seam has no directory-sync kind at all: the only kinds the log
    // can contain are the ones the production seam declares.
    expect(ops.map((o) => o.kind).toSet(), {
      FsOpKind.createDir,
      FsOpKind.openWrite,
      FsOpKind.write,
      FsOpKind.flush,
      FsOpKind.fsync,
      FsOpKind.close,
      FsOpKind.rename,
      FsOpKind.readBytes,
    });
    expect(
        FsOpKind.values.map((k) => k.name).any((n) => n.toLowerCase().contains('dirsync')),
        isFalse);
  });

  test('the old generation is deleted only after the next verified read', () async {
    await h.journal.put(journalSession(id));
    await h.journal.put(journalSession(id, seed: 2));
    expect(await h.generations(id), [1, 2]);

    h.fs.clearLog();
    final e = await h.journal.read(id);
    expect(e!.generation, 2);
    expect(await h.generations(id), [2], reason: 'pruned by the verified read');
    final deletes = [for (final o in h.fs.log) if (o.kind == FsOpKind.deleteDir) o];
    expect(deletes.map((o) => o.path.substring(h.root.length + 1)),
        ['journal/$id/g1']);
  });

  test('CURRENT names the new generation and the index line is appended '
      'after the COMMIT', () async {
    await h.journal.put(journalSession(id));
    final cur = await h.currentJson(id);
    expect(cur!['gen'], 'g1');
    final commit = await h.commitJson(id, 1);
    expect(commit!['seq'], 1);
    expect((await h.indexLines()).single, contains('"op":"put"'));
    expect(JournalSyncState.pending.wire, 'pending');
  });
}
