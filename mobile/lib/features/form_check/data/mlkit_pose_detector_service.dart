import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import 'package:flutter/foundation.dart' show debugPrint;

import 'pose_detector_service.dart';
import 'pose_landmark.dart';

/// Real, on-device pose detector binding the [camera] plugin to
/// `google_mlkit_pose_detection`. Frames are processed at the camera's
/// native rate (typically 15-30 FPS depending on device); rule
/// classifiers downstream consume the [PoseFrame] stream.
///
/// Lifecycle: callers MUST call [start] before subscribing to [frames]
/// and [dispose] when leaving the screen — otherwise the camera stays
/// hot and the detector leaks resources.
class MlKitPoseDetectorService implements PoseDetectorService {
  MlKitPoseDetectorService();

  CameraController? _camera;
  // Nullable, not `late final`: stop() has to be able to release the detector
  // and let a later start() build a new one. A `late final` field made the
  // service single-use, which is what broke Form Check on any second visit.
  mlkit.PoseDetector? _detector;
  final StreamController<PoseFrame> _ctrl =
      StreamController<PoseFrame>.broadcast();
  bool _busy = false;
  bool _initialised = false;

  /// Exposed so the FormCheckPage can render `CameraPreview(controller)`
  /// against the same controller this service feeds to ML Kit. Null
  /// until [start] resolves.
  CameraController? get cameraController => _camera;

  @override
  Stream<PoseFrame> frames() => _ctrl.stream;

  @override
  Future<void> start() async {
    if (_initialised) return;
    _detector = mlkit.PoseDetector(
      options: mlkit.PoseDetectorOptions(
        mode: mlkit.PoseDetectionMode.stream,
        model: mlkit.PoseDetectionModel.accurate,
      ),
    );
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _camera!.initialize();
    _initialised = true;
    await _camera!.startImageStream(_onCameraImage);
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final inputImage = _toMlKitImage(image);
      if (inputImage == null) return;
      final detector = _detector;
      if (detector == null) return; // stopped mid-frame
      final poses = await detector.processImage(inputImage);
      if (poses.isEmpty) return;
      final frame = _convert(poses.first);
      _ctrl.add(frame);
    } catch (_) {
      // Drop frames that fail conversion — the next one will recover.
    } finally {
      _busy = false;
    }
  }

  /// Convert a `CameraImage` into the format `google_mlkit_pose_detection`
  /// expects. The plugin specifies separate paths for Android NV21 vs
  /// iOS BGRA8888.
  mlkit.InputImage? _toMlKitImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final builder = BytesBuilder();
    for (final p in image.planes) {
      builder.add(p.bytes);
    }
    final bytes = builder.toBytes();
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = mlkit.InputImageRotationValue.fromRawValue(
            _camera!.description.sensorOrientation) ??
        mlkit.InputImageRotation.rotation0deg;
    final format =
        mlkit.InputImageFormatValue.fromRawValue(image.format.raw) ??
            (Platform.isAndroid
                ? mlkit.InputImageFormat.nv21
                : mlkit.InputImageFormat.bgra8888);
    return mlkit.InputImage.fromBytes(
      bytes: bytes,
      metadata: mlkit.InputImageMetadata(
        size: size,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Translate ML Kit's joint set into [PoseFrame]. We only forward the
  /// joints our classifiers actually read, so the wire stays light.
  PoseFrame _convert(mlkit.Pose pose) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final out = <LandmarkType, PoseLandmark>{};
    void add(LandmarkType t, mlkit.PoseLandmarkType src,
        {LandmarkSide side = LandmarkSide.center}) {
      final lm = pose.landmarks[src];
      if (lm == null) return;
      out[t] = PoseLandmark(
        type: t,
        x: lm.x,
        y: lm.y,
        z: lm.z,
        likelihood: lm.likelihood,
        side: side,
      );
    }

    add(LandmarkType.nose, mlkit.PoseLandmarkType.nose);
    add(LandmarkType.leftShoulder, mlkit.PoseLandmarkType.leftShoulder,
        side: LandmarkSide.left);
    add(LandmarkType.rightShoulder, mlkit.PoseLandmarkType.rightShoulder,
        side: LandmarkSide.right);
    add(LandmarkType.leftElbow, mlkit.PoseLandmarkType.leftElbow,
        side: LandmarkSide.left);
    add(LandmarkType.rightElbow, mlkit.PoseLandmarkType.rightElbow,
        side: LandmarkSide.right);
    add(LandmarkType.leftWrist, mlkit.PoseLandmarkType.leftWrist,
        side: LandmarkSide.left);
    add(LandmarkType.rightWrist, mlkit.PoseLandmarkType.rightWrist,
        side: LandmarkSide.right);
    add(LandmarkType.leftHip, mlkit.PoseLandmarkType.leftHip,
        side: LandmarkSide.left);
    add(LandmarkType.rightHip, mlkit.PoseLandmarkType.rightHip,
        side: LandmarkSide.right);
    add(LandmarkType.leftKnee, mlkit.PoseLandmarkType.leftKnee,
        side: LandmarkSide.left);
    add(LandmarkType.rightKnee, mlkit.PoseLandmarkType.rightKnee,
        side: LandmarkSide.right);
    add(LandmarkType.leftAnkle, mlkit.PoseLandmarkType.leftAnkle,
        side: LandmarkSide.left);
    add(LandmarkType.rightAnkle, mlkit.PoseLandmarkType.rightAnkle,
        side: LandmarkSide.right);

    return PoseFrame(timestampMs: ts, landmarks: out);
  }

  /// Releases the camera and the detector, leaving the service **restartable**.
  ///
  /// This used to only stop the image stream and leave `_initialised` true,
  /// so a later [start] returned early and Form Check was dead on every
  /// second visit — with the front camera still held. The broadcast
  /// controller deliberately stays open: listeners re-subscribe across visits.
  @override
  Future<void> stop() async {
    if (!_initialised) return;
    _initialised = false;
    try {
      if (_camera?.value.isStreamingImages ?? false) {
        await _camera!.stopImageStream();
      }
      await _camera?.dispose();
    } catch (e) {
      debugPrint('pose detector camera shutdown: $e');
    }
    _camera = null;
    try {
      await _detector?.close();
    } catch (e) {
      debugPrint('pose detector close: $e');
    }
    _detector = null;
  }

  /// Terminal: releases everything and closes the stream. After this the
  /// instance cannot be restarted — use [stop] when leaving a screen.
  @override
  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}

