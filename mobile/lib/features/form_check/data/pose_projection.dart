import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Where a landmark lands on the camera preview.
///
/// Landmarks arrive in the isotropic space described by
/// `pose_coordinate_space.dart`: both axes divided by the image height, so the
/// frame is `aspectRatio` wide and exactly `1.0` tall. The preview is a widget
/// of some other shape entirely — a 9:16 panel on this page — and `CameraPreview`
/// fills it, cropping whatever does not fit.
///
/// So drawing a landmark is not `x * width, y * height`. Scaling the two axes by
/// different factors is a shear: a straight back renders as a bent one, most
/// visibly on a body that fills the frame.
///
/// This comment used to go on to say that `x * width, y * height` was fine for
/// the silhouette, "because those targets are AUTHORED in the box's own
/// coordinates". That was wrong, and a screen recording of the coach is what
/// proved it: on this page's 9:16 panel the outline came out squeezed 1.78x
/// horizontally — a tall thin stalk under a large circle. Coordinates authored
/// to look like a person encode a claim about proportion, and a per-axis scale
/// destroys it exactly as thoroughly here as anywhere else. The silhouette now
/// fits itself with one scale, in `pose_silhouette.dart`.
///
/// This is the same class of mistake as the anisotropic normalisation that was
/// already fixed once inside the detector, which is why it is a named function
/// with tests rather than two multiplications inside a painter.
Offset projectLandmark(
  double x,
  double y, {
  required double frameAspect,
  required Size canvas,
  bool mirror = false,
}) {
  // Cover, not contain: `CameraPreview` inside an expanded Stack fills the box
  // and loses the overflow. Matching that means scaling by whichever axis needs
  // the larger factor, then centring — the crop is symmetric.
  final scale = math.max(canvas.width / frameAspect, canvas.height);
  final offsetX = (canvas.width - frameAspect * scale) / 2;
  final offsetY = (canvas.height - scale) / 2;
  final px = x * scale + offsetX;
  final py = y * scale + offsetY;
  // The front camera shows the user a mirror, because a preview that moves the
  // opposite way to the body is unusable. Whether the platform has already done
  // it is a per-device question, which is why this is a parameter and not an
  // assumption baked into the maths.
  //
  // UNWIRED, deliberately: no production caller passes it, and it is left here
  // rather than deleted because the question it answers is open, not because it
  // is dead. It could not have been answered before 2026-08-15 — the avatar was
  // drawn by mirroring one side of the body, so it was bilaterally symmetric
  // and a left/right flip was invisible by construction. Now that each limb is
  // drawn from its own observation, one look at the device settles it: raise
  // one hand, and see whether the figure raises the hand on the same side the
  // user perceives.
  //
  // Do not wire it on inference. The answer differs between the two surfaces —
  // the skeleton drawn over a camera preview the platform may already have
  // mirrored, and the avatar drawn over a photograph with no preview behind it
  // at all — so it is two measurements, not one.
  return Offset(mirror ? canvas.width - px : px, py);
}
