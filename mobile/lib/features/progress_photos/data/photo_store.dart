import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'photo_encryption.dart';
import 'progress_photo.dart';

/// On-device encrypted photo store.
///
/// Layout under [dir]:
///
/// ```
///   index.json       metadata for every photo, plaintext
///   <id>.bin         one AES-GCM envelope per photo
/// ```
///
/// The index is deliberately NOT encrypted. It holds dates, angles, an
/// optional weight and an optional note — the same facts the app already
/// writes to Firestore unencrypted for every workout. Encrypting it would buy
/// nothing (the key sits on the same device, see [PhotoKeyStore]) while making
/// the timeline unreadable if a single envelope corrupts. The pixels are the
/// sensitive part and the pixels are what gets encrypted.
///
/// [dir] is injected rather than resolved from `path_provider` inside, so
/// tests run against a real temp directory and exercise the real file I/O
/// instead of a mock that cannot reproduce a partial write.
class PhotoStore {
  PhotoStore({required this.dir, required this.cipher});

  final Directory dir;
  final PhotoCipher cipher;

  File get _indexFile => File('${dir.path}/index.json');
  File _blobFile(String id) => File('${dir.path}/$id.bin');

  /// Reads the metadata index, oldest first. Returns empty when the store has
  /// never been written.
  Future<List<ProgressPhoto>> index() async {
    if (!await _indexFile.exists()) return const [];
    final raw = await _indexFile.readAsString();
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <ProgressPhoto>[];
    for (final e in decoded) {
      if (e is Map<String, dynamic>) out.add(_fromJson(e));
    }
    out.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return List.unmodifiable(out);
  }

  /// Encrypts [bytes] and appends a record.
  ///
  /// The blob is written before the index. If the process dies between the
  /// two, the result is an orphan `.bin` that nothing references — wasted
  /// bytes, recoverable by [prune]. The other order would leave an index row
  /// pointing at a file that does not exist, which is a broken tile in the
  /// timeline and a crash in the compare view.
  Future<ProgressPhoto> put(
    Uint8List bytes, {
    required DateTime takenAt,
    ProgressPhotoAngle angle = ProgressPhotoAngle.front,
    double? weightKg,
    double? bodyFatPercent,
    String? note,
    String? id,
  }) async {
    await dir.create(recursive: true);
    final photoId = id ?? 'p_${takenAt.microsecondsSinceEpoch}';
    final envelope = cipher.encrypt(bytes);
    await _blobFile(photoId).writeAsBytes(envelope.toBytes(), flush: true);

    final photo = ProgressPhoto(
      id: photoId,
      takenAt: takenAt,
      storagePath: _blobFile(photoId).path,
      keyFingerprint: cipher.fingerprint(),
      angle: angle,
      weightKg: weightKg,
      bodyFatPercent: bodyFatPercent,
      note: note,
    );
    final all = [...await index(), photo];
    await _writeIndex(all);
    return photo;
  }

  /// Decrypts and returns the pixels for [photo].
  ///
  /// Throws [StateError] when the key that wrote the blob is not the key we
  /// hold now. That happens after a reinstall or a cleared app-data: the
  /// index survives a backup, the key does not. Callers surface it as "this
  /// photo was encrypted with a key this device no longer has" rather than as
  /// a generic decode failure, because the two need different user actions.
  Future<Uint8List> read(ProgressPhoto photo) async {
    final file = _blobFile(photo.id);
    if (!await file.exists()) {
      throw StateError('Photo blob missing: ${photo.id}');
    }
    if (photo.keyFingerprint != cipher.fingerprint()) {
      throw StateError(
        'Photo ${photo.id} was encrypted with key ${photo.keyFingerprint}; '
        'this device holds ${cipher.fingerprint()}.',
      );
    }
    final raw = await file.readAsBytes();
    return cipher.decrypt(PhotoEnvelope.fromBytes(raw));
  }

  Future<void> remove(String id) async {
    final file = _blobFile(id);
    if (await file.exists()) await file.delete();
    final all = (await index()).where((p) => p.id != id).toList();
    await _writeIndex(all);
  }

  /// Deletes `.bin` files no index row references. Returns how many went.
  Future<int> prune() async {
    if (!await dir.exists()) return 0;
    final known = {for (final p in await index()) '${p.id}.bin'};
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.bin') || known.contains(name)) continue;
      await entity.delete();
      removed++;
    }
    return removed;
  }

  Future<void> _writeIndex(List<ProgressPhoto> photos) async {
    await dir.create(recursive: true);
    final json = photos.map(_toJson).toList();
    await _indexFile.writeAsString(jsonEncode(json), flush: true);
  }

  static Map<String, dynamic> _toJson(ProgressPhoto p) => {
        'id': p.id,
        'takenAt': p.takenAt.toIso8601String(),
        'storagePath': p.storagePath,
        'keyFingerprint': p.keyFingerprint,
        'angle': p.angle.name,
        if (p.weightKg != null) 'weightKg': p.weightKg,
        if (p.bodyFatPercent != null) 'bodyFatPercent': p.bodyFatPercent,
        if (p.note != null) 'note': p.note,
      };

  static ProgressPhoto _fromJson(Map<String, dynamic> m) => ProgressPhoto(
        id: m['id'] as String,
        takenAt: DateTime.parse(m['takenAt'] as String),
        storagePath: m['storagePath'] as String? ?? '',
        keyFingerprint: m['keyFingerprint'] as String? ?? '',
        angle: ProgressPhotoAngle.values.firstWhere(
          (a) => a.name == m['angle'],
          orElse: () => ProgressPhotoAngle.front,
        ),
        weightKg: (m['weightKg'] as num?)?.toDouble(),
        bodyFatPercent: (m['bodyFatPercent'] as num?)?.toDouble(),
        note: m['note'] as String?,
      );
}
