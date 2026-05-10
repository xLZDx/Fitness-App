/// Body-side annotation for [PoseLandmark]. Useful when classifiers need
/// to reason about asymmetry (e.g. left vs right knee tracking on a lunge).
enum LandmarkSide { left, right, center }

/// Joint type from MediaPipe BlazePose's 33-keypoint model. Only includes
/// the joints we actually consume — adding more is harmless because the
/// pipeline gracefully ignores keys it doesn't recognise.
enum LandmarkType {
  nose,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

/// Single keypoint estimate from a frame.
class PoseLandmark {
  const PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    required this.likelihood,
    this.z = 0.0,
    this.side = LandmarkSide.center,
  });

  /// Image-space x coordinate, normalised 0..1 (left → right).
  final double x;

  /// Image-space y coordinate, normalised 0..1 (top → bottom).
  final double y;

  /// Depth, normalised. Negative = closer to camera. Coarse on phone
  /// cameras without TrueDepth; classifiers use it only for fallback.
  final double z;

  /// 0..1 confidence — drop or downweight low-likelihood keypoints.
  final double likelihood;

  final LandmarkType type;
  final LandmarkSide side;
}

/// Container for all keypoints from a single frame, plus the frame's
/// timestamp (so classifiers can window/segment).
class PoseFrame {
  const PoseFrame({
    required this.timestampMs,
    required this.landmarks,
  });

  final int timestampMs;
  final Map<LandmarkType, PoseLandmark> landmarks;
}
