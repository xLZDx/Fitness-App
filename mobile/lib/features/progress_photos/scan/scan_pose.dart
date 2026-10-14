/// The three poses of one guided body scan, in capture order.
///
/// Pure Dart (no camera or plugin imports) so the whole scan logic is testable
/// without a device.
library;

enum ScanPose {
  front,
  side,
  back;

  /// Capture order is the declaration order: front, then side, then back.
  static const List<ScanPose> ordered = ScanPose.values;
}
