/// File operations the S02 `JournalFileSystem` seam does not have but the
/// recording journal needs (S04 design 4.3, 4.7): exclusive create, exclusive
/// hard-link publish, directory rename, parent-directory fsync and the
/// process-wide journal lock. Tests inject a fault-injecting implementation.
library;

import 'dart:io';
import 'dart:typed_data';

enum LinkOutcome {
  /// `to` did not exist and now is a hard link of `from`.
  created,

  /// `to` already existed; nothing changed.
  exists,

  /// The platform (or this implementation) cannot hard-link: the caller uses
  /// the exclusive-create fallback, which is allowed ONLY under the
  /// process-wide journal lock (design 4.3, Z10, Z14).
  unsupported,
}

abstract class RecordingFileOps {
  /// Exclusive create-if-absent hard link (`Files.createLink`). Never replaces.
  Future<LinkOutcome> linkExclusive(String from, String to);

  /// Exclusive create (`O_CREAT|O_EXCL`), write, fsync. True = this call
  /// created the file; false = it already existed.
  Future<bool> createExclusive(String path, Uint8List bytes);

  /// Atomic directory rename.
  Future<void> renameDir(String from, String to);

  /// Parent-directory fsync. Dart has no directory fsync: the production
  /// implementation is a best-effort no-op and the residual limit is stated in
  /// the design (S02 design 10 step 5). Tests count the call for the ordering
  /// rows.
  Future<void> fsyncDir(String path);

  /// Takes the process-wide exclusive lock on [path] (created if missing).
  /// Returns an opaque handle for [releaseLock]; throws when another holder
  /// has it (the journal then fails closed).
  Future<Object> acquireLock(String path);

  Future<void> releaseLock(Object handle);
}

class IoRecordingFileOps implements RecordingFileOps {
  const IoRecordingFileOps();

  @override
  Future<LinkOutcome> linkExclusive(String from, String to) async =>
      LinkOutcome.unsupported;

  @override
  Future<bool> createExclusive(String path, Uint8List bytes) async {
    final f = File(path);
    try {
      await f.create(exclusive: true);
    } on FileSystemException {
      if (await f.exists()) return false;
      rethrow;
    }
    final raf = await f.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
    return true;
  }

  @override
  Future<void> renameDir(String from, String to) async {
    await Directory(from).rename(to);
  }

  @override
  Future<void> fsyncDir(String path) async {}

  static final Set<String> _held = {};

  @override
  Future<Object> acquireLock(String path) async {
    if (_held.contains(path)) throw const FileSystemException('lock held');
    final f = File(path);
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive);
    } catch (_) {
      await raf.close();
      rethrow;
    }
    _held.add(path);
    return _IoLock(path, raf);
  }

  @override
  Future<void> releaseLock(Object handle) async {
    final h = handle as _IoLock;
    _held.remove(h.path);
    try {
      await h.raf.unlock();
    } catch (_) {}
    await h.raf.close();
  }
}

class _IoLock {
  _IoLock(this.path, this.raf);

  final String path;
  final RandomAccessFile raf;
}
