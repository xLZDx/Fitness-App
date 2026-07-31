/// Read-only measurement of what the pose detector actually produces on a real
/// device, so the next round of threshold work is grounded in observation
/// instead of in the same assumption that produced the current thresholds.
///
/// Every number in `pose_gate.dart`, `rep_counter.dart` and
/// `form_classifier.dart` was chosen against an *imagined* range. This probe is
/// how that stops: it accumulates the observed extent of the converted
/// coordinates, plus which raw space they arrived in, and renders one line that
/// can be read off a phone screen and typed into a plan.
///
/// It never influences scoring. Nothing reads its output but the UI.
library;

import 'pose_coordinate_space.dart';
import 'pose_landmark.dart';

/// What the probe has seen so far.
class PoseUnitReport {
  const PoseUnitReport({
    required this.frames,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.spaces,
    required this.aspectRatio,
  });

  /// Nothing observed yet — distinct from "observed and found nothing", which
  /// would otherwise print as infinities.
  static const empty = PoseUnitReport(
    frames: 0,
    minX: 0,
    maxX: 0,
    minY: 0,
    maxY: 0,
    spaces: <PoseCoordinateSpace>{},
    aspectRatio: 0,
  );

  final int frames;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// Every raw space seen. More than one entry means the detector changed its
  /// mind mid-session, which would make any single-hypothesis fix wrong.
  final Set<PoseCoordinateSpace> spaces;

  /// Last observed frame aspect ratio, i.e. the expected upper bound of x.
  final double aspectRatio;

  bool get isEmpty => frames == 0;

  /// One line, short enough to read off a phone and precise enough to act on.
  ///
  /// Reports the aspect ratio next to the x range on purpose: `x` is in-contract
  /// when it stays under the ratio, so printing the bound beside the measurement
  /// means the reader does not have to remember what the bound was.
  String get summary {
    if (isEmpty) return 'pose: no frames yet';
    final space = spaces.length == 1
        ? spaces.first.name
        : spaces.map((s) => s.name).join('+');
    return 'pose[$space] n=$frames '
        'x ${minX.toStringAsFixed(3)}..${maxX.toStringAsFixed(3)} '
        '(bound ${aspectRatio.toStringAsFixed(3)}) '
        'y ${minY.toStringAsFixed(3)}..${maxY.toStringAsFixed(3)}';
  }

  /// Value equality, deliberately **excluding** [frames].
  ///
  /// This report is published to a `StateProvider`, which suppresses a
  /// notification when the new value equals the old one. The extents stop moving
  /// within a second or two of a steady camera, so comparing on extents alone
  /// means the diagnostic line repaints while it is still learning something and
  /// then goes quiet — instead of forcing a rebuild 30 times a second forever
  /// just because a counter ticked.
  @override
  bool operator ==(Object other) =>
      other is PoseUnitReport &&
      other.minX == minX &&
      other.maxX == maxX &&
      other.minY == minY &&
      other.maxY == maxY &&
      other.aspectRatio == aspectRatio &&
      other.isEmpty == isEmpty &&
      other.spaces.length == spaces.length &&
      other.spaces.containsAll(spaces);

  @override
  int get hashCode =>
      Object.hash(minX, maxX, minY, maxY, aspectRatio, isEmpty, spaces.length);
}

/// Accumulates a [PoseUnitReport] over a session's frames.
class PoseUnitProbe {
  int _frames = 0;
  double _minX = double.infinity;
  double _maxX = double.negativeInfinity;
  double _minY = double.infinity;
  double _maxY = double.negativeInfinity;
  double _aspectRatio = 0;
  final Set<PoseCoordinateSpace> _spaces = <PoseCoordinateSpace>{};

  /// Folds one frame in. Frames with no landmarks are ignored rather than
  /// counted, so `n` reports frames that carried evidence, not frames that
  /// arrived.
  void observe(PoseFrame frame) {
    if (frame.landmarks.isEmpty) return;
    _frames++;
    _aspectRatio = frame.aspectRatio;
    final space = frame.sourceSpace;
    if (space != null) _spaces.add(space);
    for (final lm in frame.landmarks.values) {
      if (lm.x.isNaN || lm.y.isNaN) continue;
      if (lm.x < _minX) _minX = lm.x;
      if (lm.x > _maxX) _maxX = lm.x;
      if (lm.y < _minY) _minY = lm.y;
      if (lm.y > _maxY) _maxY = lm.y;
    }
  }

  void reset() {
    _frames = 0;
    _minX = double.infinity;
    _maxX = double.negativeInfinity;
    _minY = double.infinity;
    _maxY = double.negativeInfinity;
    _aspectRatio = 0;
    _spaces.clear();
  }

  PoseUnitReport get report => _frames == 0
      ? PoseUnitReport.empty
      : PoseUnitReport(
          frames: _frames,
          minX: _minX,
          maxX: _maxX,
          minY: _minY,
          maxY: _maxY,
          spaces: Set.unmodifiable(_spaces),
          aspectRatio: _aspectRatio,
        );
}
