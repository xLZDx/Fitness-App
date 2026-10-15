/// On-device image preparation for the food AI calls (design s17.2, s17.6):
/// bake the EXIF orientation, resize to a long edge, and re-encode a JPEG from
/// raw pixels so no EXIF / GPS / ICC block is carried over. Pure function plus
/// an isolate wrapper; no Flutter widgets.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Long edge of a meal photo sent to `analyzeMealPhoto`.
const int kMealLongEdge = 1024;

/// Long edge of a label photo sent to `parseNutritionLabel`.
const int kLabelLongEdge = 1280;

/// Long edge of the optional private on-device thumbnail.
const int kMealThumbLongEdge = 256;

/// Upper bound for the encoded bytes (the server accepts 3 MB per image).
const int kPreparedMaxBytes = 3 * 1024 * 1024;

/// Returns re-encoded JPEG bytes whose long edge is at most [longEdge], or null
/// when [source] is not a decodable image or cannot be brought under
/// [kPreparedMaxBytes]. Never enlarges an image.
Uint8List? prepareJpeg(Uint8List source, {required int longEdge}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final edge = math.max(image.width, image.height);
  if (edge > longEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: longEdge)
        : img.copyResize(image, height: longEdge);
  }
  for (final quality in const [85, 70, 55]) {
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (bytes.length <= kPreparedMaxBytes) return bytes;
  }
  return null;
}

class _PrepareJob {
  const _PrepareJob(this.bytes, this.longEdge);
  final Uint8List bytes;
  final int longEdge;
}

Uint8List? _run(_PrepareJob job) => prepareJpeg(job.bytes, longEdge: job.longEdge);

/// [prepareJpeg] off the UI isolate.
Future<Uint8List?> prepareJpegInBackground(
  Uint8List source, {
  required int longEdge,
}) =>
    compute(_run, _PrepareJob(source, longEdge));
