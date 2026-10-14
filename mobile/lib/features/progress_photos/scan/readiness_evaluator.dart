/// Is the person ready to be photographed for the current scan pose?
///
/// Stateless and pure: pose landmarks + one frame luminance value in, a typed
/// per-check verdict and a single hint key out. No camera, no timers; the
/// [AutoShutterMachine] adds the "stay ready for a while" part.
///
/// Reuses `gatePose` (form_check/data/pose_gate.dart) only for the frame-level
/// smoke detectors (unit mismatch, implausible torso) and `kLowLightBrightness`
/// from `frame_brightness.dart` as the dark floor; everything else is scan
/// specific because the form gate wants joints with high confidence, which a
/// side-on body (far-side joints occluded) can never provide.
///
/// Thresholds are opening values, not measured on a device fleet. Calibrate on
/// the operator's phone before trusting any of them.
///
/// ## Orientation heuristic and its limits (read this before relying on it)
///
/// A pose detector tells us WHERE the joints are, not which way the person
/// faces. We use the shoulder-width / torso-length ratio:
///
/// * front and back: both shoulders far apart (ratio >= [frontMinShoulderRatio]);
/// * side: shoulders overlap (ratio <= [sideMaxShoulderRatio]).
///
/// That separates side from front/back reliably enough. It CANNOT separate front
/// from back by geometry alone (a back view is a mirrored front view with the
/// left/right labels swapped). We add one weak hint, face landmarks:
///
/// * front requires the nose to be confident ([ReadinessConfig.requireFaceForFront]);
/// * back requires the nose to be absent/low, OR the user's explicit
///   `userConfirmsFacingAway` flag.
///
/// Limits: BlazePose often hallucinates a nose with HIGH likelihood on a back
/// view (it extrapolates), and a low-likelihood nose on a real front view
/// (hair, hat, dim light, mask) is possible. So the face hint can produce false
/// "not ready" results in both directions; a UI MUST expose the "I am facing
/// away" confirmation for the back step, and must keep a manual shutter. The
/// check never claims to know the true facing direction; it only decides whether
/// the picture is plausibly the requested pose.
library;

import 'dart:math' as math;

import 'package:fitness_app/core/camera/frame_brightness.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

import 'scan_pose.dart';

enum CheckStatus {
  pass,
  fail,

  /// Could not be evaluated (no body, joints missing). Never counts as ready.
  unknown;

  bool get isPass => this == CheckStatus.pass;
}

/// One prompt key for the UI / voice / haptic layer (mapped to l10n later).
/// Declared in no particular priority order; priority lives in the evaluator.
enum ReadinessHint {
  none,
  moreLight,
  lessLight,
  showFullBody,
  stepBack,
  stepCloser,
  centerYourself,
  turnSideways,
  turnAround,
  faceCamera,

  /// Coordinates look broken upstream; stepping around cannot fix it.
  trackingProblem,
}

class ReadinessConfig {
  const ReadinessConfig({
    this.minLikelihood = 0.6,
    this.minLuminance = 0.25,
    this.maxLuminance = 0.92,
    this.minHeightFraction = 0.60,
    this.maxHeightFraction = 0.88,
    this.edgeMargin = 0.02,
    this.centerTolerance = 0.12,
    this.frontMinShoulderRatio = 0.55,
    this.sideMaxShoulderRatio = 0.35,
    this.faceLikelihood = 0.5,
    this.requireFaceForFront = true,
  });

  /// Per-joint confidence floor for "visible".
  final double minLikelihood;

  /// Mean frame luminance in [0, 1] (see `averageFrameBrightness`). Slightly
  /// above `kLowLightBrightness` (0.18): a scan needs more than "the detector
  /// still runs".
  final double minLuminance;
  final double maxLuminance;

  /// Estimated standing height as a fraction of the frame height.
  final double minHeightFraction;
  final double maxHeightFraction;

  /// Margin (frame units) a body extent must keep from the frame edge.
  final double edgeMargin;

  /// Allowed horizontal offset of the body centre from the frame centre, as a
  /// fraction of the frame width.
  final double centerTolerance;

  final double frontMinShoulderRatio;
  final double sideMaxShoulderRatio;

  /// Nose likelihood at or above which the face counts as visible.
  final double faceLikelihood;
  final bool requireFaceForFront;

  /// Anatomical proportions used to estimate the body extent (heuristic,
  /// upright adult): shoulder line to ankle joint is ~0.78 of height; crown is
  /// ~0.18 of height above the shoulder line; the floor is ~0.04 below the ankle.
  static const double shoulderToAnkleOfHeight = 0.78;
  static const double crownAboveShoulderOfHeight = 0.18;
  static const double floorBelowAnkleOfHeight = 0.04;
}

/// Verdict for one frame.
class ReadinessResult {
  const ReadinessResult({
    required this.distance,
    required this.lighting,
    required this.position,
    required this.orientation,
    required this.hint,
    this.heightFraction,
    this.shoulderRatio,
    this.centerOffset,
  });

  final CheckStatus distance;
  final CheckStatus lighting;
  final CheckStatus position;
  final CheckStatus orientation;

  /// Single prompt for the highest-priority failing check, or
  /// [ReadinessHint.none] when ready.
  final ReadinessHint hint;

  /// Diagnostics (null when not computable): estimated body height as a frame
  /// fraction, shoulder-width / torso-length, signed centre offset as a
  /// fraction of frame width.
  final double? heightFraction;
  final double? shoulderRatio;
  final double? centerOffset;

  bool get isReady =>
      distance.isPass &&
      lighting.isPass &&
      position.isPass &&
      orientation.isPass;
}

class ReadinessEvaluator {
  const ReadinessEvaluator({this.config = const ReadinessConfig()});

  final ReadinessConfig config;

  /// Evaluate one frame for [pose].
  ///
  /// [luminance] is the mean frame brightness in [0, 1], or null when unknown
  /// (lighting then counts as [CheckStatus.unknown], i.e. not ready).
  /// [userConfirmsFacingAway] only matters for [ScanPose.back].
  ReadinessResult evaluate({
    required PoseFrame? frame,
    required double? luminance,
    required ScanPose pose,
    bool userConfirmsFacingAway = false,
  }) {
    final c = config;

    // Lighting (independent of the body).
    var lighting = CheckStatus.unknown;
    var lightHint = ReadinessHint.none;
    if (luminance != null && !luminance.isNaN) {
      if (luminance < math.max(c.minLuminance, kLowLightBrightness)) {
        lighting = CheckStatus.fail;
        lightHint = ReadinessHint.moreLight;
      } else if (luminance > c.maxLuminance) {
        lighting = CheckStatus.fail;
        lightHint = ReadinessHint.lessLight;
      } else {
        lighting = CheckStatus.pass;
      }
    }

    ReadinessResult finish({
      CheckStatus distance = CheckStatus.unknown,
      CheckStatus position = CheckStatus.unknown,
      CheckStatus orientation = CheckStatus.unknown,
      ReadinessHint visibilityHint = ReadinessHint.none,
      ReadinessHint distanceHint = ReadinessHint.none,
      ReadinessHint positionHint = ReadinessHint.none,
      ReadinessHint orientationHint = ReadinessHint.none,
      double? heightFraction,
      double? shoulderRatio,
      double? centerOffset,
    }) {
      // Priority: lighting (a dark frame makes every landmark suspect), then
      // body visibility / tracking, distance, centring, orientation.
      final ordered = [
        lightHint,
        visibilityHint,
        distanceHint,
        positionHint,
        orientationHint,
      ];
      final hint = ordered.firstWhere(
        (h) => h != ReadinessHint.none,
        orElse: () => ReadinessHint.none,
      );
      return ReadinessResult(
        distance: distance,
        lighting: lighting,
        position: position,
        orientation: orientation,
        hint: hint,
        heightFraction: heightFraction,
        shoulderRatio: shoulderRatio,
        centerOffset: centerOffset,
      );
    }

    if (frame == null || frame.landmarks.isEmpty) {
      return finish(
        position: CheckStatus.fail,
        visibilityHint: ReadinessHint.showFullBody,
      );
    }

    // Frame-level smoke detectors from the existing gate (no required joints).
    final gate = gatePose(frame, const {});
    if (gate == PoseGateVerdict.unitMismatch) {
      return finish(
        position: CheckStatus.fail,
        visibilityHint: ReadinessHint.trackingProblem,
      );
    }
    if (gate == PoseGateVerdict.implausibleGeometry) {
      return finish(
        position: CheckStatus.fail,
        visibilityHint: ReadinessHint.showFullBody,
      );
    }

    final lm = frame.landmarks;
    bool vis(LandmarkType t) =>
        (lm[t]?.likelihood ?? 0) >= c.minLikelihood;
    // One visible joint per pair is enough for visibility in every pose: in a
    // profile the far-side joints are occluded, and a profile shown when front
    // or back was requested must be reported as an orientation problem, not as
    // "body not visible".
    const need = 1;
    int count(LandmarkType a, LandmarkType b) =>
        (vis(a) ? 1 : 0) + (vis(b) ? 1 : 0);

    final shouldersOk =
        count(LandmarkType.leftShoulder, LandmarkType.rightShoulder) >= need;
    final hipsOk = count(LandmarkType.leftHip, LandmarkType.rightHip) >= need;
    final kneesOk =
        count(LandmarkType.leftKnee, LandmarkType.rightKnee) >= need;
    final anklesOk =
        count(LandmarkType.leftAnkle, LandmarkType.rightAnkle) >= need;
    // The head is not required for the back step: a back view has no face, and
    // the crown is estimated from the shoulders instead.
    final headOk = pose == ScanPose.back ||
        vis(LandmarkType.nose) ||
        vis(LandmarkType.leftEar) ||
        vis(LandmarkType.rightEar);

    if (!shouldersOk || !hipsOk) {
      return finish(
        position: CheckStatus.fail,
        visibilityHint: ReadinessHint.showFullBody,
      );
    }
    if (!kneesOk || !anklesOk || !headOk) {
      // Torso is there but head or legs are not: the usual cause is a body
      // cropped by the frame edge, so asking for more distance is the useful
      // prompt (an occluded limb is the rarer cause).
      return finish(
        distance: CheckStatus.fail,
        position: CheckStatus.fail,
        distanceHint: ReadinessHint.stepBack,
      );
    }

    (double, double) mid(LandmarkType a, LandmarkType b) {
      final pts = [a, b].where(vis).map((t) => lm[t]!).toList();
      return (
        pts.map((p) => p.x).reduce((s, v) => s + v) / pts.length,
        pts.map((p) => p.y).reduce((s, v) => s + v) / pts.length,
      );
    }

    final shoulderMid =
        mid(LandmarkType.leftShoulder, LandmarkType.rightShoulder);
    final hipMid = mid(LandmarkType.leftHip, LandmarkType.rightHip);
    final ankleMid = mid(LandmarkType.leftAnkle, LandmarkType.rightAnkle);

    // ---- distance ----
    final span = ankleMid.$2 - shoulderMid.$2;
    if (span <= 0) {
      // Upside-down or lying body; not a standing scan pose.
      return finish(
        distance: CheckStatus.fail,
        position: CheckStatus.fail,
        visibilityHint: ReadinessHint.showFullBody,
      );
    }
    final height = span / ReadinessConfig.shoulderToAnkleOfHeight;
    final crownY =
        shoulderMid.$2 - ReadinessConfig.crownAboveShoulderOfHeight * height;
    final floorY =
        ankleMid.$2 + ReadinessConfig.floorBelowAnkleOfHeight * height;
    final croppedVertically =
        crownY < c.edgeMargin || floorY > 1.0 - c.edgeMargin;

    var distance = CheckStatus.pass;
    var distanceHint = ReadinessHint.none;
    if (croppedVertically || height > c.maxHeightFraction) {
      distance = CheckStatus.fail;
      distanceHint = ReadinessHint.stepBack;
    } else if (height < c.minHeightFraction) {
      distance = CheckStatus.fail;
      distanceHint = ReadinessHint.stepCloser;
    }

    // ---- position (centred, inside the frame horizontally) ----
    final cx = (shoulderMid.$1 + hipMid.$1) / 2;
    final centerOffset = (cx - frame.aspectRatio / 2) / frame.aspectRatio;
    final keyTypes = [
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
      LandmarkType.leftHip,
      LandmarkType.rightHip,
      LandmarkType.leftKnee,
      LandmarkType.rightKnee,
      LandmarkType.leftAnkle,
      LandmarkType.rightAnkle,
    ];
    final croppedHorizontally = keyTypes.where(vis).any((t) {
      final x = lm[t]!.x;
      return x < c.edgeMargin || x > frame.aspectRatio - c.edgeMargin;
    });
    var position = CheckStatus.pass;
    var positionHint = ReadinessHint.none;
    if (croppedHorizontally || centerOffset.abs() > c.centerTolerance) {
      position = CheckStatus.fail;
      positionHint = ReadinessHint.centerYourself;
    }

    // ---- orientation ----
    final torso = math.sqrt(
      math.pow(hipMid.$1 - shoulderMid.$1, 2) +
          math.pow(hipMid.$2 - shoulderMid.$2, 2),
    );
    final bothShoulders = vis(LandmarkType.leftShoulder) &&
        vis(LandmarkType.rightShoulder);
    final shoulderWidth = bothShoulders
        ? (lm[LandmarkType.leftShoulder]!.x - lm[LandmarkType.rightShoulder]!.x)
            .abs()
        : 0.0; // one shoulder hidden behind the body: a profile
    final ratio = torso > 1e-6 ? shoulderWidth / torso : 0.0;

    final wide = ratio >= c.frontMinShoulderRatio;
    final narrow = ratio <= c.sideMaxShoulderRatio;
    final noseLikelihood = lm[LandmarkType.nose]?.likelihood ?? 0.0;
    final faceVisible = noseLikelihood >= c.faceLikelihood;

    var orientation = CheckStatus.pass;
    var orientationHint = ReadinessHint.none;
    switch (pose) {
      case ScanPose.front:
        if (!wide) {
          orientation = CheckStatus.fail;
          orientationHint = ReadinessHint.faceCamera;
        } else if (c.requireFaceForFront && !faceVisible) {
          orientation = CheckStatus.fail;
          orientationHint = ReadinessHint.faceCamera;
        }
      case ScanPose.side:
        if (!narrow) {
          orientation = CheckStatus.fail;
          orientationHint = ReadinessHint.turnSideways;
        }
      case ScanPose.back:
        if (!wide) {
          orientation = CheckStatus.fail;
          orientationHint = ReadinessHint.turnAround;
        } else if (!userConfirmsFacingAway && faceVisible) {
          orientation = CheckStatus.fail;
          orientationHint = ReadinessHint.turnAround;
        }
    }

    return finish(
      distance: distance,
      position: position,
      orientation: orientation,
      distanceHint: distanceHint,
      positionHint: positionHint,
      orientationHint: orientationHint,
      heightFraction: height,
      shoulderRatio: ratio,
      centerOffset: centerOffset,
    );
  }
}
