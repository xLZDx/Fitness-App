// Data-driven [FormClassifier] built from one registry row ([CoachSpec]).
//
// Phase convention: a spec with one phase applies every rule always; with
// several, the FIRST declared phase is the rest state, the LAST is the active
// state (signal past `enter`, until it crosses `exit`), and any middle phase
// applies in both. A rule violates when its metric is outside [min, max] by
// more than `tolerance`.
//
// Advisory (or beta-provenance) rules always yield severity 0 and
// `FormFeedback.advisory = true`: on-screen only, never spoken, never a rep
// fault. `canFault` is true only when a rule is entitled to fault.

import 'coach_signal.dart';
import 'coach_spec.dart';
import 'form_classifier.dart';
import 'pose_gate.dart';
import 'pose_landmark.dart';

class GenericRuleClassifier implements FormClassifier, FrameSelectingClassifier {
  GenericRuleClassifier(
    this.spec, {
    this.gateConfig = const PoseGateConfig(),
  })  : _band = CoachSignalBand(spec.signal),
        _metrics = {
          for (final r in spec.rules) r.id: CoachMetric.parse(r.metric, spec),
        },
        _required = coachRequiredLandmarks(spec);

  final CoachSpec spec;
  final PoseGateConfig gateConfig;
  final CoachSignalBand _band;
  final Map<String, CoachMetric?> _metrics;
  final Set<LandmarkType> _required;
  double? _driftBaseline;

  bool _entitled(CoachRule r) =>
      !r.advisory && spec.provenance.status == CoachProvenanceStatus.stable;

  @override
  String get rule => spec.id;

  @override
  Set<LandmarkType> get requiredLandmarks => _required;

  @override
  bool get canFault => spec.rules.any(_entitled);

  @override
  LandmarkType? get faultVertex => null;

  @override
  PoseFrame frameFor(PoseFrame raw) => coachFrameFor(spec, raw);

  /// Forget the per-set baseline (torso drift) and the phase state.
  void reset() {
    _band.reset();
    _driftBaseline = null;
  }

  bool _applies(CoachRule r, bool active) {
    if (spec.phases.length < 2) return true;
    if (r.phase == spec.phases.first.name) return !active;
    if (r.phase == spec.phases.last.name) return active;
    return true;
  }

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final view = coachFrameFor(spec, frame);
    if (!gatePose(view, _required, config: gateConfig).isScorable) return null;
    final minL = gateConfig.minLikelihood;
    final sides = spec.sidePolicy == CoachSidePolicy.both ? const [0, 1] : const [0];

    final signal = coachSignalValue(spec, view, minLikelihood: minL);
    final active = _band.update(signal);

    FormFeedback? worst;
    for (final r in spec.rules) {
      if (!_applies(r, active)) continue;
      final m = _metrics[r.id];
      if (m == null) continue;
      for (final side in sides) {
        double? v;
        if (m.isDrift) {
          final lean = coachTorsoLeanDeg(view, side, minL);
          if (lean == null) continue;
          _driftBaseline ??= lean;
          v = coachMetricValue(spec, m, view,
              side: side, minLikelihood: minL, driftBaseline: _driftBaseline);
        } else {
          v = coachMetricValue(spec, m, view, side: side, minLikelihood: minL);
        }
        if (v == null) continue;
        final lo = r.min, hi = r.max;
        final bad = (lo != null && v < lo - r.tolerance) ||
            (hi != null && v > hi + r.tolerance);
        if (!bad) continue;
        final entitled = _entitled(r);
        final severity = !entitled
            ? 0
            : r.severity == CoachSeverity.minor
                ? 1
                : 2;
        if (worst == null || severity > worst.severity) {
          worst = FormFeedback(
            rule: rule,
            severity: severity,
            cueKey: FormCueKey.registry,
            cueId: r.cueId,
            metric: v,
            advisory: !entitled,
          );
        }
      }
    }
    return worst;
  }
}
