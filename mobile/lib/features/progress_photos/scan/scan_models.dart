/// Data model of one saved guided body scan.
///
/// Holds NO pixels: each shot points at an existing encrypted `ProgressPhoto`
/// by id, and carries the pose landmarks that were measured on it. Landmarks
/// are body-shape data, so they only ever leave memory inside the encrypted
/// sidecar (see `scan_store.dart`), never in the plaintext photo index.
library;

import '../../body_scan/data/body_fat_estimate.dart';
import '../../body_scan/data/body_scan_job.dart';
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

/// The analysis block of a v2 record (design s10): the persisted job state of
/// the offline queue plus, for the on-device provisional estimator, the
/// locally computed estimate (D-52). Closed slugs only: never a raw exception
/// message (D-67).
class ScanAnalysis {
  const ScanAnalysis({
    required this.status,
    this.attempt = 0,
    this.remoteId,
    this.remoteStatus,
    this.lastError,
    this.estimate,
    this.updatedAt,
  });

  /// A freshly saved scan waiting for its analysis.
  const ScanAnalysis.queued() : this(status: JobStatus.queued);

  final JobStatus status;

  /// Failed attempts so far.
  final int attempt;

  /// Server scan id; null means "the local id". Rotated to `<id>_r<n>` after a
  /// server `scan-cancelled`.
  final String? remoteId;
  final String? remoteStatus;
  final String? lastError;

  /// The locally computed provisional estimate.
  final BodyFatEstimate? estimate;
  final DateTime? updatedAt;

  ScanAnalysis copyWith({
    JobStatus? status,
    int? attempt,
    String? remoteId,
    String? remoteStatus,
    String? lastError,
    BodyFatEstimate? estimate,
    DateTime? updatedAt,
    bool clearLastError = false,
  }) =>
      ScanAnalysis(
        status: status ?? this.status,
        attempt: attempt ?? this.attempt,
        remoteId: remoteId ?? this.remoteId,
        remoteStatus: remoteStatus ?? this.remoteStatus,
        lastError: clearLastError ? null : (lastError ?? this.lastError),
        estimate: estimate ?? this.estimate,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'status': status.name,
        'attempt': attempt,
        if (remoteId != null) 'remoteId': remoteId,
        if (remoteStatus != null) 'remoteStatus': remoteStatus,
        if (lastError != null) 'lastError': lastError,
        if (estimate != null) 'estimate': estimate!.toJson(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  /// Tolerant read; an unknown status reads as `failed` (never auto-resumed).
  static ScanAnalysis? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final attempt = raw['attempt'];
    final remoteId = raw['remoteId'];
    final remoteStatus = raw['remoteStatus'];
    final lastError = raw['lastError'];
    final updated = raw['updatedAt'];
    return ScanAnalysis(
      status: JobStatus.parse(raw['status']),
      attempt: attempt is int && attempt >= 0 ? attempt : 0,
      remoteId: remoteId is String && remoteId.isNotEmpty ? remoteId : null,
      remoteStatus: remoteStatus is String ? remoteStatus : null,
      lastError: lastError is String ? lastError : null,
      estimate: BodyFatEstimate.tryFromJson(raw['estimate']),
      updatedAt: updated is String ? DateTime.tryParse(updated)?.toLocal() : null,
    );
  }
}

/// A saved scan: up to three shots keyed by pose.
///
/// v2 (design s10) adds [analysis], [weightKg], [manualOverride] and
/// [pendingRemoteDelete]. A v1 record has no [analysis]: it is a LEGACY
/// local-only scan and is never auto-uploaded (D-6).
class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.createdAt,
    required this.shots,
    this.analysis,
    this.weightKg,
    this.manualOverride = const {},
    this.pendingRemoteDelete = false,
  });

  final String id;
  final DateTime createdAt;
  final Map<ScanPose, ScanShot> shots;

  /// Null for a v1 (legacy) record.
  final ScanAnalysis? analysis;

  /// The weight recorded with this scan.
  final double? weightKg;

  /// Per pose: the manual shutter fired while readiness was not green.
  final Map<ScanPose, bool> manualOverride;

  /// A server delete is owed (queued while offline).
  final bool pendingRemoteDelete;

  /// True for a v1 scan: local only, never uploaded.
  bool get isLegacy => analysis == null;

  /// True when any pose was captured with the manual shutter while not ready.
  bool get anyManualOverride => manualOverride.values.any((v) => v);

  /// The server scan id: the local id unless rotated after `scan-cancelled`.
  String get remoteId => analysis?.remoteId ?? id;

  ScanRecord copyWith({
    ScanAnalysis? analysis,
    double? weightKg,
    Map<ScanPose, bool>? manualOverride,
    bool? pendingRemoteDelete,
  }) =>
      ScanRecord(
        id: id,
        createdAt: createdAt,
        shots: shots,
        analysis: analysis ?? this.analysis,
        weightKg: weightKg ?? this.weightKg,
        manualOverride: manualOverride ?? this.manualOverride,
        pendingRemoteDelete: pendingRemoteDelete ?? this.pendingRemoteDelete,
      );

  Map<String, Object?> toJson() => {
        'v': 2,
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'shots': {for (final e in shots.entries) e.key.name: e.value.toJson()},
        if (analysis != null) 'analysis': analysis!.toJson(),
        if (weightKg != null) 'weightKg': weightKg,
        'capture': {
          'manualOverride': {
            for (final p in ScanPose.ordered) p.name: manualOverride[p] ?? false,
          },
        },
        if (pendingRemoteDelete) 'pendingRemoteDelete': true,
      };

  /// Null when the payload is not a well-formed v1 or v2 record.
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
    final w = raw['weightKg'];
    final capture = raw['capture'];
    final overrideRaw = capture is Map ? capture['manualOverride'] : null;
    return ScanRecord(
      id: id,
      createdAt: at.toLocal(),
      shots: shots,
      analysis: ScanAnalysis.tryFromJson(raw['analysis']),
      weightKg: w is num && w.isFinite ? w.toDouble() : null,
      manualOverride: {
        if (overrideRaw is Map)
          for (final p in ScanPose.ordered)
            if (overrideRaw[p.name] == true) p: true,
      },
      pendingRemoteDelete: raw['pendingRemoteDelete'] == true,
    );
  }
}
