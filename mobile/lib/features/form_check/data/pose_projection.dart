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
/// So drawing a landmark is not `x * width, y * height`. That is the mapping the
/// silhouette uses, and it is right for the silhouette because those targets are
/// AUTHORED in the box's own coordinates. A measured landmark is in the camera's,
/// and scaling the two axes by different factors is a shear: a straight back
/// would render as a bent one, most visibly on a body that fills the frame.
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
  return Offset(mirror ? canvas.width - px : px, py);
}
