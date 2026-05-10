import '../../equipment/data/equipment_models.dart';

/// Generated workout plan — one day's worth of training.
class GeneratedPlan {
  const GeneratedPlan({
    required this.title,
    required this.estimatedMinutes,
    required this.exercises,
    required this.intensityFactor,
    required this.rationale,
  });

  final String title;
  final int estimatedMinutes;
  final List<ExerciseItem> exercises;

  /// Effective intensity vs baseline (0.5..1.1). Lower when recovery
  /// signals (deload, cycle phase, low compliance) suggest it.
  final double intensityFactor;

  /// Why this plan was selected (read out by the page so users trust it).
  final String rationale;
}
