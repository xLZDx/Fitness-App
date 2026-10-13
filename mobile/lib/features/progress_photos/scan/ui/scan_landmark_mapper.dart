/// Conversions between the live pose frame, the stored [ScanLandmark]s and the
/// keypoints [BodyAlignment] works on.
///
/// Coordinates: a `PoseFrame` is isotropic (x in 0..aspectRatio, y in 0..1).
/// Stored landmarks are normalised to the image (x/aspectRatio, y), so they do
/// not depend on the capture resolution. Stills and the analysis stream both
/// come off the sensor un-mirrored (only the on-screen preview of a selfie
/// camera is mirrored), so landmarks and photo agree for either lens.
library;

import '../../../form_check/data/pose_landmark.dart';
import '../body_alignment.dart';
import '../scan_models.dart';

/// Landmarks below this likelihood are not stored as usable points.
const double kScanMinStoredLikelihood = 0.5;

/// Aspect ratio (width / height) of the box the compare screen draws photos
/// in, and the x scale that makes the normalised x isotropic with y. Stills are
/// portrait 3:4 on the supported camera presets; a device with another sensor
/// ratio only costs some alignment precision, never a wrong claim.
const double kScanDisplayAspect = 0.75;

List<ScanLandmark> landmarksFromFrame(PoseFrame? frame) {
  if (frame == null) return const [];
  final a = frame.aspectRatio <= 0 ? 1.0 : frame.aspectRatio;
  return [
    for (final e in frame.landmarks.entries)
      ScanLandmark(
        name: e.key.name,
        x: e.value.x / a,
        y: e.value.y,
        likelihood: e.value.likelihood,
      ),
  ];
}

/// Keypoints for alignment, in the isotropic display space (x scaled by
/// [kScanDisplayAspect]). Missing or low-confidence landmarks are omitted.
Map<BodyKeypoint, Point2> keypointsFromLandmarks(List<ScanLandmark> landmarks) {
  final byName = {
    for (final l in landmarks)
      if (l.likelihood >= kScanMinStoredLikelihood &&
          l.x.isFinite &&
          l.y.isFinite)
        l.name: l,
  };
  Point2? pt(String n) {
    final l = byName[n];
    return l == null ? null : Point2(l.x * kScanDisplayAspect, l.y);
  }

  final out = <BodyKeypoint, Point2>{};
  void put(BodyKeypoint k, Point2? p) {
    if (p != null) out[k] = p;
  }

  put(BodyKeypoint.head, pt(LandmarkType.nose.name) ?? _earMid(byName));
  put(BodyKeypoint.leftShoulder, pt(LandmarkType.leftShoulder.name));
  put(BodyKeypoint.rightShoulder, pt(LandmarkType.rightShoulder.name));
  put(BodyKeypoint.leftHip, pt(LandmarkType.leftHip.name));
  put(BodyKeypoint.rightHip, pt(LandmarkType.rightHip.name));
  put(BodyKeypoint.leftKnee, pt(LandmarkType.leftKnee.name));
  put(BodyKeypoint.rightKnee, pt(LandmarkType.rightKnee.name));
  put(BodyKeypoint.leftAnkle, pt(LandmarkType.leftAnkle.name));
  put(BodyKeypoint.rightAnkle, pt(LandmarkType.rightAnkle.name));
  return out;
}

Point2? _earMid(Map<String, ScanLandmark> byName) {
  final l = byName[LandmarkType.leftEar.name];
  final r = byName[LandmarkType.rightEar.name];
  if (l != null && r != null) {
    return Point2((l.x + r.x) / 2 * kScanDisplayAspect, (l.y + r.y) / 2);
  }
  final one = l ?? r;
  return one == null ? null : Point2(one.x * kScanDisplayAspect, one.y);
}
