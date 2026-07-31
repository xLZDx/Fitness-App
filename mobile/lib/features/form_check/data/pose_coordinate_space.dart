/// The unit the pose detector's coordinates arrive in, and the conversion into
/// the one unit the rest of the form coach is allowed to assume.
///
/// ## Why this file exists
///
/// Every threshold in `pose_gate.dart`, `rep_counter.dart` and
/// `form_classifier.dart` is a bare number compared against a landmark
/// coordinate. Not one of them can be right unless the unit is known, and until
/// 2026-07-31 the unit was **asserted in a doc comment and never established**:
/// `pose_landmark.dart` said "normalised 0..1" while
/// `mlkit_pose_detector_service.dart` passed `lm.x` straight through from a
/// plugin whose own doc says "x coordinate of landmark in image frame"
/// (`pose_detector.dart:135`) and whose Android bridge reads
/// `poseLandmark.getPosition3D().getX()` (`PoseDetector.java:94`) — pixels, per
/// ML Kit's API contract.
///
/// The two readings cannot both be true, and the evidence points both ways: the
/// documented contract says pixels, but the operator's incident (six reps
/// counted from a still photograph of a face) is arithmetically impossible in
/// pixels, because the rep counter's entire hysteresis ladder spans 0.11 units
/// and crossing it would need the hip and the knee within 0.11 **pixels** of
/// each other.
///
/// ## What this file does about it
///
/// It stops asserting and starts measuring. The two hypotheses are separated by
/// roughly two orders of magnitude — a body in pixels spans hundreds of units on
/// any camera this app supports, a body in normalised coordinates spans at most
/// about one — so a single observation of the frame's own extent tells them
/// apart with enormous margin. [detectCoordinateSpace] is that observation.
///
/// Then **both** hypotheses are converted into one output contract, so the
/// pipeline downstream is correct either way and no threshold depends on which
/// branch fired.
///
/// ## The output contract
///
/// Both axes are divided by the **same** scalar — the post-rotation image height:
///
/// * `y ∈ [0, 1]`
/// * `x ∈ [0, aspectRatio]`, where `aspectRatio = width / height`
///
/// One scalar, not one per axis, because [FormClassifier] measures joint angles
/// with `atan2`, and `atan2` survives only **isotropic** scaling. Dividing x by
/// the width and y by the height — the obvious-looking normalisation, and the
/// one this gate nearly shipped — is anisotropic: on a 3:4 frame it reports a
/// correct 82.9° Romanian deadlift as 77.5°, an error larger than the entire
/// 5.2° gap the deadlift rule was claiming to resolve. Angles would have been
/// wrong in a way no test comparing angles to angles could see.
library;

/// Which unit a frame's raw landmark coordinates were expressed in.
enum PoseCoordinateSpace {
  /// Image-space pixels, as ML Kit's `PoseLandmark.getPosition3D()` documents.
  pixels,

  /// Already scaled to roughly 0..1 by something upstream.
  normalised,
}

/// Below this extent the coordinates cannot be pixels.
///
/// A frame at the lowest resolution this app ever requests (`ResolutionPreset
/// .medium`, 480x360 on Android) puts a standing body across hundreds of
/// pixels. Normalised coordinates span at most 1.0, and past the frame edge
/// BlazePose extrapolates only modestly beyond that. Four is far above anything
/// the normalised hypothesis can produce and far below anything the pixel
/// hypothesis can produce, so the discriminator is not a close call.
const double kPixelSpaceThreshold = 4.0;

/// Which space [values] are in, judged by how far they spread.
///
/// [values] should be every x and y in the frame. Fewer than two values cannot
/// have an extent, so the answer defaults to [PoseCoordinateSpace.pixels] — the
/// documented contract, which is the right thing to assume when there is no
/// evidence either way.
PoseCoordinateSpace detectCoordinateSpace(Iterable<double> values) {
  var min = double.infinity;
  var max = double.negativeInfinity;
  var n = 0;
  for (final v in values) {
    if (v.isNaN || v.isInfinite) continue;
    if (v < min) min = v;
    if (v > max) max = v;
    n++;
  }
  if (n < 2) return PoseCoordinateSpace.pixels;
  return (max - min) >= kPixelSpaceThreshold
      ? PoseCoordinateSpace.pixels
      : PoseCoordinateSpace.normalised;
}

/// Maps one frame's raw coordinates onto the isotropic contract in the library
/// doc, from whichever space they arrived in.
///
/// Immutable and cheap: one per frame, built once the frame's space is known.
class PoseCoordinateNormaliser {
  PoseCoordinateNormaliser({
    required this.space,
    required this.imageWidth,
    required this.imageHeight,
  })  : assert(imageWidth > 0, 'a frame with no width has no coordinate space'),
        assert(imageHeight > 0);

  /// The space [normalise] is being asked to convert **from**.
  final PoseCoordinateSpace space;

  /// Post-rotation frame dimensions. ML Kit reports landmarks in the upright
  /// image, so for a 90°/270° sensor these are the camera's dimensions swapped.
  final double imageWidth;
  final double imageHeight;

  /// Widest x the frame can contain: `width / height`. `y` maxes at 1.
  double get aspectRatio => imageWidth / imageHeight;

  /// Converts (x, y) into the isotropic contract.
  ///
  /// Both branches land in the same space, which is the point — nothing
  /// downstream has to know or ask which one ran.
  (double, double) normalise(double x, double y) => switch (space) {
        // Pixels: one divisor for both axes preserves every angle.
        PoseCoordinateSpace.pixels => (x / imageHeight, y / imageHeight),
        // Already 0..1, which means x was divided by the width and y by the
        // height — anisotropic. Re-stretching x by the aspect ratio undoes
        // exactly that and lands on the same isotropic space as the branch
        // above. This is recoverable only because the distortion is a known
        // constant, not because 0..1 was ever a safe unit to reason in.
        PoseCoordinateSpace.normalised => (x * aspectRatio, y),
      };
}
