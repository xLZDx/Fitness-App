// Test doubles for the journal file-system seam (S02 test plan I19, I20, I40,
// I41, I46-I49, I54, I55). Test-only.
//
// - [MemoryJournalFileSystem]: an in-memory file system with the same contract
//   as the production seam (atomic rename that replaces, parent directory must
//   exist, directory modification times taken from an injectable clock).
// - [FaultInjectingJournalFileSystem]: wraps ANY [JournalFileSystem] (memory or
//   a real temp directory), logs every operation, and can inject one fault at
//   an exact operation index: a crash after the operation (the process dies,
//   every later call fails and changes nothing), an error after the operation,
//   a failure instead of the operation, or "no space left" instead of it.
//
// The wrapper deliberately has NO directory-sync operation, like the seam.
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/repository/journal_file_system.dart';

// ---------------------------------------------------------------------------
// In-memory file system

class MemoryJournalFileSystem implements JournalFileSystem {
  MemoryJournalFileSystem(this._now);

  final DateTime Function() _now;

  /// Absolute path -> bytes.
  final Map<String, Uint8List> files = {};

  /// Absolute directory paths (every ancestor is present).
  final Set<String> dirs = {};
  final Map<String, DateTime> _mtimes = {};

  static String _parent(String p) {
    final i = p.lastIndexOf('/');
    return i <= 0 ? '' : p.substring(0, i);
  }

  void _touch(String path) {
    _mtimes[path] = _now();
  }

  void _touchParent(String path) {
    final parent = _parent(path);
    if (parent.isNotEmpty && dirs.contains(parent)) _touch(parent);
  }

  bool _parentExists(String path) {
    final parent = _parent(path);
    return parent.isEmpty || dirs.contains(parent);
  }

  @override
  Future<void> createDir(String path) async {
    var p = path;
    while (p.isNotEmpty) {
      if (files.containsKey(p)) {
        throw FileSystemException('a file exists at the directory path', p);
      }
      if (dirs.add(p)) {
        _touch(p);
        _touchParent(p);
      }
      p = _parent(p);
    }
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || dirs.contains(path);

  @override
  Future<Uint8List> readBytes(String path) async {
    final b = files[path];
    if (b == null) throw FileSystemException('No such file', path);
    return Uint8List.fromList(b);
  }

  @override
  Future<List<JournalDirEntry>> list(String path) async {
    if (!dirs.contains(path)) return const [];
    final out = <JournalDirEntry>[];
    for (final f in files.keys) {
      if (_parent(f) == path) {
        out.add(JournalDirEntry(f.substring(path.length + 1), isDirectory: false));
      }
    }
    for (final d in dirs) {
      if (_parent(d) == path) {
        out.add(JournalDirEntry(d.substring(path.length + 1), isDirectory: true));
      }
    }
    return out;
  }

  @override
  Future<JournalWriteHandle> openWrite(String path, {bool append = false}) async {
    if (dirs.contains(path)) throw FileSystemException('is a directory', path);
    if (!_parentExists(path)) {
      throw FileSystemException('parent directory missing', path);
    }
    if (!append || !files.containsKey(path)) {
      final fresh = !files.containsKey(path);
      files[path] = Uint8List(0);
      if (fresh) _touchParent(path);
    }
    _touch(path);
    return _MemoryHandle(this, path);
  }

  @override
  Future<void> rename(String from, String to) async {
    final b = files[from];
    if (b == null) throw FileSystemException('rename source missing', from);
    if (dirs.contains(to)) throw FileSystemException('target is a directory', to);
    if (!_parentExists(to)) {
      throw FileSystemException('rename target parent missing', to);
    }
    files.remove(from);
    files[to] = b;
    _touch(to);
    _touchParent(from);
    _touchParent(to);
  }

  @override
  Future<void> deleteFile(String path) async {
    if (files.remove(path) != null) _touchParent(path);
  }

  @override
  Future<void> deleteDir(String path) async {
    if (!dirs.contains(path)) return;
    final prefix = '$path/';
    files.removeWhere((k, _) => k.startsWith(prefix));
    dirs.removeWhere((d) => d == path || d.startsWith(prefix));
    _mtimes.removeWhere((k, _) => k == path || k.startsWith(prefix));
    _touchParent(path);
  }

  @override
  Future<DateTime?> modified(String path) async => _mtimes[path];
}

class _MemoryHandle implements JournalWriteHandle {
  _MemoryHandle(this._fs, this._path);

  final MemoryJournalFileSystem _fs;
  final String _path;
  bool _closed = false;

  @override
  Future<void> write(Uint8List bytes) async {
    if (_closed) throw FileSystemException('write on a closed handle', _path);
    final old = _fs.files[_path] ?? Uint8List(0);
    final out = Uint8List(old.length + bytes.length)
      ..setRange(0, old.length, old)
      ..setRange(old.length, old.length + bytes.length, bytes);
    _fs.files[_path] = out;
    _fs._touch(_path);
  }

  @override
  Future<void> flush() async {
    if (_closed) throw FileSystemException('flush on a closed handle', _path);
  }

  @override
  Future<void> fsync() async {
    if (_closed) throw FileSystemException('fsync on a closed handle', _path);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

// ---------------------------------------------------------------------------
// Fault injection

enum FsOpKind {
  createDir,
  exists,
  readBytes,
  list,
  openWrite,
  write,
  flush,
  fsync,
  close,
  rename,
  deleteFile,
  deleteDir,
  modified,

  /// A note written by the test (for example the caller acknowledgement).
  note,
}

class FsOp {
  FsOp(this.kind, this.path, {this.to, required this.index, this.append = false});

  final FsOpKind kind;
  final String path;
  final String? to;

  /// Position among the real operations since the last [clearLog]; -1 for
  /// notes.
  final int index;
  final bool append;

  @override
  String toString() => '#$index ${kind.name} $path${to == null ? '' : ' -> $to'}';
}

/// The process died right after the injected operation.
class SimulatedCrash implements Exception {
  SimulatedCrash(this.at);

  final String at;

  @override
  String toString() => 'SimulatedCrash($at)';
}

enum FaultMode {
  /// Perform the operation, then the process dies (no later call works).
  crashAfter,

  /// Perform the operation, then report a [FileSystemException] anyway.
  errorAfter,

  /// Do not perform the operation; throw a [FileSystemException].
  failAt,

  /// Do not perform the operation; throw "no space left on device" (ENOSPC).
  diskFullAt,
}

class FaultPlan {
  const FaultPlan(this.opIndex, this.mode, {this.partialWrite = false});

  /// Index of the operation (as in [FaultInjectingJournalFileSystem.log],
  /// counted from the last [FaultInjectingJournalFileSystem.arm]).
  final int opIndex;
  final FaultMode mode;

  /// With [FaultMode.crashAfter] on a `write`: only the first half of the
  /// bytes reaches the file (a torn write).
  final bool partialWrite;

  @override
  String toString() => 'FaultPlan(#$opIndex ${mode.name}'
      '${partialWrite ? ', partial' : ''})';
}

class FaultInjectingJournalFileSystem implements JournalFileSystem {
  FaultInjectingJournalFileSystem(this.inner);

  final JournalFileSystem inner;
  final List<FsOp> log = [];
  FaultPlan? _plan;
  int _count = 0;
  bool _fired = false;
  bool _dead = false;

  /// True after an injected crash: the process is gone, nothing changes.
  bool get dead => _dead;

  /// True once the armed fault has actually been injected.
  bool get fired => _fired;

  /// Arms [plan]; the operation counter restarts at zero.
  void arm(FaultPlan plan) {
    _plan = plan;
    _count = 0;
    _fired = false;
  }

  void disarm() {
    _plan = null;
  }

  /// Empties the log and restarts the operation counter.
  void clearLog() {
    log.clear();
    _count = 0;
  }

  /// Number of real operations since the last [clearLog] / [arm].
  int get opCount => _count;

  void note(String text) {
    log.add(FsOp(FsOpKind.note, text, index: -1));
  }

  FileSystemException _error(bool diskFull, String path) => diskFull
      ? FileSystemException('No space left on device', path,
          const OSError('No space left on device', 28))
      : FileSystemException('injected I/O failure', path,
          const OSError('Input/output error', 5));

  Future<T> _op<T>(
    FsOpKind kind,
    String path,
    Future<T> Function() body, {
    String? to,
    bool append = false,
    Future<T> Function()? partial,
  }) async {
    if (_dead) throw SimulatedCrash('after crash: ${kind.name} $path');
    final idx = _count++;
    log.add(FsOp(kind, path, to: to, index: idx, append: append));
    final plan = _plan;
    final hit = plan != null && !_fired && plan.opIndex == idx;
    if (hit && plan.mode == FaultMode.failAt) {
      _fired = true;
      throw _error(false, path);
    }
    if (hit && plan.mode == FaultMode.diskFullAt) {
      _fired = true;
      throw _error(true, path);
    }
    if (hit && plan.mode == FaultMode.crashAfter && plan.partialWrite && partial != null) {
      _fired = true;
      await partial();
      _dead = true;
      throw SimulatedCrash('torn ${kind.name} $path');
    }
    final r = await body();
    if (hit) {
      _fired = true;
      if (plan.mode == FaultMode.crashAfter) {
        _dead = true;
        throw SimulatedCrash('after #$idx ${kind.name} $path');
      }
      throw _error(false, path); // errorAfter
    }
    return r;
  }

  @override
  Future<void> createDir(String path) =>
      _op(FsOpKind.createDir, path, () => inner.createDir(path));

  @override
  Future<bool> exists(String path) =>
      _op(FsOpKind.exists, path, () => inner.exists(path));

  /// Optional hook that may alter bytes returned by [readBytes] (a failing
  /// read-back, bit rot between write and verify).
  Uint8List Function(String path, Uint8List bytes)? onRead;

  @override
  Future<Uint8List> readBytes(String path) => _op(FsOpKind.readBytes, path, () async {
        final b = await inner.readBytes(path);
        final hook = onRead;
        return hook == null ? b : hook(path, b);
      });

  @override
  Future<List<JournalDirEntry>> list(String path) =>
      _op(FsOpKind.list, path, () => inner.list(path));

  @override
  Future<JournalWriteHandle> openWrite(String path, {bool append = false}) =>
      _op(FsOpKind.openWrite, path, () async {
        final h = await inner.openWrite(path, append: append);
        return _FaultHandle(this, h, path) as JournalWriteHandle;
      }, append: append);

  @override
  Future<void> rename(String from, String to) =>
      _op(FsOpKind.rename, from, () => inner.rename(from, to), to: to);

  @override
  Future<void> deleteFile(String path) =>
      _op(FsOpKind.deleteFile, path, () => inner.deleteFile(path));

  @override
  Future<void> deleteDir(String path) =>
      _op(FsOpKind.deleteDir, path, () => inner.deleteDir(path));

  @override
  Future<DateTime?> modified(String path) =>
      _op(FsOpKind.modified, path, () => inner.modified(path));
}

class _FaultHandle implements JournalWriteHandle {
  _FaultHandle(this._fs, this._inner, this._path);

  final FaultInjectingJournalFileSystem _fs;
  final JournalWriteHandle _inner;
  final String _path;

  @override
  Future<void> write(Uint8List bytes) => _fs._op(
        FsOpKind.write,
        _path,
        () => _inner.write(bytes),
        partial: () => _inner.write(bytes.sublist(0, bytes.length ~/ 2)),
      );

  @override
  Future<void> flush() => _fs._op(FsOpKind.flush, _path, _inner.flush);

  @override
  Future<void> fsync() => _fs._op(FsOpKind.fsync, _path, _inner.fsync);

  @override
  Future<void> close() => _fs._op(FsOpKind.close, _path, _inner.close);
}
