/// Minimal file seam of the durable command queue so tests can inject faults
/// (crash between temp write and rename, failing flush). The production
/// implementation uses the same atomic-write pattern as the recording journal
/// and the activity journal: write a temp file, flush, rename over the target.
library;

import 'dart:io';
import 'dart:typed_data';

abstract class QueueFileOps {
  Future<void> ensureDir(String path);

  /// Atomically replaces [path] with [bytes]: a reader sees the old file or
  /// the complete new one, never a partial write.
  Future<void> writeAtomic(String path, Uint8List bytes);

  /// Null when the file does not exist.
  Future<Uint8List?> read(String path);

  /// File names (not paths) directly inside [dir]; empty if [dir] is missing.
  Future<List<String>> listFileNames(String dir);

  /// Deletes [path]; a missing file is not an error.
  Future<void> delete(String path);
}

class IoQueueFileOps implements QueueFileOps {
  const IoQueueFileOps();

  static const String tempSuffix = '.tmp';
  static int _tmpCounter = 0;

  @override
  Future<void> ensureDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> writeAtomic(String path, Uint8List bytes) async {
    // Unique per write so two writers never share a temp file.
    final tmp = File(
        '$path.${DateTime.now().microsecondsSinceEpoch}.${_tmpCounter++}$tempSuffix');
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
    // Bounded retry: transient WinError 5/32 from short-lived handles.
    var delayMs = 20;
    for (var attempt = 0;; attempt++) {
      try {
        await tmp.rename(path);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        delayMs *= 2;
      }
    }
  }

  @override
  Future<Uint8List?> read(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<List<String>> listFileNames(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const <String>[];
    final names = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is File) names.add(e.uri.pathSegments.last);
    }
    return names;
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
