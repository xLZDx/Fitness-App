/// PORT for the post-blur face check (design s9, D-69). Pure Dart, no Flutter
/// imports.
///
/// Before `BODY_SCAN_CLOUD` is ever enabled an on-device detector must run on
/// the BLURRED output and the upload must be refused when any face remains.
/// This sprint ships the seam, not the detector: the DEFAULT implementation
/// answers "cannot verify", which the pipeline treats as a refusal, so flipping
/// the flag without a detector uploads nothing.
library;

import 'dart:typed_data';

sealed class FaceCheckResult {
  const FaceCheckResult();
}

/// The detector ran and found [count] faces in the blurred bytes.
class FacesFound extends FaceCheckResult {
  const FacesFound(this.count);

  final int count;
}

/// No detector is available or it failed: nothing can be claimed.
class FaceCheckUnavailable extends FaceCheckResult {
  const FaceCheckUnavailable();
}

/// True only when the detector verified ZERO faces. Anything else, including
/// "cannot verify", refuses the upload.
bool faceCheckAllowsUpload(FaceCheckResult r) =>
    r is FacesFound && r.count == 0;

abstract class FaceCheckPort {
  const FaceCheckPort();

  Future<FaceCheckResult> countFaces(Uint8List blurredJpeg);
}

/// The fail-closed default.
class UnavailableFaceCheck extends FaceCheckPort {
  const UnavailableFaceCheck();

  @override
  Future<FaceCheckResult> countFaces(Uint8List blurredJpeg) async =>
      const FaceCheckUnavailable();
}
