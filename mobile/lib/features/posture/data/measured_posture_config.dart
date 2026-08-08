/// R10 — measured typical-range posture data.
///
/// Every number below came out of `scripts/pose/extract_mmfit_posture.py`
/// run against MM-Fit (Stromback, Huang, Radu -- IMWUT 2020, CC BY 4.0):
/// 9,070 frames from the "standing between reps" phase of 124 squat/lunge
/// sets. None is a guess.
///
/// **What these numbers are NOT**: a clinical posture-assessment reference.
/// MM-Fit contains no "stand neutrally for a posture check" scenario at all
/// -- the proxy used is "the moment a lifter is standing between reps of an
/// unrelated exercise," which is incidental, not deliberate, posture. See
/// `core/plans/PLAN_R10_POSTURE_2026-08-08.md` sections 2-3 for the full
/// reasoning. Read that before tightening any band below on the assumption
/// the underlying measurement is more precise than it is.
///
/// Each metric carries P05/P25/median/P75/P95 rather than a single "normal"
/// number, because the spread IS the finding: `forwardHead`'s interquartile
/// range is nearly twice as wide, relative to its median, as the other two
/// -- a real difference in how noisy this proxy is per metric, not
/// something to average away.
class MeasuredPostureRange {
  const MeasuredPostureRange({
    required this.p05,
    required this.p25,
    required this.median,
    required this.p75,
    required this.p95,
  });

  final double p05;
  final double p25;
  final double median;
  final double p75;
  final double p95;

  /// Three-tier read: inside the interquartile band is "typical"; between
  /// that and the 5th/95th percentile is "mild"; beyond p05/p95 is
  /// "notable". Never "normal" vs "abnormal" -- this is a population
  /// spread from an incidental proxy, not a clinical cutoff, and the
  /// verdict names must not overclaim what the number behind them is.
  PostureVerdict verdictFor(double value) {
    if (value >= p25 && value <= p75) return PostureVerdict.typical;
    if (value >= p05 && value <= p95) return PostureVerdict.mild;
    return PostureVerdict.notable;
  }
}

enum PostureVerdict { typical, mild, notable }

/// Positive [MeasuredPostureRange.median] means the right side sits HIGHER
/// than the left, per the extraction script's confirmed axis convention
/// (`extract_mmfit_posture.py`'s `posture_metrics` docstring) -- not lower.
/// Get this backwards and every "right shoulder low" cue in the UI would be
/// pointing at the wrong shoulder.
const shoulderAsymmetryRange = MeasuredPostureRange(
  p05: -0.0285,
  p25: 0.0256,
  median: 0.0765,
  p75: 0.1164,
  p95: 0.1963,
);

/// Same sign convention as [shoulderAsymmetryRange]: positive = right hip
/// higher.
const pelvisTiltRange = MeasuredPostureRange(
  p05: -0.0337,
  p25: 0.0240,
  median: 0.0675,
  p75: 0.1015,
  p95: 0.1924,
);

/// Positive = head sits forward of the shoulder midpoint, on whichever
/// horizontal axis the extraction script found had the larger pooled
/// spread across the whole dataset (axis 0; see the script's `--out` JSON,
/// field `forward_axis`). The widest, least trustworthy of the three
/// bands -- see the class doc.
const forwardHeadRange = MeasuredPostureRange(
  p05: -0.1871,
  p25: 0.0129,
  median: 0.1975,
  p75: 0.4029,
  p95: 0.5043,
);
