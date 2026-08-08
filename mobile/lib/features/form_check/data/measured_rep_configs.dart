import 'dart:math' as math;

import 'pose_landmark.dart';
import 'rep_counter.dart';

/// Measured tuning for [RepCounter], one entry per movement.
///
/// Every number came out of `scripts/pose/extract_mmfit_targets.py` run against
/// MM-Fit (Stromback, Huang, Radu -- IMWUT 2020, CC BY 4.0): 6,160 labelled
/// repetitions across 21 sessions. None is a guess. That distinction is the
/// point of the file -- on 2026-08-08 five thresholds in this app were checked
/// against data for the first time and four of them were wrong.
///
/// This does not replace [RepCounterConfig] or [squatDepthSignal]. The squat
/// already had a working signal in frame-height units and keeps it; what is
/// added here is a joint-angle signal for the movements that had no signal at
/// all, plus the measured thresholds to drive them.
class MeasuredRepConfig {
  const MeasuredRepConfig({
    required this.tag,
    required this.driver,
    required this.bottomDeg,
    required this.bottomP25,
    required this.bottomP75,
    required this.topDeg,
    required this.enterBelowDeg,
    required this.exitAboveDeg,
    required this.holdoutExactRate,
    required this.sets,
    required this.reps,
  });

  /// Key into `poseTargetsByTag`.
  final String tag;

  /// Joint triple whose angle drives one repetition, as (a, vertex, c).
  final (LandmarkType, LandmarkType, LandmarkType) driver;

  /// Median driver angle at the bottom of a rep, degrees.
  final double bottomDeg;

  /// Interquartile spread of the per-set bottom. A wide band means people do
  /// this movement to very different depths, which is a reason to be careful
  /// about calling any particular depth wrong.
  final double bottomP25;
  final double bottomP75;

  /// Median driver angle at the top of a rep, degrees.
  final double topDeg;

  /// Rep boundary: a descent below [enterBelowDeg] followed by a return above
  /// [exitAboveDeg]. Two thresholds because one line double-counts every time
  /// the signal jitters across it at the bottom.
  final double enterBelowDeg;
  final double exitAboveDeg;

  /// Exact-match rate against MM-Fit's own rep counts, on sessions the
  /// threshold sweep never saw.
  ///
  /// Only the holdout number is stored. In-sample there is nowhere to put:
  /// push-ups scored 74% on the sessions they were fitted to and 29% on
  /// held-out ones -- worse than the 45% the un-swept guess managed. Keeping
  /// the flattering number anywhere in this file would invite someone to quote
  /// it.
  final double holdoutExactRate;

  final int sets;
  final int reps;

  /// Whether the rep counter ships for this movement.
  ///
  /// The bar is 80% exact on held-out sessions. Below it the counter is worse
  /// than absent: a user watching the number disagree with their own count
  /// stops trusting the coach entirely, and the coach has nothing else to
  /// offer them. Movements under the bar keep their reference angles, which
  /// are measured independently of segmentation and stay usable for cues.
  bool get countsReps => holdoutExactRate >= 0.80;

  /// Thresholds translated into [RepCounter]'s sign convention.
  ///
  /// The machine expects a signal that RISES as the lifter descends -- that is
  /// how [squatDepthSignal] behaves, because image y grows downward. A joint
  /// angle does the opposite: it shrinks as the joint closes. So the signal is
  /// the negated angle, and every threshold is negated with it. Getting this
  /// backwards would not throw; it would silently count the top of each rep as
  /// the bottom, which is why the ladder assertion below exists.
  RepCounterConfig toConfig() {
    final config = RepCounterConfig(
      topEnter: -topDeg,
      topExit: -exitAboveDeg,
      bottomExit: -exitAboveDeg + 0.001,
      bottomEnter: -enterBelowDeg,
      minRepDurationMs: 600,
    );
    assert(
      config.isOrdered,
      'measured thresholds for $tag do not form a rising ladder after '
      'negation: top=$topDeg exit=$exitAboveDeg enter=$enterBelowDeg',
    );
    return config;
  }

  /// A [RepSignalExtractor] over this movement's driver joints.
  RepSignalExtractor get signal => (PoseFrame frame, double minLikelihood) {
        final (a, b, c) = driver;
        final pa = frame.landmarks[a];
        final pb = frame.landmarks[b];
        final pc = frame.landmarks[c];
        if (pa == null || pb == null || pc == null) return null;
        if (pa.likelihood < minLikelihood ||
            pb.likelihood < minLikelihood ||
            pc.likelihood < minLikelihood) {
          return null;
        }
        return -jointAngleDeg(pa, pb, pc);
      };
}

/// Angle at [b] in the a-b-c chain, degrees, in image space.
double jointAngleDeg(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final bax = a.x - b.x;
  final bay = a.y - b.y;
  final bcx = c.x - b.x;
  final bcy = c.y - b.y;
  final denom =
      math.sqrt(bax * bax + bay * bay) * math.sqrt(bcx * bcx + bcy * bcy);
  if (denom == 0) return 0;
  final cos = ((bax * bcx) + (bay * bcy)) / denom;
  return math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Measured configuration per movement tag.
///
/// Six of the app's seven tags. `hinge` is absent because MM-Fit has no
/// deadlift: its `dumbbell_rows` is a different movement in a similar
/// position, and substituting it would put a number here that was never
/// measured for the thing it claims to describe.
const measuredRepConfigs = <String, MeasuredRepConfig>{
  'squat': MeasuredRepConfig(
    tag: 'squat',
    driver:
        (LandmarkType.leftHip, LandmarkType.leftKnee, LandmarkType.leftAnkle),
    bottomDeg: 94.8,
    bottomP25: 70.5,
    bottomP75: 97.9,
    topDeg: 172.0,
    enterBelowDeg: 115,
    exitAboveDeg: 130,
    holdoutExactRate: 1.00,
    sets: 62,
    reps: 619,
  ),
  'curl': MeasuredRepConfig(
    tag: 'curl',
    driver: (
      LandmarkType.leftShoulder,
      LandmarkType.leftElbow,
      LandmarkType.leftWrist
    ),
    bottomDeg: 93.3,
    bottomP25: 90.8,
    bottomP75: 94.7,
    topDeg: 146.0,
    enterBelowDeg: 110,
    exitAboveDeg: 115,
    holdoutExactRate: 0.93,
    sets: 59,
    reps: 599,
  ),
  'overhead_press': MeasuredRepConfig(
    tag: 'overhead_press',
    driver: (
      LandmarkType.leftShoulder,
      LandmarkType.leftElbow,
      LandmarkType.leftWrist
    ),
    bottomDeg: 73.3,
    bottomP25: 68.4,
    bottomP75: 75.8,
    topDeg: 120.6,
    enterBelowDeg: 95,
    exitAboveDeg: 105,
    holdoutExactRate: 0.93,
    sets: 60,
    reps: 598,
  ),
  'lunge': MeasuredRepConfig(
    tag: 'lunge',
    driver:
        (LandmarkType.leftHip, LandmarkType.leftKnee, LandmarkType.leftAnkle),
    bottomDeg: 97.4,
    bottomP25: 89.2,
    bottomP75: 108.1,
    topDeg: 171.5,
    enterBelowDeg: 125,
    exitAboveDeg: 130,
    holdoutExactRate: 0.84,
    sets: 62,
    reps: 624,
  ),
  // Below the bar. Kept, with the failing number attached, because deleting
  // them would lose the measurement and invite someone to guess a threshold
  // here again in six months.
  'situp': MeasuredRepConfig(
    tag: 'situp',
    driver: (
      LandmarkType.leftShoulder,
      LandmarkType.leftHip,
      LandmarkType.leftKnee
    ),
    bottomDeg: 53.9,
    bottomP25: 50.1,
    bottomP75: 57.5,
    topDeg: 142.5,
    enterBelowDeg: 90,
    exitAboveDeg: 125,
    holdoutExactRate: 0.41,
    sets: 65,
    reps: 640,
  ),
  'pushup': MeasuredRepConfig(
    tag: 'pushup',
    driver: (
      LandmarkType.leftShoulder,
      LandmarkType.leftElbow,
      LandmarkType.leftWrist
    ),
    bottomDeg: 96.6,
    bottomP25: 78.2,
    bottomP75: 113.1,
    topDeg: 157.7,
    enterBelowDeg: 125,
    exitAboveDeg: 135,
    holdoutExactRate: 0.29,
    sets: 65,
    reps: 649,
  ),
};

/// Tags whose rep counter is accurate enough to show a number for.
Iterable<String> get countableTags => measuredRepConfigs.entries
    .where((e) => e.value.countsReps)
    .map((e) => e.key);

/// A counter tuned for [tag], or null when the movement has no measured
/// configuration or did not clear the accuracy bar.
///
/// Returning null rather than a counter with guessed thresholds is the whole
/// contract: a caller that gets null shows no number, which is the honest
/// outcome for push-ups and sit-ups.
RepCounter? counterFor(String tag) {
  final measured = measuredRepConfigs[tag];
  if (measured == null || !measured.countsReps) return null;
  return RepCounter(config: measured.toConfig(), signal: measured.signal);
}
