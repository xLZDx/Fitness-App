/// The client view of a server `body_scans/{scanId}` document (design s5.1).
/// Pure Dart, no Flutter imports. CLOUD PATH ONLY: scans measured by the
/// provisional estimator live in the encrypted local record and never produce
/// one of these (D-52).
library;

import 'body_fat_estimate.dart';

/// Server-side status of the document.
enum ScanDocStatus {
  pending,
  done,
  failed,
  cancelled;

  /// Unknown names read as [failed]: never shown as a result.
  static ScanDocStatus parse(Object? name) {
    if (name is String) {
      for (final s in values) {
        if (s.name == name) return s;
      }
    }
    return ScanDocStatus.failed;
  }
}

/// Where the photos are.
enum PhotosState {
  none,
  awaitingUpload,
  stored,
  deleted;

  /// Wire names: `none`, `awaiting_upload`, `stored`, `deleted`.
  String get wireName =>
      this == PhotosState.awaitingUpload ? 'awaiting_upload' : name;

  static PhotosState parse(Object? name) {
    if (name is String) {
      for (final s in values) {
        if (s.wireName == name) return s;
      }
    }
    return PhotosState.none;
  }
}

class BodyScanEntry {
  const BodyScanEntry({
    required this.scanId,
    required this.takenAt,
    required this.status,
    required this.photosState,
    this.weightKg,
    this.estimate,
    this.providerId,
    this.clientNote,
  });

  final String scanId;
  final DateTime takenAt;
  final ScanDocStatus status;
  final PhotosState photosState;
  final double? weightKg;
  final BodyFatEstimate? estimate;
  final String? providerId;
  final String? clientNote;

  /// Only a `done` scan with a readable estimate is a result.
  bool get hasResult => status == ScanDocStatus.done && estimate != null;

  /// Tolerant read of a document map; `at` fields may be [DateTime] or ISO
  /// strings (the Firestore mapping converts timestamps before calling this).
  /// Null when the document cannot be a scan entry.
  static BodyScanEntry? tryFromJson(String scanId, Object? raw) {
    if (raw is! Map) return null;
    final taken = _date(raw['takenAt']);
    if (taken == null) return null;
    final w = raw['weightKg'];
    final provider = raw['provider'];
    final note = raw['clientNote'];
    final est = raw['estimate'];
    return BodyScanEntry(
      scanId: scanId,
      takenAt: taken,
      status: ScanDocStatus.parse(raw['status']),
      photosState: PhotosState.parse(raw['photosState']),
      weightKg: w is num ? w.toDouble() : null,
      estimate: BodyFatEstimate.tryFromJson(
        est is Map ? {...est, 'provisional': _providerProvisional(provider)} : null,
      ),
      providerId: provider is Map && provider['id'] is String
          ? provider['id'] as String
          : null,
      clientNote: note is String ? note : null,
    );
  }

  static bool _providerProvisional(Object? provider) =>
      provider is Map && provider['provisional'] == true;

  static DateTime? _date(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
