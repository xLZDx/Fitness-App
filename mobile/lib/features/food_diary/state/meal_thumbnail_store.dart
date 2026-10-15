/// Optional private meal thumbnail (design s17.2, C24): a small JPEG encrypted
/// with the EXISTING progress-photo cipher, kept ON THIS DEVICE ONLY under
/// `<per-uid photo dir>/meals/<entryId>.bin` and deleted with its diary entry.
/// Nothing here is ever uploaded. The per-uid photo directory is already wiped
/// by the account-deletion flow, which covers this subfolder.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress_photos/data/photo_encryption.dart';
import '../../progress_photos/state/progress_photos_providers.dart';

class MealThumbnailStore {
  MealThumbnailStore({required this.dir, required this.cipher});

  /// The `meals/` directory.
  final Directory dir;
  final PhotoCipher cipher;

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  File? _file(String entryId) =>
      _safeId.hasMatch(entryId) ? File('${dir.path}/$entryId.bin') : null;

  /// Encrypts and writes [jpeg]; false for an unusable id.
  Future<bool> put(String entryId, Uint8List jpeg) async {
    final f = _file(entryId);
    if (f == null) return false;
    await dir.create(recursive: true);
    await f.writeAsBytes(cipher.encrypt(jpeg).toBytes(), flush: true);
    return true;
  }

  /// Decrypted bytes, or null when absent / unreadable / wrong key.
  Future<Uint8List?> read(String entryId) async {
    final f = _file(entryId);
    if (f == null || !await f.exists()) return null;
    try {
      return cipher.decrypt(PhotoEnvelope.fromBytes(await f.readAsBytes()));
    } catch (_) {
      return null;
    }
  }

  Future<bool> exists(String entryId) async {
    final f = _file(entryId);
    return f != null && await f.exists();
  }

  /// Removes the thumbnail of [entryId]; absent is fine.
  Future<void> delete(String entryId) async {
    final f = _file(entryId);
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // A short-lived handle; the next prune retries.
    }
  }

  /// Deletes every thumbnail whose entry id is not in [keepIds] (orphans of an
  /// entry deleted on another device or before this store existed).
  Future<int> pruneExcept(Set<String> keepIds) async {
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!name.endsWith('.bin')) continue;
      if (keepIds.contains(name.substring(0, name.length - 4))) continue;
      await e.delete();
      removed++;
    }
    return removed;
  }
}

/// The store for the signed-in account, or null when signed out / no key.
final mealThumbnailStoreProvider = FutureProvider<MealThumbnailStore?>((ref) async {
  final store = await ref.watch(progressPhotosStoreProvider.future);
  if (store == null) return null;
  return MealThumbnailStore(
    dir: Directory('${store.dir.path}/meals'),
    cipher: store.cipher,
  );
});

/// Deletes the thumbnail of a diary entry; best effort, never throws. A
/// provider so tests of the diary actions can override it.
final mealThumbnailDeleterProvider =
    Provider<Future<void> Function(String entryId)>((ref) {
  return (entryId) async {
    try {
      final store = await ref.read(mealThumbnailStoreProvider.future);
      await store?.delete(entryId);
    } catch (_) {
      // No store (signed out, key store unavailable): nothing to delete.
    }
  };
});
