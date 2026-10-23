import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Device-side persistence of an unfinished server export, so an interrupted
/// run (app killed, network lost, the server's daily continuation quota reached)
/// can be RESUMED later instead of starting from the first page.
///
/// Layout: numbered part files plus one small manifest.
///  - part 0 is the server's complete first response;
///  - part N (N >= 1) is one continuation page: only the section row lists (and
///    `warnings`) of that page;
///  - the manifest holds the per-section cursors (`paging`), the part count and
///    a timestamp.
///
/// Write order is part first, manifest second. A crash between the two leaves
/// an orphan part that the manifest does not list, and the cursors in the
/// manifest still point before it, so the next run fetches that page again and
/// overwrites the orphan: no row is dropped and none is duplicated.
abstract class ExportProgressStore {
  Future<Map<String, dynamic>?> readManifest();
  Future<void> writeManifest(Map<String, dynamic> manifest);
  Future<Map<String, dynamic>?> readPart(int index);
  Future<void> writePart(int index, Map<String, dynamic> part);

  /// Removes the manifest and every part.
  Future<void> clear();
}

/// Default (and test) store: lives only as long as the process.
class InMemoryExportProgressStore implements ExportProgressStore {
  Map<String, dynamic>? manifest;
  final parts = <int, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> readManifest() async => manifest;

  @override
  Future<void> writeManifest(Map<String, dynamic> m) async {
    manifest = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> readPart(int index) async => parts[index];

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    parts[index] = jsonDecode(jsonEncode(part)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    manifest = null;
    parts.clear();
  }
}

/// Files in the app's private support directory (not the temp/cache directory,
/// which the OS may purge mid-export, and not a shared location: the parts hold
/// the user's own data).
class FileExportProgressStore implements ExportProgressStore {
  FileExportProgressStore({Future<Directory> Function()? baseDir})
      : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/server_export_progress');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _partName(int i) => 'part_${i.toString().padLeft(5, '0')}.json';

  Future<Map<String, dynamic>?> _read(String name) async {
    final file = File('${(await _dir()).path}/$name');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Temp file + rename, so a crash never leaves a half-written file under the
  /// final name.
  Future<void> _write(String name, Map<String, dynamic> value) async {
    final dir = await _dir();
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename('${dir.path}/$name');
  }

  @override
  Future<Map<String, dynamic>?> readManifest() => _read('manifest.json');

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) =>
      _write('manifest.json', manifest);

  @override
  Future<Map<String, dynamic>?> readPart(int index) => _read(_partName(index));

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) =>
      _write(_partName(index), part);

  @override
  Future<void> clear() async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/server_export_progress');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

final exportProgressStoreProvider = Provider<ExportProgressStore>(
    (_) => InMemoryExportProgressStore());
