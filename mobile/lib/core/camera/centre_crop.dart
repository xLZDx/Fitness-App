import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Crops a photo to its central region and writes it next to the original.
///
/// Why: gyms pack machines shoulder to shoulder, so a full-frame photo almost
/// always contains three of them and the classifier has to gamble on which
/// one was meant (operator point 3). The Scan page draws a guide frame in the
/// middle of the viewfinder; this makes the classifier see the same thing the
/// user framed.
///
/// EXIF orientation is baked in before cropping — phone JPEGs are stored
/// sideways with a rotation tag, and cropping "the centre" of the un-rotated
/// bytes would crop the wrong axis.
///
/// Any failure returns the ORIGINAL path with a log: an uncropped photo still
/// classifies, a thrown crop would turn a nice-to-have into a new failure
/// mode.
///
/// Since SCAN-G1 the Scan page's own capture path uses [cropToViewfinder]
/// instead -- the reference's viewfinder is a fixed 230px landscape card, not
/// a 75% square, so "what the user framed" is no longer a centre fraction of
/// the photo. This stays for callers that have no viewfinder geometry.
Future<String> centreCropForClassification(
  String path, {
  double fraction = 0.75,
}) async {
  try {
    final bytes = await File(path).readAsBytes();
    final cropped = await compute(_cropCentre, (bytes, fraction));
    if (cropped == null) return path;
    final out = File('$path.centre.jpg');
    await out.writeAsBytes(cropped, flush: true);
    return out.path;
  } catch (e) {
    debugPrint('centre crop failed, classifying full frame: $e');
    return path;
  }
}

Uint8List? _cropCentre((Uint8List, double) args) {
  final (bytes, fraction) = args;
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = img.bakeOrientation(decoded);
  final w = (decoded.width * fraction).round();
  final h = (decoded.height * fraction).round();
  if (w < 32 || h < 32) return null;
  final cropped = img.copyCrop(
    decoded,
    x: (decoded.width - w) ~/ 2,
    y: (decoded.height - h) ~/ 2,
    width: w,
    height: h,
  );
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 88));
}

/// Where, in a photo of [image] pixels, the viewfinder's bracket window lies.
///
/// SCAN-G1 (core/SCAN_G1_SCOPE.md, R3/R7). The Scan card shows the camera
/// through `LiveEquipmentPreview`, which is a *cover* fit: the frame is scaled
/// by `max(viewport.width / image.width, viewport.height / image.height)` and
/// centred, so whatever overflows the card on the long axis is simply not
/// shown. The bracket window ([windowNormalized], as fractions of the
/// [viewport]) therefore maps back into the photo by the inverse of that
/// transform. The result is clamped to the image so a window that reaches
/// past the shown region (it cannot, by construction, but a caller could
/// pass one) never produces a crop outside the pixels.
///
/// Pure, so the arithmetic is testable against hand-computed numbers
/// (`centre_crop_test.dart`) without a camera. [image] is the photo's size
/// AFTER its EXIF orientation is baked in -- the same orientation the preview
/// showed -- which is what [cropToViewfinder] passes.
Rect viewfinderSourceRect(Size image, Size viewport, Rect windowNormalized) {
  if (image.isEmpty || viewport.isEmpty) {
    return Rect.fromLTWH(0, 0, image.width, image.height);
  }
  final double scale = math.max(
    viewport.width / image.width,
    viewport.height / image.height,
  );
  // Where the scaled image's top-left lands in the viewport (<= 0 on the
  // axis that overflows, 0 on the axis that fits exactly).
  final double dx = (viewport.width - image.width * scale) / 2;
  final double dy = (viewport.height - image.height * scale) / 2;
  double sx(double fx) =>
      ((fx * viewport.width - dx) / scale).clamp(0.0, image.width);
  double sy(double fy) =>
      ((fy * viewport.height - dy) / scale).clamp(0.0, image.height);
  return Rect.fromLTRB(
    sx(windowNormalized.left),
    sy(windowNormalized.top),
    sx(windowNormalized.right),
    sy(windowNormalized.bottom),
  );
}

/// Crops the photo at [path] to what the Scan card's bracket window showed.
///
/// [viewport] is the card's rendered logical size at capture time and
/// [windowNormalized] the bracket window as fractions of it (inset 20px on a
/// 358x230 card: `Rect.fromLTRB(20/358, 20/230, 1 - 20/358, 1 - 20/230)`).
/// EXIF orientation is baked in first, exactly as [centreCropForClassification]
/// does and for the same reason. Writes `<path>.viewfinder.jpg` and returns
/// its path.
///
/// Fail-open, same contract as [centreCropForClassification]: any failure
/// returns the ORIGINAL path with a log, because an uncropped photo still
/// classifies and a thrown crop would be a new failure mode. Callers that
/// need to know whether the crop happened compare the returned path with the
/// input (the evidence mode of the Scan page does).
Future<String> cropToViewfinder(
  String path, {
  required Size viewport,
  required Rect windowNormalized,
}) async {
  try {
    final bytes = await File(path).readAsBytes();
    final cropped = await compute(
      _cropWindow,
      (
        bytes,
        viewport.width,
        viewport.height,
        windowNormalized.left,
        windowNormalized.top,
        windowNormalized.right,
        windowNormalized.bottom,
      ),
    );
    if (cropped == null) return path;
    final out = File('$path.viewfinder.jpg');
    await out.writeAsBytes(cropped, flush: true);
    return out.path;
  } catch (e) {
    debugPrint('viewfinder crop failed, classifying full frame: $e');
    return path;
  }
}

Uint8List? _cropWindow(
  (Uint8List, double, double, double, double, double, double) args,
) {
  final (bytes, vw, vh, l, t, r, b) = args;
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = img.bakeOrientation(decoded);
  final Rect src = viewfinderSourceRect(
    Size(decoded.width.toDouble(), decoded.height.toDouble()),
    Size(vw, vh),
    Rect.fromLTRB(l, t, r, b),
  );
  final int x = src.left.round();
  final int y = src.top.round();
  final int w = src.right.round() - x;
  final int h = src.bottom.round() - y;
  if (w < 32 || h < 32) return null;
  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 88));
}
