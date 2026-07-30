import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/nv21_converter.dart';
import 'live_equipment_service.dart';
import 'live_recognition.dart';
import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart' show VisualEquipmentException;

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

  /// Published so the preview can react the instant the camera is usable.
  ///
  /// Assigning `_camera` alone was the black-square bug: the field flips
  /// part-way through `start()`, which nothing in the widget tree can observe.
  final ValueNotifier<CameraController?> _surface =
      ValueNotifier<CameraController?>(null);

  @override
  ValueListenable<CameraController?> get cameraSurface => _surface;

  /// When the last frame was handed to the labeler. Drives [_watchdog].
  DateTime? _lastFrameAt;
  Timer? _watchdog;

  /// A live preview keeps painting the last texture even when analysis is dead,
  /// so a stalled stream looks HEALTHIER than a broken one. Past this window
  /// with no processed frame, say so instead of leaving the user pointing a
  /// working-looking camera at nothing.
  static const _frameStallAfter = Duration(seconds: 8);

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
    // Check the model HERE, not later. `ImageLabeler(...)` is a pure Dart
    // constructor (verified in google_mlkit_image_labeling 0.14.1
    // image_labeler.dart:16) — the model is not loaded until the first
    // processImage call, which happens inside the per-frame handler. Without
    // this check a missing model fails silently on every frame forever and
    // the UI just says "Looking…".
    if (!await modelFile.exists()) {
      throw VisualEquipmentException(
        'Recognition model missing at ${modelFile.path}. The bundled model '
        'failed to unpack on first launch — reinstalling the app fixes it.',
      );
    }
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
      // yuv420, not nv21: on Android the plugin resolves to
      // camera_android_camerax, which documents that it ignores this
      // argument and always emits YUV_420_888
      // (android_camera_camerax.dart:450-453). Asking for nv21 here bought
      // nothing and hid the need to repack — see _toInputImage.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await _camera!.initialize();
    _running = true;
    // Publish only once initialize() has returned: a controller that is not yet
    // initialized cannot be handed to CameraPreview.
    _surface.value = _camera;
    _lastFrameAt = DateTime.now();
    await _camera!.startImageStream(_onFrame);
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      final last = _lastFrameAt;
      if (!_running || last == null) return;
      if (DateTime.now().difference(last) < _frameStallAfter) return;
      _watchdog?.cancel();
      if (!_ctrl.isClosed) {
        _ctrl.addError(VisualEquipmentException(
          'Камера перестала присылать кадры. Выключите и включите живой режим.',
        ));
      }
      unawaited(stop());
    });
  }

  /// Waits for the camera to become usable, or gives up.
  ///
  /// Used by the capture path, which can be tapped while `start()` is still in
  /// flight. Returns null on timeout rather than throwing so the caller can
  /// show its own message.
  Future<CameraController?> awaitCamera({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    bool usable() => _surface.value?.value.isInitialized ?? false;
    if (usable()) return _surface.value;
    final done = Completer<CameraController?>();
    void listener() {
      if (usable() && !done.isCompleted) done.complete(_surface.value);
    }

    _surface.addListener(listener);
    try {
      return await done.future.timeout(timeout, onTimeout: () => null);
    } finally {
      _surface.removeListener(listener);
    }
  }

  @override
  Future<XFile?> captureStill() async {
    final cam = await awaitCamera();
    if (cam == null) return null;
    // The analysis stream is stopped around the shot deliberately. Whether
    // takePicture() may run while startImageStream is active is plugin- and
    // device-dependent, and nothing here needs that to be true.
    final wasStreaming = cam.value.isStreamingImages;
    if (wasStreaming) await cam.stopImageStream();
    try {
      return await cam.takePicture();
    } finally {
      if (wasStreaming && _running && !cam.value.isStreamingImages) {
        _lastFrameAt = DateTime.now();
        await cam.startImageStream(_onFrame);
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_running) return;
    _busy = true;
    _lastFrameAt = DateTime.now();
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
    } on PlatformException catch (e) {
      // The native labeler rejected the call — a broken model, an
      // unsupported format, a dead detector. This does NOT recover on the
      // next frame, so surface it once and stop streaming instead of
      // spinning silently. (Per-frame conversion errors are different and
      // handled below.)
      debugPrint('live recognition failed natively: ${e.code} ${e.message}');
      if (!_ctrl.isClosed) {
        _ctrl.addError(VisualEquipmentException(
          'Recognition engine failed: ${e.message ?? e.code}',
        ));
      }
      unawaited(stop());
    } catch (e) {
      // A frame that fails conversion is not worth surfacing — the next one
      // recovers.
      debugPrint('live recognition frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  mlkit.InputImage? _toInputImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final rotation = mlkit.InputImageRotationValue.fromRawValue(
          _camera!.description.sensorOrientation,
        ) ??
        mlkit.InputImageRotation.rotation0deg;

    // The format is stated, never derived from `image.format.raw`. CameraX
    // reports YUV_420_888 (35) and ML Kit's Android bridge rejects that raw
    // value outright (InputImageConverter.java:111), so we repack the frame
    // into a real NV21 buffer and say so. iOS delivers a single BGRA plane
    // and needs no repacking.
    final android = Platform.isAndroid;
    return mlkit.InputImage.fromBytes(
      bytes: android ? cameraImageToNv21(image) : image.planes.first.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: android
            ? mlkit.InputImageFormat.nv21
            : mlkit.InputImageFormat.bgra8888,
        // NV21 is packed unpadded, so its row stride is exactly the width.
        bytesPerRow: android ? image.width : image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  Future<void> stop() async {
    _running = false;
    _smoother.reset();
    _watchdog?.cancel();
    _watchdog = null;
    _lastFrameAt = null;
    // Cleared before disposal so no listener can be handed a dead controller.
    _surface.value = null;
    try {
      if (_camera?.value.isStreamingImages ?? false) {
        await _camera!.stopImageStream();
      }
      await _camera?.dispose();
      _camera = null;
      // Inside the try as well: a throw here used to escape stop() entirely,
      // and every caller invokes it fire-and-forget.
      await _labeler?.close();
    } catch (e) {
      debugPrint('camera shutdown: $e');
    }
    _camera = null;
    _labeler = null;
  }

  Future<void> dispose() async {
    await stop();
    _surface.dispose();
    await _ctrl.close();
  }
}
