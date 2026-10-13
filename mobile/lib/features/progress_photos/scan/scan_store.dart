import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/photo_encryption.dart';
import 'scan_models.dart';

/// Encrypted on-disk store for [ScanRecord]s.
///
/// Layout, inside the account's photo directory (`<docs>/progress_photos/<uid>/`):
///
/// ```
///   scans/<id>.scan    one AES-GCM envelope holding the whole record as JSON
/// ```
///
/// There is deliberately NO plaintext index: the file name is the only
/// plaintext (an opaque id), and the creation time, photo ids and landmarks
/// all live inside the envelope. Landmarks are body-shape data and must never
/// reach the plaintext `index.json` of the photo store.
///
/// Because the sidecar sits under the per-uid directory, the account-deletion
/// wipe (which deletes that whole directory) erases it with the photos.
class ScanStore {
  ScanStore({required this.dir, required this.cipher});

  /// The account's photo directory (the one that holds `index.json`).
  final Directory dir;
  final PhotoCipher cipher;

  static const folderName = 'scans';
  static const extension = '.scan';

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  Directory get _scansDir => Directory('${dir.path}/$folderName');

  File _file(String id) {
    // The id becomes a file name; refuse anything that could leave the folder.
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'not a safe scan id');
    }
    return File('${_scansDir.path}/$id$extension');
  }

  /// Writes (or replaces) the record. Temp file + rename, so a crash never
  /// leaves a half-written sidecar under the real name.
  Future<void> save(ScanRecord record) async {
    final target = _file(record.id);
    await _scansDir.create(recursive: true);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(record.toJson())));
    final bytes = cipher.encrypt(plain).toBytes();
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  /// Newest first. A sidecar that cannot be read (corrupt, or sealed with a
  /// key this device no longer holds) is skipped, not fatal.
  Future<List<ScanRecord>> list() async {
    if (!await _scansDir.exists()) return const [];
    final out = <ScanRecord>[];
    await for (final e in _scansDir.list()) {
      if (e is! File || !e.path.endsWith(extension)) continue;
      try {
        final plain = cipher.decrypt(PhotoEnvelope.fromBytes(await e.readAsBytes()));
        final rec = ScanRecord.tryFromJson(jsonDecode(utf8.decode(plain)));
        if (rec != null) out.add(rec);
      } catch (err) {
        debugPrint('scan store: unreadable sidecar skipped (${err.runtimeType})');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(out);
  }

  /// Deletes the landmark sidecar. Idempotent.
  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}
