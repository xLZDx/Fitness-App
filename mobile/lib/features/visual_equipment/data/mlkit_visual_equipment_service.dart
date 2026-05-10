import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart';

/// Production [VisualEquipmentService] backed by ML Kit's image-labeling
/// pipeline + a custom TFLite model bundled in
/// `assets/models/equipment_v1.tflite`.
///
/// We deliberately use ML Kit's labeling instead of raw `tflite_flutter`
/// because ML Kit handles the rotation / format / Android-vs-iOS preproc
/// for us. The label set our model emits maps onto the catalog's
/// `equipmentId` namespace via [_kLabelMap].
class MlKitVisualEquipmentService implements VisualEquipmentService {
  MlKitVisualEquipmentService({this.modelAssetPath = 'assets/models/equipment_v1.tflite'});

  final String modelAssetPath;
  mlkit.ImageLabeler? _labeler;

  /// Stable mapping of model label → catalog equipmentId. Adding a new
  /// equipment class to the model = add a row here.
  static const Map<String, String> _kLabelMap = {
    'squat_rack': 'squat_rack',
    'barbell': 'barbell',
    'dumbbell': 'dumbbell',
    'kettlebell': 'kettlebell',
    'cable_machine': 'cable_machine',
    'bench': 'bench_press',
    'leg_press': 'leg_press',
    'lat_pulldown': 'lat_pulldown',
    'rowing_machine': 'rowing_machine',
    'treadmill': 'treadmill',
  };

  Future<mlkit.ImageLabeler> _ensureLabeler() async {
    if (_labeler != null) return _labeler!;
    // ML Kit needs an absolute file path on Android; on iOS it accepts
    // bundle URLs. We resolve via path_provider so unit tests stub
    // it cleanly.
    final modelFile = await _resolveModelFile();
    final options = mlkit.LocalLabelerOptions(
      modelPath: modelFile.path,
      confidenceThreshold: 0.10,
      maxCount: 5,
    );
    _labeler = mlkit.ImageLabeler(options: options);
    return _labeler!;
  }

  Future<File> _resolveModelFile() async {
    // Stub path; production unzips assets/models/* to the app's docs
    // dir on first launch and remembers the absolute path. Until the
    // bundling lands, fall back to a non-existent file (callers must
    // guard with the mock service in dev mode).
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/models/equipment_v1.tflite');
  }

  @override
  Future<List<VisualMatch>> classify({
    required List<int> imageBytes,
    int topK = 3,
  }) async {
    try {
      final labeler = await _ensureLabeler();
      final inputImage = mlkit.InputImage.fromBytes(
        bytes: Uint8List.fromList(imageBytes),
        metadata: mlkit.InputImageMetadata(
          // Best-effort defaults; in real use the camera plugin gives us
          // a CameraImage with proper rotation/format and we'd construct
          // the metadata from that.
          size: const Size(640, 480),
          rotation: mlkit.InputImageRotation.rotation0deg,
          format: Platform.isAndroid
              ? mlkit.InputImageFormat.nv21
              : mlkit.InputImageFormat.bgra8888,
          bytesPerRow: 640,
        ),
      );
      final labels = await labeler.processImage(inputImage);
      final raw = <VisualMatch>[];
      for (final l in labels) {
        final id = _kLabelMap[l.label.toLowerCase()];
        if (id == null) continue;
        raw.add(VisualMatch(
          equipmentId: id,
          confidence: l.confidence,
          labelHint: l.label,
        ));
      }
      return normaliseAndTopK(raw, limit: topK);
    } catch (_) {
      // Either the model isn't bundled yet or the device blocked the
      // file read. Fall back to an empty result so the UI shows the
      // empty-state instead of crashing.
      return const [];
    }
  }

  Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
  }
}

