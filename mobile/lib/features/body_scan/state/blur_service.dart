/// On-device face blurring before any upload (design s9, D-4, D-69). FAIL
/// CLOSED: whenever the head region cannot be established, or the output
/// cannot be produced within the size limit, the verdict is a refusal and
/// nothing may be uploaded.
///
/// The geometry is `data/face_region.dart` (pure); this file does the pixels in
/// an isolate with the `image` package: bake the EXIF orientation, resize to a
/// long edge of 1280 px, pixelate the head box, blur it, and re-encode a JPEG
/// from raw pixels so no EXIF/GPS/ICC block is carried over. The blurred bytes
/// live in memory only.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../../form_check/data/pose_landmark.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../data/face_region.dart';

/// Upload size cap (the server accepts at most 3 MB per photo).
const int kBlurMaxBytes = 3 * 1024 * 1024;

/// Long edge of the uploaded image.
const int kBlurLongEdge = 1280;

/// Why a photo cannot be uploaded safely.
enum BlurRefusal {
  /// No pose landmarks (manual shutter without a detected body).
  noLandmarks,

  /// Landmarks present but the head box cannot be sized.
  cannotSize,

  /// The bytes are not a decodable image.
  undecodable,

  /// Even the lowest quality exceeds [kBlurMaxBytes].
  tooLarge,
}

sealed class BlurOutcome {
  const BlurOutcome();
}

class BlurSuccess extends BlurOutcome {
  const BlurSuccess(this.jpeg);

  final Uint8List jpeg;
}

class BlurRefused extends BlurOutcome {
  const BlurRefused(this.reason);

  final BlurRefusal reason;
}

abstract class BlurService {
  const BlurService();

  Future<BlurOutcome> blur({
    required Uint8List photo,
    required List<ScanLandmark> landmarks,
  });
}

/// The real service: pixels in a background isolate.
class IsolateBlurService extends BlurService {
  const IsolateBlurService();

  @override
  Future<BlurOutcome> blur({
    required Uint8List photo,
    required List<ScanLandmark> landmarks,
  }) async {
    final result = await compute(
      _blurInIsolate,
      _BlurJob(photo, [for (final l in landmarks) l.toJson()]),
    );
    final reason = result.refusal;
    if (reason != null) return BlurRefused(reason);
    return BlurSuccess(result.jpeg!);
  }
}

class _BlurJob {
  const _BlurJob(this.photo, this.landmarks);

  final Uint8List photo;
  final List<Map<String, Object?>> landmarks;
}

class _BlurResult {
  const _BlurResult.ok(Uint8List this.jpeg) : refusal = null;
  const _BlurResult.refused(BlurRefusal this.refusal) : jpeg = null;

  final Uint8List? jpeg;
  final BlurRefusal? refusal;
}

/// Rebuilds a [PoseFrame] from stored (image-normalised) landmarks for an
/// image of the given aspect ratio (width / height), so the pure geometry can
/// be reused unchanged.
PoseFrame frameFromScanLandmarks(
  List<ScanLandmark> landmarks,
  double aspectRatio,
) {
  final byName = {for (final t in LandmarkType.values) t.name: t};
  final out = <LandmarkType, PoseLandmark>{};
  for (final l in landmarks) {
    final t = byName[l.name];
    if (t == null || !l.x.isFinite || !l.y.isFinite) continue;
    out[t] = PoseLandmark(
      type: t,
      x: l.x * aspectRatio,
      y: l.y,
      likelihood: l.likelihood,
    );
  }
  return PoseFrame(timestampMs: 0, landmarks: out, aspectRatio: aspectRatio);
}

_BlurResult _blurInIsolate(_BlurJob job) {
  final landmarks = [
    for (final raw in job.landmarks)
      if (ScanLandmark.tryFromJson(raw) case final ok?) ok,
  ];
  if (landmarks.isEmpty) {
    return const _BlurResult.refused(BlurRefusal.noLandmarks);
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(job.photo);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return const _BlurResult.refused(BlurRefusal.undecodable);
  }
  // Landmarks come from the upright preview, so the still is upright too.
  var image = img.bakeOrientation(decoded);
  // The decoded image still carries the source EXIF (camera make, GPS) and ICC
  // profile and the encoder would write them back: drop them explicitly.
  image.exif = img.ExifData();
  image.iccProfile = null;
  final aspect = image.width / image.height;
  final verdict = computeFaceRegion(frameFromScanLandmarks(landmarks, aspect));
  final region = verdict.region;
  if (region == null) {
    return _BlurResult.refused(
      verdict.failure == FaceRegionFailure.noLandmarks
          ? BlurRefusal.noLandmarks
          : BlurRefusal.cannotSize,
    );
  }

  // Resize FIRST so the box is computed on the final pixel grid.
  final longEdge = math.max(image.width, image.height);
  if (longEdge > kBlurLongEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: kBlurLongEdge)
        : img.copyResize(image, height: kBlurLongEdge);
  }
  final box = region.toPixels(
    imageWidth: image.width,
    imageHeight: image.height,
  );
  if (box.width <= 0 || box.height <= 0) {
    return const _BlurResult.refused(BlurRefusal.cannotSize);
  }

  final side = math.max(box.width, box.height);
  final block = math.max(8, side ~/ 10);
  var patch = img.copyCrop(
    image,
    x: box.left,
    y: box.top,
    width: box.width,
    height: box.height,
  );
  patch = img.pixelate(patch, size: block);
  // Two passes: pixelation alone can be partly reversed, blur on top is not.
  patch = img.gaussianBlur(patch, radius: math.max(4, block ~/ 2));
  patch = img.gaussianBlur(patch, radius: math.max(4, block ~/ 2));
  img.compositeImage(image, patch, dstX: box.left, dstY: box.top);

  // Re-encoded from raw pixels: EXIF, GPS and ICC are not copied.
  for (final quality in const [85, 70, 55]) {
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (bytes.length <= kBlurMaxBytes) return _BlurResult.ok(bytes);
  }
  return const _BlurResult.refused(BlurRefusal.tooLarge);
}
