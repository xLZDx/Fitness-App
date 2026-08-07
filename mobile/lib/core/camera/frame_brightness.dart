import 'dart:typed_data';

/// Average brightness of a camera frame, 0.0 (black) to 1.0 (white).
///
/// R2.2 state 9. A pure function over bytes, deliberately separated from
/// [CameraSession]: brightness is the one part of the low-light gate that can
/// be proven with a unit test instead of a device, and a frame-rate code path
/// that cannot be tested is a frame-rate code path nobody will dare change.
///
/// Sampled, not summed. A 1280x720 frame is ~920k luma bytes and this runs on
/// the UI isolate for every delivered frame; averaging all of them would cost
/// more than the recognition it is guarding. [maxSamples] evenly-spaced reads
/// answer "is this room dark" just as well — the question has no need of
/// per-pixel precision.
double? averageFrameBrightness(
  Uint8List bytes, {
  required bool interleavedBgra,
  int maxSamples = 2048,
}) {
  if (bytes.isEmpty) return null;
  // BGRA carries four bytes per pixel; a luma plane carries one.
  final bytesPerPixel = interleavedBgra ? 4 : 1;
  final pixels = bytes.length ~/ bytesPerPixel;
  if (pixels == 0) return null;

  final step = pixels <= maxSamples ? 1 : pixels ~/ maxSamples;
  var total = 0.0;
  var taken = 0;
  for (var p = 0; p < pixels; p += step) {
    final i = p * bytesPerPixel;
    if (interleavedBgra) {
      // BGRA byte order. Rec. 601 luma weights — the same ones the rest of
      // the imaging world uses for "how bright does this look".
      final b = bytes[i];
      final g = bytes[i + 1];
      final r = bytes[i + 2];
      total += 0.299 * r + 0.587 * g + 0.114 * b;
    } else {
      // YUV420's first plane IS luma; no conversion to do.
      total += bytes[i];
    }
    taken++;
  }
  if (taken == 0) return null;
  return (total / taken) / 255.0;
}

/// Below this the viewfinder is dark enough that recognition is unreliable.
///
/// NOT calibrated against a labelled set of gym photographs — it is a starting
/// value picked so that an ordinarily-lit room sits well above it and a
/// genuinely dark one below. Named and in one place so it can be moved from
/// evidence later rather than re-guessed at a call site.
const double kLowLightBrightness = 0.18;

/// How many consecutive dark frames before the user is told.
///
/// One frame is not a lighting condition: a hand passing the lens, or the
/// auto-exposure still settling after the camera opens, both produce a dark
/// frame in an otherwise fine room. A banner that flickers on those is worse
/// than no banner, because the user learns to ignore it.
const int kLowLightFrameRun = 8;
