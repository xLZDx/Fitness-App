import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import 'live_equipment_service.dart';
import 'live_recognition.dart';
import 'visual_equipment_match.dart';

/// Real live recogniser: back camera -> ML Kit custom labeler -> smoother.
///
/// One frame at a time (`_busy`) — the labeler is slower than the camera and
/// queueing frames would blow memory and lag the preview by seconds.
class MlKitLiveEquipmentService implements LiveEquipmentService {
  MlKitLiveEquipmentService({
    this.modelAssetPath = 'assets/models/equipment_v1.tflite',
    RecognitionSmoother? smoother,
  }) : _smoother = smoother ?? RecognitionSmoother();

  final String modelAssetPath;
  final RecognitionSmoother _smoother;

  /// Same map as the photo path: model label -> catalog equipmentId.
  static const _kLabelMap = <String, String>{
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

  CameraController? _camera;
  mlkit.ImageLabeler? _labeler;
  final StreamController<LiveRecognition> _ctrl =
      StreamController<LiveRecognition>.broadcast();
  bool _busy = false;
  bool _running = false;

  /// Exposed so the Scan page can render `CameraPreview` against the same
  /// controller this service is streaming from.
  CameraController? get cameraController => _camera;

  @override
  Stream<LiveRecognition> recognitions() => _ctrl.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    final dir = await getApplicationDocumentsDirectory();
    // Path must match AssetBootstrap: '<docs>/<asset path verbatim>'.
    final modelFile = File('${dir.path}/$modelAssetPath');
    _labeler = mlkit.ImageLabeler(
      options: mlkit.LocalLabelerOptions(
        modelPath: modelFile.path,
        // Lower than the photo path on purpose: a single frame is weak
        // evidence, and the smoother is what decides. Filtering hard here
        // would starve the vote.
        confidenceThreshold: 0.05,
        maxCount: 3,
      ),
    );

    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _camera = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _camera!.initialize();
    _running = true;
    await _camera!.startImageStream(_onFrame);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_running) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final labels = await _labeler!.processImage(input);
      VisualMatch? top;
      for (final l in labels) {
        final id = _kLabelMap[l.label.toLowerCase()];
        if (id == null) continue;
        if (top == null || l.confidence > top.confidence) {
          top = VisualMatch(
            equipmentId: id,
            confidence: l.confidence,
            labelHint: l.label,
          );
        }
      }
      final settled = _smoother.add(top);
      if (settled != null && !_ctrl.isClosed) _ctrl.add(settled);
    } catch (e) {
      // A frame that fails conversion is not worth surfacing — the next one
      // recovers. A model that never loads shows up as "no recognition",
      // which start() would already have thrown for.
      debugPrint('live recognition frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  mlkit.InputImage? _toInputImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final builder = BytesBuilder();
    for (final p in image.planes) {
      builder.add(p.bytes);
    }
    final rotation = mlkit.InputImageRotationValue.fromRawValue(
          _camera!.description.sensorOrientation,
        ) ??
        mlkit.InputImageRotation.rotation0deg;
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw) ??
        (Platform.isAndroid
            ? mlkit.InputImageFormat.nv21
            : mlkit.InputImageFormat.bgra8888);
    return mlkit.InputImage.fromBytes(
      bytes: builder.toBytes(),
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  Future<void> stop() async {
    _running = false;
    _smoother.reset();
    try {
      if (_camera?.value.isStreamingImages ?? false) {
        await _camera!.stopImageStream();
      }
      await _camera?.dispose();
    } catch (e) {
      debugPrint('camera shutdown: $e');
    }
    _camera = null;
    await _labeler?.close();
    _labeler = null;
  }

  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}
