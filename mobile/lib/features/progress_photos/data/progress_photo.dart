/// A user-controlled progress photo. Stored client-encrypted in Firebase
/// Storage; the encryption key never leaves the device. The metadata
/// document at `users/{uid}/progress_photos/{id}` keeps the storage path,
/// timestamp, and a *non-secret* fingerprint of the key so we can warn
/// the user before they wipe the device key.
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
