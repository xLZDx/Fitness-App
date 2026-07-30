import 'dart:io';

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
