import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

// Where one account's encrypted photos live, and the one-time move of the
// pre-A2-sec install-wide folder into it.
//
// Before A2-sec every account on a device shared `<docs>/progress_photos/`
// and one AES key. Sign out, sign in as someone else, open the Photos tab,
// and the timeline that appeared was the previous person's — the folder had
// no idea whose it was. The layout is now:
//
//   <docs>/progress_photos/<uid>/index.json
//   <docs>/progress_photos/<uid>/<id>.bin
//
// The per-account folder stays UNDER `progress_photos/` on purpose: the
// account-deletion wipe deletes that account's subdirectory, and the
// pre-existing "delete the whole tree" behaviour still means "no photos
// remain" if it is ever reached.

/// Records which account absorbed the legacy folder. Its presence — not the
/// folder's absence — is what makes the migration one-time, so an account that
/// legitimately has no photos never re-triggers it.
const kLegacyPhotoMigrationMarker = 'progress_photos.legacy_migrated_to';

/// The directory for [uid], with the legacy folder folded in if this is the
/// first account to ask since the upgrade.
///
/// ## Why the first account inherits, rather than nobody
///
/// The legacy folder carries no record of whose photos it holds, so there are
/// exactly three options: give it to the first account that opens the feature
/// after the upgrade, delete it, or leave it stranded and invisible. Deleting
/// destroys a user's own data to close a window; stranding does the same thing
/// while also leaving the plaintext-adjacent key in place. Adopting keeps the
/// photos working for the overwhelmingly likely case (one person, one phone)
/// and shrinks the shared-folder bug from "every future account" to "the one
/// account that migrates". That residual window is stated rather than hidden,
/// and it closes the moment the marker is written.
Future<Directory> resolvePhotoDir({
  required Directory documents,
  required String uid,
  SharedPreferences? prefs,
}) async {
  final root = Directory('${documents.path}/progress_photos');
  final scoped = Directory('${root.path}/$uid');
  await scoped.create(recursive: true);

  final store = prefs ?? await SharedPreferences.getInstance();
  if (store.getString(kLegacyPhotoMigrationMarker) != null) return scoped;

  try {
    await _absorbLegacy(root: root, scoped: scoped);
  } catch (e) {
    // A half-moved folder is recoverable (the marker is not written, so the
    // next launch retries); a photos tab that throws on open is not.
    debugPrint('progress photos: legacy folder not migrated: $e');
    return scoped;
  }
  await store.setString(kLegacyPhotoMigrationMarker, uid);
  return scoped;
}

/// Moves loose `index.json` + `*.bin` from [root] into [scoped].
Future<void> _absorbLegacy({
  required Directory root,
  required Directory scoped,
}) async {
  final legacyIndex = File('${root.path}/index.json');
  if (!await legacyIndex.exists()) return;

  // Blobs first. An index that arrives before its blobs is a timeline of
  // tiles that throw; blobs before the index are invisible bytes that the
  // store's own `prune()` cleans up.
  await for (final entity in root.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.bin')) continue;
    await entity.rename('${scoped.path}/$name');
  }

  // `storagePath` inside each row still points at the old location. Nothing
  // reads it to open a file — `PhotoStore` derives the path from its own
  // directory — but it IS what the GDPR export prints, and an export naming a
  // path that does not exist is a small lie in a document whose whole purpose
  // is being accurate.
  final rewritten = await _rewriteStoragePaths(legacyIndex, scoped);
  await File('${scoped.path}/index.json').writeAsString(rewritten, flush: true);
  await legacyIndex.delete();
}

Future<String> _rewriteStoragePaths(File index, Directory scoped) async {
  final raw = await index.readAsString();
  if (raw.trim().isEmpty) return '[]';
  final decoded = jsonDecode(raw);
  if (decoded is! List) return '[]';
  for (final row in decoded) {
    if (row is! Map) continue;
    final id = row['id'];
    if (id is String) row['storagePath'] = '${scoped.path}/$id.bin';
  }
  return jsonEncode(decoded);
}
