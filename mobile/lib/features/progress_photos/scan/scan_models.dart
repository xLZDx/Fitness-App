/// Data model of one saved guided body scan.
///
/// Holds NO pixels: each shot points at an existing encrypted `ProgressPhoto`
/// by id, and carries the pose landmarks that were measured on it. Landmarks
/// are body-shape data, so they only ever leave memory inside the encrypted
/// sidecar (see `scan_store.dart`), never in the plaintext photo index.
library;

import 'scan_pose.dart';

/// One body landmark, normalised to the image (x and y in 0..1).
class ScanLandmark {
  const ScanLandmark({
    required this.name,
    required this.x,
    required this.y,
    required this.likelihood,
  });

  final String name;
  final double x;
  final double y;
  final double likelihood;

  Map<String, Object?> toJson() =>
      {'n': name, 'x': x, 'y': y, 'l': likelihood};

  static ScanLandmark? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final n = raw['n'];
    final x = raw['x'];
    final y = raw['y'];
    final l = raw['l'];
    if (n is! String || x is! num || y is! num || l is! num) return null;
    return ScanLandmark(
      name: n,
      x: x.toDouble(),
      y: y.toDouble(),
      likelihood: l.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanLandmark &&
      other.name == name &&
      other.x == x &&
      other.y == y &&
      other.likelihood == likelihood;

  @override
  int get hashCode => Object.hash(name, x, y, likelihood);
}

/// One captured pose: the id of the stored photo and its landmarks.
class ScanShot {
  const ScanShot({required this.photoId, required this.landmarks});

  /// Id of the existing encrypted `ProgressPhoto`.
  final String photoId;
  final List<ScanLandmark> landmarks;

  Map<String, Object?> toJson() => {
        'photoId': photoId,
        'landmarks': [for (final l in landmarks) l.toJson()],
      };

  static ScanShot? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['photoId'];
    final lms = raw['landmarks'];
    if (id is! String || id.isEmpty || lms is! List) return null;
    return ScanShot(
      photoId: id,
      landmarks: [
        for (final l in lms)
          if (ScanLandmark.tryFromJson(l) case final ok?) ok,
      ],
    );
  }
}

/// A saved scan: up to three shots keyed by pose.
class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.createdAt,
    required this.shots,
  });

  final String id;
  final DateTime createdAt;
  final Map<ScanPose, ScanShot> shots;

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'shots': {for (final e in shots.entries) e.key.name: e.value.toJson()},
      };

  /// Null when the payload is not a well-formed v1 record.
  static ScanRecord? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final created = raw['createdAt'];
    final shotsRaw = raw['shots'];
    if (id is! String || created is! String || shotsRaw is! Map) return null;
    final at = DateTime.tryParse(created);
    if (at == null) return null;
    final shots = <ScanPose, ScanShot>{};
    for (final pose in ScanPose.ordered) {
      final s = ScanShot.tryFromJson(shotsRaw[pose.name]);
      if (s != null) shots[pose] = s;
    }
    return ScanRecord(id: id, createdAt: at.toLocal(), shots: shots);
  }
}
