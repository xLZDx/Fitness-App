import 'visual_equipment_match.dart';

/// Raised when recognition itself failed (model missing, native error,
/// unreadable file) — as opposed to succeeding with no match.
class VisualEquipmentException implements Exception {
  const VisualEquipmentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Bridge to the equipment classifier. The on-device impl ships a TFLite
/// model bundled in assets/models/equipment_v1.tflite; the mock here
/// returns deterministic results so widget tests work.
///
/// File-only on purpose. There used to be a raw-bytes `classify()` that
/// wrapped encoded JPEG in NV21 metadata with hardcoded 640x480 dimensions —
/// on a real device ML Kit rejected it with `InputImageConverterError:
/// Image dimension, ByteBuffer size and format don't match` (operator
/// screenshot, 2026-07-30). The platform file decoder handles format + EXIF
/// rotation; raw bytes cannot.
abstract class VisualEquipmentService {
  /// Classify an image FILE (camera / gallery capture).
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  });
}

/// Implemented only by a service that HAS a fallback and can say when it used
/// one.
///
/// R2.2 state 12. A separate capability interface rather than a member on
/// [VisualEquipmentService], because Dart's `implements` does not inherit
/// concrete members: putting a defaulted getter on the main interface would
/// force every implementation and every test fake to restate it, including
/// the several that have no fallback and nothing to report.
///
/// This is a capability check, not the layering mistake this file's history
/// records elsewhere (a preview downcasting a *detector* to reach a camera).
/// The caller is not reaching through the abstraction for internals — it is
/// asking whether an optional capability is present at all, which is what an
/// `is` check is for.
abstract interface class FallbackReportingRecogniser
    implements VisualEquipmentService {
  /// Whether the LAST `classifyFile` was answered by the on-device fallback
  /// rather than the primary (cloud) recogniser.
  ///
  /// Read immediately after an awaited call; it describes that call.
  bool get lastAnsweredOffline;
}

class MockVisualEquipmentService implements VisualEquipmentService {
  MockVisualEquipmentService({this.fixedResults = const []});
  final List<VisualMatch> fixedResults;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    if (fixedResults.isNotEmpty) {
      return rankTopK(fixedResults, limit: topK);
    }
    // Deterministic seed based on path length so tests are stable.
    final id = (path.length % 4 == 0) ? 'squat_rack' : 'barbell';
    return rankTopK([
      VisualMatch(equipmentId: id, confidence: 0.7),
      VisualMatch(equipmentId: 'kettlebell', confidence: 0.2),
      VisualMatch(equipmentId: 'dumbbell', confidence: 0.1),
    ], limit: topK);
  }
}
