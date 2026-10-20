/// Model of one guided self-timer scan: three poses, captured in order, with
/// per-pose status and retake. Immutable; every mutation returns a new value.
///
/// It stores an opaque [ScanPoseEntry.shotRef] (for example a photo id) and
/// never pixels, so it can live in plain Dart state.
library;

import 'scan_pose.dart';

/// Minimum age for the guided body scan. Scan is disabled for under-18 users.
const int kMinScanAge = 18;

/// Whether the guided body scan may be offered to a user of [age].
///
/// An unknown age (null) is NOT allowed: the feature stays off until the age is
/// known, so a missing profile field can never silently enable it for a minor.
bool scanAllowedForAge(int? age) => age != null && age >= kMinScanAge;

enum ScanPoseStatus { pending, captured }

class ScanPoseEntry {
  const ScanPoseEntry({
    required this.pose,
    this.status = ScanPoseStatus.pending,
    this.shotRef,
  });

  final ScanPose pose;
  final ScanPoseStatus status;

  /// Opaque reference to the saved shot (photo id); null while pending.
  final String? shotRef;

  bool get isCaptured => status == ScanPoseStatus.captured;
}

class ScanSession {
  /// A fresh scan with all three poses pending.
  ScanSession.start()
      : entries = List.unmodifiable([
          for (final p in ScanPose.ordered) ScanPoseEntry(pose: p),
        ]);

  const ScanSession._(this.entries);

  /// One entry per pose, always in [ScanPose.ordered] order.
  final List<ScanPoseEntry> entries;

  ScanPoseEntry entryFor(ScanPose pose) =>
      entries.firstWhere((e) => e.pose == pose);

  ScanPoseStatus statusOf(ScanPose pose) => entryFor(pose).status;

  /// The pose to capture next: the first pending one in capture order. After
  /// [retake] this is the retaken pose; once it is shot, it moves on to the next
  /// pending pose. Null when the scan is complete.
  ScanPose? get currentPose {
    for (final e in entries) {
      if (!e.isCaptured) return e.pose;
    }
    return null;
  }

  bool get isComplete => entries.every((e) => e.isCaptured);

  int get capturedCount => entries.where((e) => e.isCaptured).length;

  /// Record a shot for [pose]. The pose must be pending; retake it first to
  /// replace an existing shot.
  ScanSession markCaptured(ScanPose pose, String shotRef) {
    if (statusOf(pose) == ScanPoseStatus.captured) {
      throw StateError('$pose already captured; call retake first');
    }
    return _replace(
      pose,
      ScanPoseEntry(
        pose: pose,
        status: ScanPoseStatus.captured,
        shotRef: shotRef,
      ),
    );
  }

  /// Discard the shot of [pose] so it becomes the current pose again. The
  /// caller owns deleting the stored photo behind the old `shotRef`.
  ScanSession retake(ScanPose pose) =>
      _replace(pose, ScanPoseEntry(pose: pose));

  ScanSession _replace(ScanPose pose, ScanPoseEntry entry) => ScanSession._(
        List.unmodifiable([
          for (final e in entries) e.pose == pose ? entry : e,
        ]),
      );
}
