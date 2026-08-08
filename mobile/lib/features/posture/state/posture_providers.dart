// R10 -- posture capture session. Mirrors `form_check_providers.dart`'s
// shape (Notifier subscribed to the same `poseDetectorServiceProvider`
// frame stream) but averages a fixed window instead of counting reps: this
// is a static stand, not a movement with a phase to detect.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../form_check/data/pose_landmark.dart';
import '../../form_check/state/form_check_providers.dart'
    show poseDetectorServiceProvider;
import 'package:fitness_app/features/posture/data/measured_posture_config.dart';
import 'package:fitness_app/features/posture/data/posture_metrics.dart';

/// Below this, a landmark is not trusted -- same floor the metric-function
/// tests exercise (`posture_metrics_test.dart`).
const double posturekMinLikelihood = 0.5;

/// How long a single check samples frames for, by default. A provider
/// rather than a bare constant so a test can shrink it instead of waiting
/// out a real 2.5s `Timer` (`postureCaptureDurationProvider.overrideWithValue`).
final postureCaptureDurationProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 2500));

enum PostureCapturePhase { idle, capturing, done }

class PostureMetricResult {
  const PostureMetricResult({required this.value, required this.verdict});
  final double value;
  final PostureVerdict verdict;
}

class PostureResult {
  const PostureResult({
    this.shoulderAsymmetry,
    this.pelvisTilt,
    this.forwardHead,
  });

  final PostureMetricResult? shoulderAsymmetry;
  final PostureMetricResult? pelvisTilt;
  final PostureMetricResult? forwardHead;

  /// True when the capture window never saw enough of the body to compute
  /// even one metric -- distinct from a single metric coming back null,
  /// which the screen reports per-card instead of as a total failure.
  bool get isEmpty =>
      shoulderAsymmetry == null && pelvisTilt == null && forwardHead == null;
}

class PostureSessionState {
  const PostureSessionState({
    this.phase = PostureCapturePhase.idle,
    this.result,
  });

  final PostureCapturePhase phase;
  final PostureResult? result;
}

double _average(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

PostureMetricResult? _summarizeOne(
        List<double> samples, MeasuredPostureRange range) =>
    samples.isEmpty
        ? null
        : PostureMetricResult(
            value: _average(samples), verdict: range.verdictFor(_average(samples)));

/// Pure summarizing step, split out from the controller so the averaging +
/// verdict logic is testable without a `Timer` or a frame stream -- the same
/// split `RepCounter` draws between its own pure state machine and
/// `RepSessionController`'s stream plumbing.
PostureResult summarizePostureCapture({
  required List<double> shoulderAsymmetrySamples,
  required List<double> pelvisTiltSamples,
  required List<double> forwardHeadSamples,
}) {
  return PostureResult(
    shoulderAsymmetry:
        _summarizeOne(shoulderAsymmetrySamples, shoulderAsymmetryRange),
    pelvisTilt: _summarizeOne(pelvisTiltSamples, pelvisTiltRange),
    forwardHead: _summarizeOne(forwardHeadSamples, forwardHeadRange),
  );
}

/// Samples frames for [postureCaptureDurationProvider], averages each metric
/// across every frame that had the joints to compute it, and reports one
/// verdict per metric. Averaging rather than reading a single frame for the
/// same reason a rep is judged on its peak match, not one instant: a lone
/// noisy frame -- a blink of misdetection -- must not decide the verdict.
class PostureSessionController extends Notifier<PostureSessionState> {
  StreamSubscription<PoseFrame>? _sub;
  Timer? _timer;
  final List<double> _shoulder = [];
  final List<double> _pelvis = [];
  final List<double> _head = [];

  @override
  PostureSessionState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
    });
    return const PostureSessionState();
  }

  void start() {
    _sub?.cancel();
    _timer?.cancel();
    _shoulder.clear();
    _pelvis.clear();
    _head.clear();
    state = const PostureSessionState(phase: PostureCapturePhase.capturing);

    final svc = ref.read(poseDetectorServiceProvider);
    _sub = svc.frames().listen(_onFrame);
    _timer = Timer(ref.read(postureCaptureDurationProvider), _finish);
  }

  void _onFrame(PoseFrame frame) {
    final shoulder =
        shoulderAsymmetrySignal(frame, posturekMinLikelihood);
    if (shoulder != null) _shoulder.add(shoulder);
    final pelvis = pelvisTiltSignal(frame, posturekMinLikelihood);
    if (pelvis != null) _pelvis.add(pelvis);
    final head = forwardHeadSignal(frame, posturekMinLikelihood);
    if (head != null) _head.add(head);
  }

  void _finish() {
    _sub?.cancel();
    _sub = null;
    state = PostureSessionState(
      phase: PostureCapturePhase.done,
      result: summarizePostureCapture(
        shoulderAsymmetrySamples: _shoulder,
        pelvisTiltSamples: _pelvis,
        forwardHeadSamples: _head,
      ),
    );
  }

  /// Back to the start prompt, discarding any result -- so leaving and
  /// returning to the screen does not show a verdict from a previous stand
  /// over a camera that has not captured anything yet this visit.
  void reset() {
    _sub?.cancel();
    _timer?.cancel();
    _sub = null;
    _timer = null;
    state = const PostureSessionState();
  }
}

final postureSessionControllerProvider =
    NotifierProvider<PostureSessionController, PostureSessionState>(
        PostureSessionController.new);
