// Immutable value types for the data-driven coach exercise registry
// (`assets/data/coach_exercises.json`, schema `coach_exercises/v1`).
//
// Every threshold here is an angle (degrees) or a torso-length ratio, never a
// pixel distance: the registry must stay valid for any camera resolution.
// Construction and validation live in `coach_registry.dart`; these types only
// carry the already-validated result.

import 'package:flutter/foundation.dart';

import 'pose_landmark.dart';

/// Which camera view the exercise is judged from.
enum CoachView { side, front }

/// How the tracked side is chosen.
enum CoachSidePolicy {
  /// Use whichever side is better visible.
  bestVisible,

  /// Score both sides.
  both,

  /// Always the left side.
  fixedLeft,
}

enum CoachSignalKind { angle, ratio, lineDeviation }

/// Direction of the rep signal on the way INTO the active phase.
/// [falling]: enter < exit (e.g. knee angle shrinking on descent).
/// [rising]: enter > exit.
enum CoachSignalDirection { falling, rising }

enum CoachCountingMode { reps, hold, off }

enum CoachSeverity { minor, major, safety }

enum CoachProvenanceKind { measured, authored, literature }

enum CoachProvenanceStatus { beta, stable }

@immutable
class CoachPhase {
  const CoachPhase({required this.name, required this.entry});
  final String name;

  /// Human-readable entry condition (documentation; not interpreted).
  final String entry;
}

@immutable
class CoachSignal {
  const CoachSignal({
    required this.kind,
    required this.joints,
    required this.direction,
    required this.enter,
    required this.exit,
    this.normalizeTorso = false,
  });

  final CoachSignalKind kind;

  /// Validated landmark names (exact [LandmarkType] names, or a side-neutral
  /// stem such as `knee` that resolves per the side policy).
  final List<String> joints;
  final CoachSignalDirection direction;

  /// Threshold that enters the active phase (degrees or torso ratio).
  final double enter;

  /// Threshold that leaves it again; hysteresis partner of [enter].
  final double exit;

  /// True when the value is divided by torso length (`normalizeBy: torso`).
  final bool normalizeTorso;
}

@immutable
class CoachCounting {
  const CoachCounting({required this.mode, this.minHoldMs});
  final CoachCountingMode mode;
  final int? minHoldMs;
}

@immutable
class CoachRule {
  const CoachRule({
    required this.id,
    required this.metric,
    required this.tolerance,
    required this.phase,
    required this.severity,
    required this.cueId,
    required this.advisory,
    this.min,
    this.max,
  });

  final String id;
  final String metric;
  final double? min;
  final double? max;
  final double tolerance;

  /// Name of a phase declared by the owning [CoachSpec].
  final String phase;
  final CoachSeverity severity;

  /// Key resolved against the cue-text catalogue (see `validateCueIds`).
  final String cueId;

  /// Advisory rules may be shown but never gate a rep or a score.
  final bool advisory;
}

@immutable
class CoachProvenance {
  const CoachProvenance({
    required this.kind,
    required this.source,
    required this.status,
  });
  final CoachProvenanceKind kind;
  final String source;
  final CoachProvenanceStatus status;
}

@immutable
class CoachSpec {
  const CoachSpec({
    required this.id,
    required this.aliases,
    required this.version,
    required this.view,
    required this.sidePolicy,
    required this.tracked,
    required this.unscored,
    required this.phases,
    required this.signal,
    required this.counting,
    required this.rules,
    required this.safetyWording,
    required this.provenance,
  });

  final String id;

  /// Catalog pose tags (e.g. `hinge`) that route to this spec.
  final List<String> aliases;
  final int version;
  final CoachView view;
  final CoachSidePolicy sidePolicy;
  final List<String> tracked;
  final List<String> unscored;
  final List<CoachPhase> phases;
  final CoachSignal signal;
  final CoachCounting counting;
  final List<CoachRule> rules;

  /// True when cue wording touches injury/safety and needs the safety review.
  final bool safetyWording;
  final CoachProvenance provenance;
}

/// Resolves a registry landmark name to concrete [LandmarkType]s, or null when
/// it is unknown. Accepts an exact enum name (`leftKnee`) or a side-neutral
/// stem (`knee`) for which both `left<Stem>` and `right<Stem>` exist.
List<LandmarkType>? resolveCoachLandmark(String name) {
  for (final t in LandmarkType.values) {
    if (t.name == name) return [t];
  }
  if (name.isEmpty) return null;
  final stem = name[0].toUpperCase() + name.substring(1);
  final l = LandmarkType.values.where((t) => t.name == 'left$stem');
  final r = LandmarkType.values.where((t) => t.name == 'right$stem');
  if (l.isNotEmpty && r.isNotEmpty) return [l.first, r.first];
  return null;
}
