/// The file-system seam of the local journal (S02 design 10, test plan I19,
/// I20).
///
/// Tests inject a fault-injecting implementation that logs every operation and
/// can fail or "crash" at any step. The seam deliberately has NO directory
/// fsync operation: Dart has no directory fsync and FFI is not used, so the
/// design relies on rename atomicity and states the residual limit (design 10
/// step 5). Paths are plain strings joined with `/`.
library;

import 'dart:io';
import 'dart:typed_data';

/// One child of a directory.
class JournalDirEntry {
  const JournalDirEntry(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;
}

/// An open file being written. The sequence of calls on a handle is the
/// observable "temp write, flush, fsync" of the write order.
abstract class JournalWriteHandle {
  Future<void> write(Uint8List bytes);

  /// Flushes user-space buffers. The real implementation has none, so this is
  /// a no-op there; the step exists so the operation log matches design 10.
  Future<void> flush();

  /// Forces the file contents to stable storage.
  Future<void> fsync();

  Future<void> close();
}

abstract class JournalFileSystem {
  /// Creates a directory and its parents; no error if it exists.
  Future<void> createDir(String path);

  /// True when a file or a directory exists at [path].
  Future<bool> exists(String path);

  /// Whole-file read. Throws a [FileSystemException] when missing.
  Future<Uint8List> readBytes(String path);

  /// Children of [path]; empty when the directory does not exist.
  Future<List<JournalDirEntry>> list(String path);

  /// Opens [path] for writing (truncate) or appending.
  Future<JournalWriteHandle> openWrite(String path, {bool append = false});

  /// Atomic rename, replacing an existing file at [to].
  Future<void> rename(String from, String to);

  /// Deletes a file; no error if it is already gone.
  Future<void> deleteFile(String path);

  /// Deletes a directory tree; no error if it is already gone.
  Future<void> deleteDir(String path);

  /// Last modification time, or null when unknown or missing.
  Future<DateTime?> modified(String path);
}

/// The real implementation over `dart:io`.
class IoJournalFileSystem implements JournalFileSystem {
  const IoJournalFileSystem();

  @override
  Future<void> createDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<bool> exists(String path) async {
    return await File(path).exists() || await Directory(path).exists();
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<List<JournalDirEntry>> list(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final out = <JournalDirEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      out.add(JournalDirEntry(name, isDirectory: e is Directory));
    }
    return out;
  }

  @override
  Future<JournalWriteHandle> openWrite(String path, {bool append = false}) async {
    final raf = await File(path)
        .open(mode: append ? FileMode.append : FileMode.write);
    return _IoWriteHandle(raf);
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteDir(String path) async {
    final d = Directory(path);
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<DateTime?> modified(String path) async {
    try {
      return (await FileStat.stat(path)).modified;
    } catch (_) {
      return null;
    }
  }
}

class _IoWriteHandle implements JournalWriteHandle {
  _IoWriteHandle(this._raf);

  final RandomAccessFile _raf;

  @override
  Future<void> write(Uint8List bytes) async {
    await _raf.writeFrom(bytes);
  }

  // RandomAccessFile has no user-space buffer; flush() below is the fsync.
  @override
  Future<void> flush() async {}

  @override
  Future<void> fsync() async {
    await _raf.flush();
  }

  @override
  Future<void> close() async {
    await _raf.close();
  }
}

/// True when [e] means the device is out of space (ENOSPC, EDQUOT, Windows
/// ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL) or says so in its message.
bool isDiskFull(FileSystemException e) {
  final code = e.osError?.errorCode;
  if (code == 28 || code == 122 || code == 69 || code == 112 || code == 39) {
    return true;
  }
  final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
  return text.contains('no space left') ||
      text.contains('disk full') ||
      text.contains('not enough space') ||
      text.contains('quota exceeded');
}
