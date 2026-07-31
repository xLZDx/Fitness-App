import 'pose_coordinate_space.dart';

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

  /// Horizontal position, left → right, in the isotropic frame space defined by
  /// `pose_coordinate_space.dart`: **both** axes divided by the post-rotation
  /// image height. Ranges over `[0, PoseFrame.aspectRatio]`, NOT `[0, 1]`.
  ///
  /// This comment used to read "normalised 0..1" while nothing anywhere divided
  /// by anything, and the detector handed through whatever ML Kit produced —
  /// which its own API documents as pixels. Every threshold downstream is a bare
  /// number compared against this field, so the comment was not decoration: it
  /// was the only statement of the contract those numbers were chosen under, and
  /// it was false. Values now genuinely arrive in the range described here
  /// because `MlKitPoseDetectorService._convert` converts them.
  final double x;

  /// Vertical position, top → bottom, same space as [x]. Ranges over `[0, 1]`.
  ///
  /// Landmarks slightly outside the range are normal and meaningful: BlazePose
  /// extrapolates joints just past the frame edge rather than omitting them,
  /// which is what the gate's `outOfFrame` verdict exists to notice.
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
/// timestamp (so classifiers can window/segment) and the shape of the space its
/// coordinates live in.
class PoseFrame {
  const PoseFrame({
    required this.timestampMs,
    required this.landmarks,
    this.aspectRatio = 1.0,
    this.sourceSpace,
  }) : assert(aspectRatio > 0);

  final int timestampMs;
  final Map<LandmarkType, PoseLandmark> landmarks;

  /// Width ÷ height of the frame these landmarks came from, which is exactly the
  /// upper bound of [PoseLandmark.x] (see `pose_coordinate_space.dart`).
  ///
  /// Needed because the gate's edge check is per-axis: on a 9:16 portrait frame
  /// the rightmost in-frame x is 0.5625, so checking x against 1.0 would let a
  /// body half out of shot count as fully framed.
  ///
  /// Defaults to 1.0 — a square frame — which is what synthetic frames in tests
  /// describe and is the tightest assumption that cannot accidentally widen a
  /// bound.
  final double aspectRatio;

  /// Which space the raw coordinates were measured in before conversion, or null
  /// for a synthetic frame that was never measured.
  ///
  /// Carried purely so the diagnostic can report it. Nothing in the scoring path
  /// may branch on this: the whole point of the conversion is that both spaces
  /// land in one contract.
  final PoseCoordinateSpace? sourceSpace;
}
