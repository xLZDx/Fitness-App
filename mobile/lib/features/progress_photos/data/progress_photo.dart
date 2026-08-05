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
}

enum ProgressPhotoAngle { front, side, back, custom }
