/// A user-controlled progress photo.
///
/// This comment described a system that does not exist: client-encrypted
/// blobs in Firebase Storage, a metadata document at
/// `users/{uid}/progress_photos/{id}`, a device key to warn about before a
/// wipe. Nothing writes to Cloud Storage, that collection is not in
/// `firestore.rules`, and there is no key. The only repository bound is
/// `MockProgressPhotosRepository`, which fills [storagePath] with
/// `mock://n.bin` and [keyFingerprint] with `mockfp`.
///
/// Both fields are kept because they are the right shape for the storage
/// layer R7 will build -- an object key and a key-rotation marker -- and
/// changing the model later would churn every reader. Read them as a plan,
/// not as a description.
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.takenAt,
    required this.storagePath,
    required this.keyFingerprint,
    this.angle = ProgressPhotoAngle.front,
    this.weightKg,
    this.bodyFatPercent,
    this.note,
  });

  final String id;
  final DateTime takenAt;
  final String storagePath;

  /// SHA-256 first 8 bytes of the device key, hex. Lets us detect a
  /// "key was overwritten" condition without storing the actual key.
  final String keyFingerprint;
  final ProgressPhotoAngle angle;
  final double? weightKg;
  final double? bodyFatPercent;
  final String? note;

  /// Value equality, and it is load-bearing rather than cosmetic.
  ///
  /// `photoBytesProvider` is a family keyed by this object. Without `==` the
  /// key was identity, and `PhotoStore.index()` rebuilds every [ProgressPhoto]
  /// from JSON on each read -- so a single capture, which invalidates the
  /// stream, gave every existing photo a NEW key. The whole history was
  /// re-decrypted on every shot, and the bytes behind the old keys stayed in
  /// the container with nothing left to reach them.
  ///
  /// Every field, not just [id]: a partial `==` on a plain value object is a
  /// trap for the next reader, who will reasonably assume two equal photos
  /// carry equal metadata.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressPhoto &&
          other.id == id &&
          other.takenAt == takenAt &&
          other.storagePath == storagePath &&
          other.keyFingerprint == keyFingerprint &&
          other.angle == angle &&
          other.weightKg == weightKg &&
          other.bodyFatPercent == bodyFatPercent &&
          other.note == note;

  @override
  int get hashCode => Object.hash(id, takenAt, storagePath, keyFingerprint,
      angle, weightKg, bodyFatPercent, note);
}

enum ProgressPhotoAngle { front, side, back, custom }
