// S04 gate 1, finding M-03: sweepExpiredAllScopes deleted recordings of a
// FOREIGN scope without that scope's process-wide lock, so it could delete
// under another live instance. A foreign scope is now swept only while the
// sweep holds that scope's own lock; an owned scope is swept under the lock
// this instance already holds (no second acquire).
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/journal/recording_file_ops.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart' show fixedJournalKey;
import 'journal_kit.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';

/// File ops that count and script the process-wide lock.
class LockOps extends MemRecordingOps {
  LockOps(super.mem, super.mark);

  final List<String> acquired = [];
  final List<Object> released = [];

  /// Paths whose acquire throws (another process holds the lock).
  final Set<String> heldElsewhere = {};

  /// Every acquire throws, whatever the path.
  bool acquireAlwaysThrows = false;

  /// releaseLock throws.
  bool releaseThrows = false;

  @override
  Future<Object> acquireLock(String path) async {
    if (acquireAlwaysThrows || heldElsewhere.contains(path)) {
      throw const FileSystemExceptionLike('lock held elsewhere');
    }
    final h = await super.acquireLock(path);
    acquired.add(path);
    return h;
  }

  @override
  Future<void> releaseLock(Object handle) async {
    released.add(handle);
    if (releaseThrows) throw const FileSystemExceptionLike('release failed');
    await super.releaseLock(handle);
  }
}

Uint8List _utf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late RecKit k;
  late LockOps ops;
  late FileRecordingJournal sweeper;
  late String aLock; // user-a's scope lock path
  late String aDir; // user-a's expired recording directory

  setUp(() async {
    k = await RecKit.create(); // user-a
    // user-a records, dies; its recording gets an FALLBACK marker.
    await k.record(recId(1), 4);
    await k.kill();
    k.put('${k.dirOf(recId(1))}/FALLBACK', _utf('${k.nowMs}'));
    aDir = k.dirOf(recId(1));
    aLock = '${k.recDir}/$kRecordingLockFile';
    ops = LockOps(k.mem, (m) => k.log.add(m));
    // The journal under test: user-b is bound, so user-a is a FOREIGN scope.
    k.uid = 'user-b';
    sweeper = _journal(k, ops);
    k.clock.advance(const Duration(days: 31));
  });
  tearDown(() async {
    await sweeper.dispose();
    await k.dispose();
  });

  List<String> filesIn(String dir) => [
        for (final f in k.mem.files.keys)
          if (f.startsWith('$dir/')) f.substring(dir.length + 1)
      ];

  bool filesLeft() =>
      k.mem.files.keys.any((f) => f.startsWith('$aDir/'));

  test('M-03 a foreign scope whose lock is held elsewhere keeps its expired '
      'recording', () async {
    ops.heldElsewhere.add(aLock);
    expect(await sweeper.sweepExpiredAllScopes(), 0);
    expect(filesLeft(), isTrue,
        reason: 'nothing may be deleted under another holder of the lock');
    expect(filesIn(aDir), contains('FALLBACK'));
    expect(ops.acquired, isNot(contains(aLock)));
  });

  test('M-03 a foreign scope held by a live second instance (real lock '
      'arbitration) keeps its recording, then is swept once released', () async {
    // The other instance holds the lock through the SAME ops object.
    final holder = await ops.acquireLock(aLock);
    expect(await sweeper.sweepExpiredAllScopes(), 0);
    expect(filesLeft(), isTrue);
    await ops.releaseLock(holder);
    expect(await sweeper.sweepExpiredAllScopes(), 1);
    expect(filesLeft(), isFalse);
  });

  test('M-03 a free lock: the foreign recording is deleted and the lock '
      'released afterwards', () async {
    expect(await sweeper.sweepExpiredAllScopes(), 1);
    expect(filesLeft(), isFalse);
    expect(ops.acquired.where((p) => p == aLock), hasLength(1));
    expect(ops.released, hasLength(1), reason: 'the sweep releases what it took');
    // The lock is really free again: it can be taken without throwing.
    final again = await ops.acquireLock(aLock);
    await ops.releaseLock(again);
  });

  test('M-03 a failing lock release does not break the sweep result', () async {
    ops.releaseThrows = true;
    expect(await sweeper.sweepExpiredAllScopes(), 1);
    expect(filesLeft(), isFalse);
  });

  test('M-03 an unavailable lock file system (every acquire throws) skips '
      'every foreign scope and never throws', () async {
    ops.acquireAlwaysThrows = true;
    expect(await sweeper.sweepExpiredAllScopes(), 0);
    expect(filesLeft(), isTrue);
  });

  test('M-03 the OWNED scope is swept under its existing lock: no second '
      'acquire, deletion works', () async {
    k.uid = 'user-a'; // user-a is bound now: the scope is owned
    // First use of the scope takes the lock once (begin does not list or
    // expire anything, and the new active recording must stay untouched).
    final active = metaFor(recId(9), uid: 'user-a', startUtcMs: k.nowMs);
    await sweeper.begin(active);
    final aScopeLock = aLock;
    expect(ops.acquired.where((p) => p == aScopeLock), hasLength(1));
    // A second acquire would throw ('lock held') in the in-memory ops; the
    // sweep still deletes, and no new acquire happened.
    expect(await sweeper.sweepExpiredAllScopes(), 1);
    expect(filesLeft(), isFalse);
    expect(ops.acquired.where((p) => p == aScopeLock), hasLength(1),
        reason: 'no second acquire for the scope this instance already owns');
    expect(ops.released, isEmpty,
        reason: 'the instance keeps its own lock for the session');
    expect(filesIn('${k.recDir}/${recId(9)}'), isNotEmpty,
        reason: 'the active recording is never swept');
  });

  test('M-03 only expired recordings are removed; a fresh one of the same '
      'foreign scope stays', () async {
    // Re-create a second recording of user-a with a fresh marker.
    k.uid = 'user-a';
    final fresh = recId(2);
    await k.journal.begin(k.meta(fresh));
    k.journal.enqueueSample(smp(1), GateCounters.zero);
    await k.journal.flush();
    await k.kill();
    k.put('${k.dirOf(fresh)}/FALLBACK', _utf('${k.nowMs}'));
    k.uid = 'user-b';
    expect(await sweeper.sweepExpiredAllScopes(), 1);
    expect(filesLeft(), isFalse);
    expect(filesIn('${k.recDirOf('user-a')}/$fresh'), contains('FALLBACK'));
  });
}

FileRecordingJournal _journal(RecKit k, LockOps ops) => FileRecordingJournal(
      activity: k.activity,
      boundUid: () => k.uid,
      scopesRoot: () async => RecKit.scopesRoot,
      keyProviderFor: (scopeId) => k.keys.putIfAbsent(
          scopeId,
          () => InMemoryJournalKeyProvider(fixedJournalKey(
              scopeId.codeUnitAt(0) + scopeId.codeUnitAt(1)))),
      fileSystem: k.fs,
      fileOps: ops,
      runner: k.runner,
      nowUtcMs: () => k.nowMs,
    );
