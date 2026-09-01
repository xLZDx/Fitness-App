// G4 — the four trainer counters under the picture.
//
// The reference draws ТЕМП / АМПЛИТУДА / СИММЕТРИЯ / ПАУЗА as four numbers.
// G3 built the panel and wired every one of them to an em-dash, because a
// number invented to fill a gauge is worse than an honest blank. This file is
// what measures them, and it is deliberately pure: a [RepQuality] and a
// [RepCounterConfig] in, four readings out, no providers and no widgets. Every
// threshold it compares against is the counter's own, so the panel cannot
// disagree with the machine that produced the rep.
//
// Each reading is nullable and every null means the same thing: this was not
// measured. None of them falls back to a plausible value.

import 'rep_counter.dart';

/// What the four counters report about one completed repetition.
class CoachCounters {
  const CoachCounters({
    this.tempoSeconds,
    this.amplitude,
    this.symmetryLeftPercent,
    this.pauseSeconds,
  });

  /// Nothing measured — the state before the first rep of a set completes.
  static const none = CoachCounters();

  /// Wall time for the whole repetition, top to top.
  final double? tempoSeconds;

  /// Depth reached, 0..1, where 1 is the hips level with the knees.
  ///
  /// See [coachCountersFor] for why parallel is the denominator and why the
  /// value is capped there.
  final double? amplitude;

  /// The left leg's share of the work at the deepest point, 0..100.
  ///
  /// Null whenever the far side was not genuinely seen, which is most of a
  /// side-on set. See [squatSideDepths].
  final int? symmetryLeftPercent;

  /// How long the lifter held the bottom.
  final double? pauseSeconds;

  /// Percentage points away from an even split, or null when unmeasured.
  ///
  /// The panel colours the symmetry column off this rather than off the raw
  /// split, because 49/51 and 51/49 are the same amount of lopsided.
  int? get symmetryOffBy {
    final left = symmetryLeftPercent;
    return left == null ? null : (left - 50).abs();
  }
}

/// Everything the panel shows, computed from the last completed repetition.
///
/// **Amplitude** is measured from the standing gate ([RepCounterConfig
/// .topEnter]) to parallel — hip level with knee, which is signal 0 in
/// [squatDepthSignal]'s own convention — rather than to the depth gate the
/// counter accepts a rep at. Against the gate every counted rep would read
/// 100% by construction, since reaching it is what made the rep count, and a
/// counter that can only ever print one number is not a measurement. Parallel
/// is the target the coach's own [SquatDepthClassifier] is tuned around, so it
/// is the depth the user is actually being asked for.
///
/// Going BELOW parallel reads 100%, not more. This is a `PRODUCT_HEURISTIC`
/// and the alternative was considered: a raw 118% is arithmetically honest but
/// it says the lifter exceeded a target, when what the coach means by
/// amplitude is "did you reach the depth being asked of you". Depth beyond
/// that is a different conversation and the technique gauge is already having
/// it.
///
/// [fullAmplitudeSignal] is the signal value that counts as full depth for
/// THIS movement, and null means the caller cannot say. It is a parameter
/// rather than a constant because the reasoning above is squat reasoning:
/// parallel is a meaningful landmark in [squatDepthSignal]'s convention and
/// nothing about it carries over to a push-up's elbow angle or a sit-up's
/// trunk lean, whose extractors put full range somewhere else entirely. A
/// movement whose caller has no defensible answer gets «—» rather than a
/// percentage of the wrong thing.
CoachCounters coachCountersFor(
  RepQuality? rep, {
  RepCounterConfig config = const RepCounterConfig(),
  double? fullAmplitudeSignal,
}) {
  if (rep == null) return CoachCounters.none;

  final duration = rep.durationMs;
  // A record whose clock ran backwards, or not at all, is not a tempo. It
  // reaches here from a hand-built [RepQuality] in a test or from a frame
  // stream whose timestamps are not monotonic; either way the honest reading
  // is none.
  final tempo = duration > 0 ? duration / 1000 : null;

  // The full travel the amplitude is a fraction OF: standing gate to full
  // depth. Written as the subtraction it is, so the intent survives a change
  // to either constant.
  double? amplitude;
  if (fullAmplitudeSignal != null && rep.peakSignal.isFinite) {
    final fullTravel = fullAmplitudeSignal - config.topEnter;
    if (fullTravel > 0) {
      amplitude =
          ((rep.peakSignal - config.topEnter) / fullTravel).clamp(0.0, 1.0);
    }
  }

  final sides = rep.peakSides;
  int? symmetry;
  if (sides != null) {
    // Both sides measured from the same standing reference the amplitude uses,
    // which turns two negative depths into two positive contributions. Taking
    // the ratio of the raw signals instead would divide by a total that passes
    // through zero mid-descent, and the split would swing wildly at exactly
    // the moment it is least meaningful.
    final left = sides.left - config.topEnter;
    final right = sides.right - config.topEnter;
    final total = left + right;
    // Above the top gate on both sides, or the pair is not a split of
    // anything. A lifter standing straight up has no work to divide.
    if (left > 0 && right > 0 && total > 0) {
      symmetry = (100 * left / total).round().clamp(0, 100);
    }
  }

  final hold = rep.bottomHoldMs;
  final pause = hold >= 0 ? hold / 1000 : null;

  return CoachCounters(
    tempoSeconds: tempo,
    amplitude: amplitude,
    symmetryLeftPercent: symmetry,
    pauseSeconds: pause,
  );
}
