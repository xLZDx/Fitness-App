/// MK.3 — Cycle-Aware Programming for Women.
///
/// 4-phase model (Menstrual / Follicular / Ovulatory / Luteal). Pure;
/// no PHI persisted in this layer — the user's logged cycle goes to
/// E2E-encrypted storage similar to progress photos.
enum CyclePhase { menstrual, follicular, ovulatory, luteal }

/// Pure phase resolver. Day 1 = first day of menstruation.
/// Standard 28-day model with calculated mid-cycle ovulation.
CyclePhase phaseFor({required int cycleDay, int cycleLength = 28}) {
  if (cycleDay < 1) return CyclePhase.luteal;
  if (cycleDay <= 5) return CyclePhase.menstrual;
  // Follicular = days 6 → ovulation-2.
  final ovulation = (cycleLength / 2).round();
  if (cycleDay < ovulation - 1) return CyclePhase.follicular;
  if (cycleDay <= ovulation + 1) return CyclePhase.ovulatory;
  return CyclePhase.luteal;
}

/// Programming hint for a given phase. The app surfaces this as a soft
/// suggestion ("You're in luteal — want to substitute today's heavy
/// squats for tempo squats?"); never imposes.
class PhaseHint {
  const PhaseHint({
    required this.phase,
    required this.headline,
    required this.intensityFactor,
    required this.preferredTags,
    required this.deprioritisedTags,
  });

  final CyclePhase phase;
  final String headline;

  /// Multiplier on the prescribed working weight. 1.0 = no change.
  final double intensityFactor;

  /// Exercise category tags to *upweight* in the For-You feed.
  final List<String> preferredTags;

  /// Categories to downweight. Soft filter — never hides them outright.
  final List<String> deprioritisedTags;
}

PhaseHint hintFor(CyclePhase p) {
  switch (p) {
    case CyclePhase.menstrual:
      return const PhaseHint(
        phase: CyclePhase.menstrual,
        headline: 'Listen to your body. Light movement only if you feel up to it.',
        intensityFactor: 0.7,
        preferredTags: ['mobility', 'walk', 'yoga'],
        deprioritisedTags: ['hiit', 'max_strength'],
      );
    case CyclePhase.follicular:
      return const PhaseHint(
        phase: CyclePhase.follicular,
        headline: 'Strength + speed window. Push the heavy days now.',
        intensityFactor: 1.05,
        preferredTags: ['max_strength', 'power'],
        deprioritisedTags: ['steady_state'],
      );
    case CyclePhase.ovulatory:
      return const PhaseHint(
        phase: CyclePhase.ovulatory,
        headline: 'Peak performance day. PR attempts welcome.',
        intensityFactor: 1.10,
        preferredTags: ['max_strength', 'sprints'],
        deprioritisedTags: [],
      );
    case CyclePhase.luteal:
      return const PhaseHint(
        phase: CyclePhase.luteal,
        headline: 'Tempo + technique focus. Pull volume back ~10–15%.',
        intensityFactor: 0.90,
        preferredTags: ['tempo', 'mobility', 'zone2'],
        deprioritisedTags: ['max_strength'],
      );
  }
}
