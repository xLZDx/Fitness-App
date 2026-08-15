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
///
/// ## Why the extent is reported twice
///
/// The operator's device produced `x -0.466..1.968 (bound 0.667) y
/// -2.173..3.015` — coordinates far outside the contract, on a session that was
/// otherwise scoring fine. Two explanations fit that line equally well and they
/// call for opposite work:
///
/// * the conversion in `pose_coordinate_space.dart` is wrong, and every number
///   downstream is being read in the wrong unit; or
/// * nothing is wrong. BlazePose emits all 33 landmarks on every frame and
///   EXTRAPOLATES the ones outside the image, so a lifter whose feet leave the
///   bottom of the frame legitimately produces `y > 1`. The service copies
///   likelihood through without filtering (`mlkit_pose_detector_service.dart`),
///   so those extrapolated joints reach this probe like any other.
///
/// A single extent over every landmark cannot tell the two apart, which is why
/// the original line could be stared at for an hour without settling anything.
/// The extent restricted to landmarks the detector is actually confident about
/// can: if the TRUSTED extent sits inside the contract while the full one does
/// not, the wide numbers are extrapolation and there is nothing to fix. If a
/// joint at likelihood 0.9 is sitting at `y = 3.0`, the conversion is broken.
///
/// Note the deliberate difference from `_unitLooksWrong` in `pose_gate.dart`,
/// which reads every landmark and ignores likelihood on purpose — for the GATE
/// that is right, because a low-confidence joint's coordinate came out of the
/// same conversion and is just as good a witness to the unit. That argument is
/// about detecting a broken unit; this one is about attributing a wide range.
/// Both are correct for their own question, and this probe does not change the
/// gate's behaviour by a line.
library;

import 'pose_coordinate_space.dart';
import 'pose_landmark.dart';

/// The bounding box of a set of observed landmarks.
class PoseExtent {
  const PoseExtent({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.landmarks,
  });

  /// Nothing observed yet — distinct from "observed and found nothing", which
  /// would otherwise print as infinities.
  static const empty =
      PoseExtent(minX: 0, maxX: 0, minY: 0, maxY: 0, landmarks: 0);

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// How many landmarks were folded in. Zero is the empty state; it is counted
  /// rather than inferred because a single landmark at the origin has zero
  /// extent and is numerically identical to [empty].
  final int landmarks;

  bool get isEmpty => landmarks == 0;

  String render() => 'x ${minX.toStringAsFixed(3)}..${maxX.toStringAsFixed(3)} '
      'y ${minY.toStringAsFixed(3)}..${maxY.toStringAsFixed(3)}';

  @override
  bool operator ==(Object other) =>
      other is PoseExtent &&
      other.minX == minX &&
      other.maxX == maxX &&
      other.minY == minY &&
      other.maxY == maxY &&
      other.isEmpty == isEmpty;

  @override
  int get hashCode => Object.hash(minX, maxX, minY, maxY, isEmpty);
}

/// What the probe has seen so far.
class PoseUnitReport {
  const PoseUnitReport({
    required this.frames,
    required this.all,
    required this.trusted,
    required this.minLikelihood,
    required this.spaces,
    required this.aspectRatio,
  });

  static const empty = PoseUnitReport(
    frames: 0,
    all: PoseExtent.empty,
    trusted: PoseExtent.empty,
    minLikelihood: 0,
    spaces: <PoseCoordinateSpace>{},
    aspectRatio: 0,
  );

  final int frames;

  /// Every landmark the detector produced, extrapolated ones included.
  final PoseExtent all;

  /// Only landmarks at or above [minLikelihood] — the ones a wrong unit would
  /// have to show up in for the conversion to be the culprit.
  final PoseExtent trusted;

  final double minLikelihood;

  /// Every raw space seen. More than one entry means the detector changed its
  /// mind mid-session, which would make any single-hypothesis fix wrong.
  final Set<PoseCoordinateSpace> spaces;

  /// Last observed frame aspect ratio, i.e. the expected upper bound of x.
  final double aspectRatio;

  bool get isEmpty => frames == 0;

  double get minX => all.minX;
  double get maxX => all.maxX;
  double get minY => all.minY;
  double get maxY => all.maxY;

  /// True when a landmark the detector is CONFIDENT about sits outside the
  /// coordinate contract — `y` outside `0..1`, or `x` outside `0..aspectRatio`.
  ///
  /// This is the question Gate B exists to answer, expressed as a boolean so it
  /// can be asserted in a test rather than eyeballed off a phone. No slack: the
  /// slack in `PoseGateConfig.unitSanitySlack` is there to avoid false alarms in
  /// a gate that blocks the user, whereas this is a diagnostic and a trusted
  /// joint one percent outside the frame is exactly the signal worth seeing.
  bool get trustedOutOfContract {
    if (trusted.isEmpty) return false;
    return trusted.minY < 0 ||
        trusted.maxY > 1.0 ||
        trusted.minX < 0 ||
        trusted.maxX > aspectRatio;
  }

  /// Two lines, short enough to read off a phone and precise enough to act on.
  ///
  /// Reports the aspect ratio next to the x range on purpose: `x` is in-contract
  /// when it stays under the ratio, so printing the bound beside the measurement
  /// means the reader does not have to remember what the bound was.
  ///
  /// The second line is the one that decides Gate B, and it says which way it
  /// decided in words — nobody holding a phone at arm's length should have to
  /// compare six decimals against a bound to find out.
  String get summary {
    if (isEmpty) return 'pose: no frames yet';
    final space = spaces.length == 1
        ? spaces.first.name
        : spaces.map((s) => s.name).join('+');
    final head = 'pose[$space] n=$frames all ${all.render()} '
        '(bound ${aspectRatio.toStringAsFixed(3)})';
    if (trusted.isEmpty) {
      return '$head\ntrusted>=${minLikelihood.toStringAsFixed(2)}: none seen';
    }
    final verdict = trustedOutOfContract ? 'OUT OF CONTRACT' : 'in contract';
    return '$head\ntrusted>=${minLikelihood.toStringAsFixed(2)} '
        'k=${trusted.landmarks} ${trusted.render()} -> $verdict';
  }

  /// Value equality, deliberately **excluding** [frames].
  ///
  /// This report is published to a `StateProvider`, which suppresses a
  /// notification when the new value equals the old one. The extents stop moving
  /// within a second or two of a steady camera, so comparing on extents alone
  /// means the diagnostic line repaints while it is still learning something and
  /// then goes quiet — instead of forcing a rebuild 30 times a second forever
  /// just because a counter ticked.
  ///
  /// [trusted] is compared too: a trusted extent that widens is the single most
  /// interesting thing this probe can observe, and leaving it out would freeze
  /// the line precisely when it started to matter.
  @override
  bool operator ==(Object other) =>
      other is PoseUnitReport &&
      other.all == all &&
      other.trusted == trusted &&
      other.minLikelihood == minLikelihood &&
      other.aspectRatio == aspectRatio &&
      other.isEmpty == isEmpty &&
      other.spaces.length == spaces.length &&
      other.spaces.containsAll(spaces);

  @override
  int get hashCode => Object.hash(
      all, trusted, minLikelihood, aspectRatio, isEmpty, spaces.length);
}

/// Accumulates a [PoseUnitReport] over a session's frames.
class PoseUnitProbe {
  PoseUnitProbe({this.minLikelihood = 0.7});

  /// Matches `PoseGateConfig.minLikelihood` by default, so "trusted" here means
  /// the same thing it means everywhere else in the pipeline.
  final double minLikelihood;

  int _frames = 0;
  double _aspectRatio = 0;
  final Set<PoseCoordinateSpace> _spaces = <PoseCoordinateSpace>{};

  final _Acc _all = _Acc();
  final _Acc _trusted = _Acc();

  /// Folds one frame in. Frames with no landmarks are ignored rather than
  /// counted, so `n` reports frames that carried evidence, not frames that
  /// arrived.
  void observe(PoseFrame frame) {
    if (frame.landmarks.isEmpty) return;

    // The counter is incremented only once a coordinate has actually been
    // folded in. Counting the frame first looked equivalent and was not: a
    // frame whose every coordinate is NaN would leave the extents at their
    // infinite seeds while `frames` said 1, and `summary` would render
    // "x Infinity..-Infinity". An all-NaN frame is one of the two states that
    // produce a unit mismatch, so the diagnostic that exists to explain that
    // state was the one guaranteed to print nothing usable in it.
    var usable = false;
    for (final lm in frame.landmarks.values) {
      if (lm.x.isNaN || lm.y.isNaN) continue;
      usable = true;
      _all.add(lm.x, lm.y);
      if (lm.likelihood >= minLikelihood) _trusted.add(lm.x, lm.y);
    }
    if (!usable) return;

    _frames++;
    _aspectRatio = frame.aspectRatio;
    final space = frame.sourceSpace;
    if (space != null) _spaces.add(space);
  }

  void reset() {
    _frames = 0;
    _aspectRatio = 0;
    _spaces.clear();
    _all.reset();
    _trusted.reset();
  }

  PoseUnitReport get report => _frames == 0
      ? PoseUnitReport.empty
      : PoseUnitReport(
          frames: _frames,
          all: _all.extent,
          trusted: _trusted.extent,
          minLikelihood: minLikelihood,
          spaces: Set.unmodifiable(_spaces),
          aspectRatio: _aspectRatio,
        );
}

/// A running bounding box. Private because the seeds are infinite and only
/// [extent] is safe to read.
class _Acc {
  double _minX = double.infinity;
  double _maxX = double.negativeInfinity;
  double _minY = double.infinity;
  double _maxY = double.negativeInfinity;
  int _n = 0;

  void add(double x, double y) {
    _n++;
    if (x < _minX) _minX = x;
    if (x > _maxX) _maxX = x;
    if (y < _minY) _minY = y;
    if (y > _maxY) _maxY = y;
  }

  void reset() {
    _minX = double.infinity;
    _maxX = double.negativeInfinity;
    _minY = double.infinity;
    _maxY = double.negativeInfinity;
    _n = 0;
  }

  PoseExtent get extent => _n == 0
      ? PoseExtent.empty
      : PoseExtent(
          minX: _minX, maxX: _maxX, minY: _minY, maxY: _maxY, landmarks: _n);
}
