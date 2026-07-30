import 'dart:io';

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
    // A photographed bench is usually just a bench, not the press station —
    // the operator's two flat benches must land on the bench page, not on
    // barbell bench-press exercises.
    'bench': 'adjustable_bench',
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
    // MUST match where AssetBootstrap.ensureBundledAssets copies the
    // asset: '<docs>/<asset-path-verbatim>'. It used to read
    // '<docs>/models/...' while the bootstrap wrote
    // '<docs>/assets/models/...' — the model was never found.
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$modelAssetPath');
  }

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    try {
      final labeler = await _ensureLabeler();
      // fromFilePath lets the platform decode JPEG/PNG + EXIF rotation.
      // The old raw-bytes route wrapped encoded JPEG in NV21 metadata with
      // hardcoded 640x480 and failed on-device with InputImageConverterError.
      final labels =
          await labeler.processImage(mlkit.InputImage.fromFilePath(path));
      return _toMatches(labels, topK);
    } catch (e) {
      // Deliberately NOT swallowed into an empty list: "the model failed to
      // load" and "no equipment in this photo" must not look identical to
      // the user. The controller turns this into an error state the Scan
      // tab renders with the reason; an empty list now means "no match".
      throw VisualEquipmentException('$e');
    }
  }

  List<VisualMatch> _toMatches(List<mlkit.ImageLabel> labels, int topK) {
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
    return rankTopK(raw, limit: topK);
  }

  Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
  }
}

