import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Saved progress older than this is discarded (cursors may be stale).
const Duration kExportProgressMaxAge = Duration(days: 7);

/// Directory (inside the app support directory) that holds every user's export
/// progress. Each user has ONE sub-directory named by [exportProgressUserKey].
const String kExportProgressDirName = 'server_export_progress';

/// Directory name of one user's progress: a hash, never the raw uid.
String exportProgressUserKey(String uid) =>
    'u_${sha256.convert(utf8.encode(uid)).toString().substring(0, 32)}';

/// Device-side persistence of an unfinished server export, so an interrupted
/// run (app killed, network lost, the server's daily continuation quota reached)
/// can be RESUMED later instead of starting from the first page, and so a run
/// never has to hold its rows in memory.
///
/// A store is scoped to one user with [forUser]; the file implementation keeps
/// each user's files in `server_export_progress/<exportProgressUserKey(uid)>/`.
///
/// Layout of one user's progress:
///  - `base.json`: the server's first response WITHOUT the rows of the paged
///    sections (profile, subscription, ... : one bounded page);
///  - one part per fetched page: `part_NNNNN.<section>.ndjson` holds that page's
///    rows of one section (one JSON row per line) and `part_NNNNN.done` is the
///    part's commit record (section -> byte length);
///  - `manifest.json`: per-section cursors (`paging`), part count, row counts,
///    warnings and a timestamp (small, no rows).
///
/// Write order is base, part files, part commit record, manifest LAST. A crash
/// before the manifest leaves an orphan part that the manifest does not list;
/// the cursors in the manifest still point before it, so the next run fetches
/// that page again and [writePart] replaces the orphan: no row is dropped and
/// none is duplicated. Every write is temp file + flush + rename. A failed write
/// THROWS: the collector turns it into an explicit storage error, it is never
/// swallowed.
abstract class ExportProgressStore {
  /// This store scoped to [uid]. Idempotent. The in-memory store ignores it.
  ExportProgressStore forUser(String uid);

  Future<Map<String, dynamic>?> readManifest();
  Future<void> writeManifest(Map<String, dynamic> manifest);

  Future<Map<String, dynamic>?> readBase();
  Future<void> writeBase(Map<String, dynamic> base);

  /// Persists page [index]: `{section: [row, ...]}`. Replaces any earlier part
  /// with the same index (an orphan of a crashed run).
  Future<void> writePart(int index, Map<String, dynamic> part);

  /// True when part [index] exists and is intact.
  Future<bool> hasPart(int index);

  /// The rows of [section] over parts `0 .. parts-1`, in order, decoded one at a
  /// time (the rows are never all in memory).
  Stream<Object?> readRows(String section, int parts);

  /// Removes everything of the scoped user (an unscoped file store: every user).
  Future<void> clear();

  /// Deletes progress that must not stay on the device: with [keepUid], every
  /// OTHER user's progress and any unrecognised leftover; without it, only
  /// progress that is expired, already delivered or unreadable. The kept user's
  /// own progress is judged by `loadExportResume`. Attempts every entry, then
  /// throws if one could not be removed.
  Future<void> purgeStale({String? keepUid, DateTime? now});
}

/// Default (and test) store: lives only as long as the process.
class InMemoryExportProgressStore implements ExportProgressStore {
  Map<String, dynamic>? manifest;
  Map<String, dynamic>? base;
  final parts = <int, Map<String, dynamic>>{};

  @override
  ExportProgressStore forUser(String uid) => this;

  @override
  Future<Map<String, dynamic>?> readManifest() async => manifest;

  @override
  Future<void> writeManifest(Map<String, dynamic> m) async {
    manifest = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> readBase() async => base;

  @override
  Future<void> writeBase(Map<String, dynamic> b) async {
    base = jsonDecode(jsonEncode(b)) as Map<String, dynamic>;
  }

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    parts[index] = jsonDecode(jsonEncode(part)) as Map<String, dynamic>;
  }

  @override
  Future<bool> hasPart(int index) async => parts.containsKey(index);

  @override
  Stream<Object?> readRows(String section, int count) async* {
    for (var i = 0; i < count; i++) {
      final part = parts[i];
      if (part == null) throw StateError('export progress part $i is missing');
      final rows = part[section];
      if (rows is List) {
        for (final row in rows) {
          yield row;
        }
      }
    }
  }

  @override
  Future<void> clear() async {
    manifest = null;
    base = null;
    parts.clear();
  }

  @override
  Future<void> purgeStale({String? keepUid, DateTime? now}) async {
    final m = manifest;
    if (m != null && keepUid != null && m['uid'] != keepUid) await clear();
  }
}

/// Files in the app's private support directory (not the temp/cache directory,
/// which the OS may purge mid-export, and not a shared location: the parts hold
/// the user's own data).
class FileExportProgressStore implements ExportProgressStore {
  FileExportProgressStore({Future<Directory> Function()? baseDir, String? uid})
      : _baseDir = baseDir ?? getApplicationSupportDirectory,
        _uid = uid;

  final Future<Directory> Function() _baseDir;
  final String? _uid;

  @override
  ExportProgressStore forUser(String uid) =>
      FileExportProgressStore(baseDir: _baseDir, uid: uid);

  Future<Directory> _root() async =>
      Directory('${(await _baseDir()).path}/$kExportProgressDirName');

  Future<Directory> _userDir() async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('export progress store is not scoped to a user');
    }
    return Directory('${(await _root()).path}/${exportProgressUserKey(uid)}');
  }

  Future<Directory> _ensureDir() async {
    final dir = await _userDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _prefix(int i) => 'part_${i.toString().padLeft(5, '0')}';
  static String _sectionFile(int i, String section) =>
      '${_prefix(i)}.${Uri.encodeComponent(section)}.ndjson';

  Future<Map<String, dynamic>?> _readJson(String name) async {
    final file = File('${(await _userDir()).path}/$name');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Temp file + flush + rename, so a crash never leaves a half-written file
  /// under the final name.
  Future<void> _writeText(String name, String text) async {
    final dir = await _ensureDir();
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename('${dir.path}/$name');
  }

  @override
  Future<Map<String, dynamic>?> readManifest() => _readJson('manifest.json');

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) =>
      _writeText('manifest.json', jsonEncode(manifest));

  @override
  Future<Map<String, dynamic>?> readBase() => _readJson('base.json');

  @override
  Future<void> writeBase(Map<String, dynamic> base) =>
      _writeText('base.json', jsonEncode(base));

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    final dir = await _ensureDir();
    // An orphan of a crashed run with this index is replaced as a whole, so a
    // section that the refetched page does not carry cannot survive from it.
    final prefix = '${_prefix(index)}.';
    await for (final e in dir.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith(prefix)) await e.delete();
    }
    final sizes = <String, int>{};
    for (final e in part.entries) {
      final rows = e.value;
      if (rows is! List || rows.isEmpty) continue;
      final text = StringBuffer();
      for (final row in rows) {
        text
          ..write(jsonEncode(row))
          ..write('\n');
      }
      final s = text.toString();
      await _writeText(_sectionFile(index, e.key), s);
      sizes[e.key] = utf8.encode(s).length;
    }
    // The commit record of the part, written last.
    await _writeText('${_prefix(index)}.done', jsonEncode({'sections': sizes}));
  }

  Future<Map<String, int>?> _partSections(int index) async {
    final done = await _readJson('${_prefix(index)}.done');
    final sections = done?['sections'];
    if (sections is! Map) return null;
    return {
      for (final e in sections.entries)
        if (e.value is int) e.key as String: e.value as int,
    };
  }

  @override
  Future<bool> hasPart(int index) async {
    try {
      final sections = await _partSections(index);
      if (sections == null) return false;
      final dir = await _userDir();
      for (final e in sections.entries) {
        final f = File('${dir.path}/${_sectionFile(index, e.key)}');
        if (!await f.exists() || await f.length() != e.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Object?> readRows(String section, int parts) async* {
    final dir = await _userDir();
    for (var i = 0; i < parts; i++) {
      final sections = await _partSections(i);
      if (sections == null) {
        throw FileSystemException('export progress part $i is missing');
      }
      if (!sections.containsKey(section)) continue;
      final file = File('${dir.path}/${_sectionFile(i, section)}');
      await for (final line in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isNotEmpty) yield jsonDecode(line);
      }
    }
  }

  @override
  Future<void> clear() async {
    final dir = _uid == null ? await _root() : await _userDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<bool> _isStale(FileSystemEntity entry, DateTime now) async {
    // Anything that is not a user directory (e.g. the flat layout of an earlier
    // build) is not ours to keep.
    if (entry is! Directory) return true;
    try {
      final file = File('${entry.path}/manifest.json');
      if (!await file.exists()) return true;
      final m = jsonDecode(await file.readAsString());
      if (m is! Map) return true;
      if (m['delivered'] == true) return true;
      final savedAt = m['savedAtMs'];
      if (savedAt is! int) return true;
      return now.millisecondsSinceEpoch - savedAt >=
          kExportProgressMaxAge.inMilliseconds;
    } catch (_) {
      return true; // unreadable progress can never be resumed
    }
  }

  @override
  Future<void> purgeStale({String? keepUid, DateTime? now}) async {
    final root = await _root();
    if (!await root.exists()) return;
    final keep = keepUid == null ? null : exportProgressUserKey(keepUid);
    final clock = now ?? DateTime.now();
    Object? firstError;
    await for (final e in root.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (keep != null && name == keep) continue;
      try {
        if (keepUid != null || await _isStale(e, clock)) {
          await e.delete(recursive: true);
        }
      } catch (err) {
        firstError ??= err;
      }
    }
    if (firstError != null) {
      throw FileSystemException(
          'could not remove stale export progress (${firstError.runtimeType})');
    }
  }
}

/// Removes ONE user's export progress under the app support directory
/// [supportDir] (account deletion). A missing directory is success; a failure
/// throws so the caller can report an incomplete wipe.
Future<void> deleteExportProgressFor(Directory supportDir, String uid) async {
  final dir = Directory(
      '${supportDir.path}/$kExportProgressDirName/${exportProgressUserKey(uid)}');
  if (await dir.exists()) await dir.delete(recursive: true);
}

final exportProgressStoreProvider = Provider<ExportProgressStore>(
    (_) => InMemoryExportProgressStore());
