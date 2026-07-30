import 'visual_equipment_match.dart';

/// One reading of what the camera is pointed at.
class LiveRecognition {
  const LiveRecognition({
    required this.equipmentId,
    required this.confidence,
    required this.agreement,
    this.settled = true,
  });

  final String equipmentId;

  /// Mean confidence of the frames that voted for [equipmentId].
  final double confidence;

  /// Share of the buffered frames that agreed, 0..1. Low agreement means
  /// the camera is still moving or the machine is ambiguous.
  final double agreement;

  /// True when the smoother's window, agreement and confidence bars are all
  /// met. A tentative (false) reading is feedback, not an answer: the UI
  /// shows it as "possibly …" and nothing records it to history. The
  /// operator's defect was a spinner with NO feedback for as long as the
  /// bars stayed unmet — which on a hard scene is forever.
  final bool settled;
}

/// Majority-vote smoother over the last N frames.
///
/// A single frame from a 62%-top-1 classifier flickers between candidates,
/// which reads as "broken" even when the model is doing its job. Requiring a
/// label to win a majority of a short window trades ~1s of latency for a
/// steady answer, and refusing to report anything below [minAgreement] is
/// what keeps a confident-but-wrong frame off the screen.
///
/// Pure and synchronous on purpose: the camera plumbing is untestable on a
/// desktop test runner, this is not.
class RecognitionSmoother {
  RecognitionSmoother({
    // 6, not 10: at the labeler's real cadence a 10-frame window meant
    // several seconds before ANY output could exist. Tentative readings
    // (see [tentative]) cover the wait either way.
    this.window = 6,
    this.minAgreement = 0.5,
    this.minConfidence = 0.30,
  })  : assert(window > 0),
        assert(minAgreement > 0 && minAgreement <= 1);

  /// How many recent frames vote.
  final int window;

  /// Fraction of the window that must agree before anything is reported.
  final double minAgreement;

  /// Mean confidence the winning label must reach.
  final double minConfidence;

  final List<VisualMatch?> _buffer = <VisualMatch?>[];

  /// Feed the top match of one frame (null when the frame matched nothing).
  /// Returns the settled reading, or null while the window is undecided.
  LiveRecognition? add(VisualMatch? top) {
    _buffer.add(top);
    if (_buffer.length > window) {
      _buffer.removeRange(0, _buffer.length - window);
    }
    if (_buffer.length < window) return null;

    final votes = <String, List<double>>{};
    for (final m in _buffer) {
      if (m == null) continue;
      votes.putIfAbsent(m.equipmentId, () => <double>[]).add(m.confidence);
    }
    if (votes.isEmpty) return null;

    var bestId = '';
    var bestVotes = <double>[];
    for (final entry in votes.entries) {
      if (entry.value.length > bestVotes.length) {
        bestId = entry.key;
        bestVotes = entry.value;
      }
    }

    final agreement = bestVotes.length / window;
    final meanConfidence =
        bestVotes.reduce((a, b) => a + b) / bestVotes.length;
    if (agreement < minAgreement || meanConfidence < minConfidence) {
      return null;
    }
    return LiveRecognition(
      equipmentId: bestId,
      confidence: meanConfidence,
      agreement: agreement,
    );
  }

  /// The current leader with no bars applied, or null when nothing in the
  /// buffer matched anything. `settled` is always false here.
  ///
  /// This is what the UI shows while [add] keeps returning null, so a hard
  /// scene degrades to "possibly: X · 23%" instead of an infinite spinner.
  LiveRecognition? get tentative {
    final votes = <String, List<double>>{};
    for (final m in _buffer) {
      if (m == null) continue;
      votes.putIfAbsent(m.equipmentId, () => <double>[]).add(m.confidence);
    }
    if (votes.isEmpty) return null;
    var bestId = '';
    var bestVotes = <double>[];
    for (final entry in votes.entries) {
      if (entry.value.length > bestVotes.length) {
        bestId = entry.key;
        bestVotes = entry.value;
      }
    }
    return LiveRecognition(
      equipmentId: bestId,
      confidence: bestVotes.reduce((a, b) => a + b) / bestVotes.length,
      agreement: bestVotes.length / window,
      settled: false,
    );
  }

  /// Forget the window — call when the user leaves the camera or a result
  /// has been acted on, so a stale label cannot leak into the next session.
  void reset() => _buffer.clear();
}
