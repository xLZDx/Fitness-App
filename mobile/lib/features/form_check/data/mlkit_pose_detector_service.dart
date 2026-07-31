import 'dart:async';

import 'package:google_mlkit_commons/google_mlkit_commons.dart'
    show InputImage, InputImageMetadata, InputImageRotation;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;

import '../../../core/camera/camera_session.dart';
import 'pose_coordinate_space.dart';
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
  MlKitPoseDetectorService({CameraSession? session})
      : session = session ?? CameraSession(facing: SessionFacing.front);

  /// The front camera, owned by the session rather than by this detector.
  ///
  /// It used to build its own controller and expose it so the page could draw a
  /// preview via `svc.cameraController as CameraController?` — a downcast of a
  /// detector to get at a camera. The frame-format handling was also a second,
  /// near-identical copy of the equipment recogniser's, which is two places for
  /// the NV21 bug to come back.
  final CameraSession session;

  StreamSubscription<InputImage>? _sub;
  // Nullable, not `late final`: stop() has to be able to release the detector
  // and let a later start() build a new one. A `late final` field made the
  // service single-use, which is what broke Form Check on any second visit.
  mlkit.PoseDetector? _detector;
  final StreamController<PoseFrame> _ctrl =
      StreamController<PoseFrame>.broadcast();
  bool _busy = false;
  bool _initialised = false;



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
    await session.start();
    _initialised = true;
    _sub = session.frames().listen(
          _onFrame,
          onError: (Object e, StackTrace st) {
            if (!_ctrl.isClosed) _ctrl.addError(e, st);
          },
        );
  }

  Future<void> _onFrame(InputImage inputImage) async {
    if (_busy) return;
    _busy = true;
    try {
      final detector = _detector;
      if (detector == null) return; // stopped mid-frame
      final poses = await detector.processImage(inputImage);
      if (poses.isEmpty) return;
      final frame = _convert(poses.first, inputImage.metadata);
      _ctrl.add(frame);
    } on PlatformException catch (e) {
      // The native detector rejected the call outright — a bad frame format,
      // a dead detector. This never recovers on the next frame, so surface it
      // and stop instead of spinning silently forever. Swallowing this is why
      // the form coach looked like "the camera works but nothing counts".
      debugPrint('pose detection failed natively: ${e.code} ${e.message}');
      if (!_ctrl.isClosed) {
        _ctrl.addError(
          StateError('Pose detection failed: ${e.message ?? e.code}'),
        );
      }
      unawaited(stop());
    } catch (e) {
      // A single frame that fails conversion is not worth surfacing — the
      // next one recovers.
      debugPrint('pose frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Translate ML Kit's joint set into [PoseFrame], converting coordinates into
  /// the isotropic contract in `pose_coordinate_space.dart`. We only forward the
  /// joints our classifiers actually read, so the wire stays light.
  ///
  /// This is the **only** place raw detector coordinates exist. Everything
  /// downstream — gate, rep counter, every classifier — is written against the
  /// converted unit, and had been since before anything converted anything.
  PoseFrame _convert(mlkit.Pose pose, InputImageMetadata? metadata) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final norm = _normaliserFor(pose, metadata);
    final out = <LandmarkType, PoseLandmark>{};
    void add(LandmarkType t, mlkit.PoseLandmarkType src,
        {LandmarkSide side = LandmarkSide.center}) {
      final lm = pose.landmarks[src];
      if (lm == null) return;
      final (x, y) = norm.normalise(lm.x, lm.y);
      out[t] = PoseLandmark(
        type: t,
        x: x,
        y: y,
        // z shares the detector's horizontal scale, so it takes the same
        // divisor as x to stay comparable with it.
        z: norm.space == PoseCoordinateSpace.pixels
            ? lm.z / norm.imageHeight
            : lm.z,
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

    return PoseFrame(
      timestampMs: ts,
      landmarks: out,
      aspectRatio: norm.aspectRatio,
      sourceSpace: norm.space,
    );
  }

  /// Builds the converter for one frame: the post-rotation frame size, plus the
  /// space the raw values are actually in, measured rather than assumed.
  ///
  /// Falls back to a square frame when metadata is absent, which cannot happen
  /// for a camera-stream image (`camera_session.dart` always supplies it) but is
  /// possible for an `InputImage` built from a file path. A square frame is the
  /// identity for the aspect correction, so the fallback degrades to "no
  /// horizontal correction" instead of to a wrong one.
  PoseCoordinateNormaliser _normaliserFor(
    mlkit.Pose pose,
    InputImageMetadata? metadata,
  ) {
    var w = metadata?.size.width ?? 1.0;
    var h = metadata?.size.height ?? 1.0;
    // ML Kit reports landmarks in the upright image, so a sensor mounted at
    // 90° or 270° means the frame the coordinates live in has the camera's
    // width and height swapped. Getting this backwards does not corrupt the
    // angles — both axes still share one divisor — but it does put the x bound
    // in the wrong place, which is the gate's edge check.
    final rotation = metadata?.rotation;
    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      final swap = w;
      w = h;
      h = swap;
    }
    if (w <= 0 || h <= 0) {
      w = 1.0;
      h = 1.0;
    }
    return PoseCoordinateNormaliser(
      space: detectCoordinateSpace(
        pose.landmarks.values.expand((lm) => [lm.x, lm.y]),
      ),
      imageWidth: w,
      imageHeight: h,
    );
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
    await _sub?.cancel();
    _sub = null;
    await session.stop();
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

