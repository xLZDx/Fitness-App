import 'visual_equipment_match.dart';

/// Bridge to the on-device equipment classifier. The real impl ships
/// a TFLite model bundled in assets/models/equipment_v1.tflite; the
/// mock here returns deterministic results so widget tests work.
abstract class VisualEquipmentService {
  /// Classify the image bytes (encoded JPEG / PNG). Returns top-K matches
  /// post-normalisation.
  Future<List<VisualMatch>> classify({
    required List<int> imageBytes,
    int topK = 3,
  });

  /// Classify an image FILE (camera / gallery capture). Preferred over
  /// [classify] for picked photos: the platform decoder handles JPEG
  /// format + EXIF rotation, which raw-bytes paths cannot.
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  });
}

class MockVisualEquipmentService implements VisualEquipmentService {
  MockVisualEquipmentService({this.fixedResults = const []});
  final List<VisualMatch> fixedResults;

  @override
  Future<List<VisualMatch>> classify({
    required List<int> imageBytes,
    int topK = 3,
  }) async {
    if (fixedResults.isNotEmpty) {
      return normaliseAndTopK(fixedResults, limit: topK);
    }
    // Deterministic seed based on byte length so tests are stable.
    final id = (imageBytes.length % 4 == 0) ? 'squat_rack' : 'barbell';
    return normaliseAndTopK([
      VisualMatch(equipmentId: id, confidence: 0.7),
      VisualMatch(equipmentId: 'kettlebell', confidence: 0.2),
      VisualMatch(equipmentId: 'dumbbell', confidence: 0.1),
    ], limit: topK);
  }

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) =>
      classify(imageBytes: path.codeUnits, topK: topK);
}
