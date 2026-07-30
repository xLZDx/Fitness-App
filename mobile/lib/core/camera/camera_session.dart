import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import 'nv21_converter.dart';

/// Which way the camera points. Named per feature intent, not per plugin enum.
enum SessionFacing { back, front }

/// Owns a camera and publishes its frames. Nothing else in the app opens one.
///
/// This exists because camera ownership used to live inside the *recognition
/// services*: `MlKitLiveEquipmentService` and `MlKitPoseDetectorService` each
/// built their own `CameraController`, each converted frames to `InputImage`
/// with near-identical code, and each leaked the controller to its preview
/// widget through a downcast (`if (svc is MlKitLiveEquipmentService)`,
/// `svc.cameraController as CameraController?`). Two copies of the format
/// handling is two places for the NV21 bug to come back, and a preview that has
/// to downcast a *detector* to draw a camera is the layering telling on itself.
///
/// Detectors are now consumers of [frames]. They can be attached and detached
/// independently, which is what lets the QR watcher run continuously while the
/// far more expensive equipment labeler runs only when the user asks for it.
class CameraSession {
  CameraSession({this.facing = SessionFacing.back});

  final SessionFacing facing;

  CameraController? _camera;
  final ValueNotifier<CameraController?> _surface =
      ValueNotifier<CameraController?>(null);
  final StreamController<InputImage> _frames =
      StreamController<InputImage>.broadcast();

  bool _running = false;
  bool _busy = false;
  DateTime? _lastFrameAt;
  Timer? _watchdog;

  /// A live preview keeps painting the last texture even when nothing is
  /// analysing it, so a stalled stream looks HEALTHIER than a broken one. Past
  /// this window with no delivered frame, the stream reports an error rather
  /// than leaving the user pointing a working-looking camera at nothing.
  static const _frameStallAfter = Duration(seconds: 8);

  /// The controller to render, or null while there is none.
  ///
  /// A listenable, not a getter: the field flips part-way through an async
  /// [start], which no widget can observe. Reading it as a one-shot value is
  /// exactly why the live preview stayed a black square.
  ValueListenable<CameraController?> get surface => _surface;

  /// Converted frames, ready for any ML Kit detector.
  ///
  /// Broadcast, so several detectors can attach at once and each decide for
  /// itself whether to skip a frame it is too slow for.
  Stream<InputImage> frames() => _frames.stream;

  bool get isRunning => _running;

  /// When a frame was last delivered, for staleness checks.
  DateTime? get lastFrameAt => _lastFrameAt;

  /// Idempotent: safe to call when already running.
  Future<void> start() async {
    if (_running) return;
    final cameras = await availableCameras();
    final wanted = facing == SessionFacing.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final description = cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => cameras.first,
    );
    _camera = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      // yuv420, not nv21: on Android the plugin resolves to
      // camera_android_camerax, which documents that it ignores this argument
      // and always emits YUV_420_888 (android_camera_camerax.dart:450-453).
      // Asking for nv21 bought nothing and hid the need to repack.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await _camera!.initialize();
    // Widest available field of view. On phones whose logical camera extends
    // to the ultrawide lens this is the 0.6x the operator asked for; the
    // default 1.0x could not fit a machine standing two steps away. Devices
    // report their own floor, so this can never zoom past what exists.
    try {
      final minZoom = await _camera!.getMinZoomLevel();
      if (minZoom < 1.0) await _camera!.setZoomLevel(minZoom);
    } catch (e) {
      debugPrint('min-zoom unavailable, staying at default: $e');
    }
    _running = true;
    // Published only after initialize(): an uninitialized controller cannot be
    // handed to CameraPreview.
    _surface.value = _camera;
    _lastFrameAt = DateTime.now();
    await _camera!.startImageStream(_onFrame);
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      final last = _lastFrameAt;
      if (!_running || last == null) return;
      if (DateTime.now().difference(last) < _frameStallAfter) return;
      _watchdog?.cancel();
      if (!_frames.isClosed) {
        _frames.addError(StateError(
          'The camera stopped delivering frames.',
        ));
      }
      unawaited(stop());
    });
  }

  /// Waits for the camera to be usable, or gives up.
  ///
  /// The capture button can be tapped while [start] is still in flight. Returns
  /// null on timeout rather than throwing, so the caller can phrase its own
  /// message.
  Future<CameraController?> awaitReady({
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

  /// Takes a still photo through this same session.
  ///
  /// The analysis stream is stopped around the shot deliberately: whether
  /// `takePicture()` may run while `startImageStream` is active is plugin- and
  /// device-dependent, and nothing here needs that to be true.
  Future<XFile?> captureStill() async {
    final cam = await awaitReady();
    if (cam == null) return null;
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

  void _onFrame(CameraImage image) {
    if (!_running || _busy) return;
    // Guards against a slow listener queueing frames faster than they drain;
    // conversion itself is synchronous, so this only ever skips.
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      _lastFrameAt = DateTime.now();
      if (!_frames.isClosed) _frames.add(input);
    } catch (e) {
      // One unconvertible frame is not worth surfacing; the next recovers. The
      // watchdog is what notices if they ALL fail.
      debugPrint('camera frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final rotation = InputImageRotationValue.fromRawValue(
          _camera!.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    // The format is STATED, never derived from `image.format.raw`. CameraX
    // reports YUV_420_888 (35) and ML Kit's Android bridge rejects that raw
    // value outright (InputImageConverter.java:111) with "ImageFormat is not
    // supported" — the operator-visible failure this repacking fixed. iOS
    // delivers a single BGRA plane and needs none of it.
    final android = Platform.isAndroid;
    return InputImage.fromBytes(
      bytes: android ? cameraImageToNv21(image) : image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format:
            android ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        // NV21 is packed unpadded, so its row stride is exactly the width.
        bytesPerRow: android ? image.width : image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Releases the camera. The device indicator must go dark after this.
  ///
  /// Leaves the session restartable, and the frame stream open: detectors
  /// re-subscribe across visits.
  Future<void> stop() async {
    _running = false;
    _watchdog?.cancel();
    _watchdog = null;
    _lastFrameAt = null;
    // Cleared before disposal so no listener is handed a dead controller.
    _surface.value = null;
    try {
      if (_camera?.value.isStreamingImages ?? false) {
        await _camera!.stopImageStream();
      }
      await _camera?.dispose();
    } catch (e) {
      debugPrint('camera shutdown: $e');
    }
    _camera = null;
  }

  /// Terminal. After this the session cannot be restarted.
  Future<void> dispose() async {
    await stop();
    _surface.dispose();
    await _frames.close();
  }
}
