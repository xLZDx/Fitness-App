/// MK.2 — Goal-photo → personalised program.
///
/// User uploads (or takes) a photo of their goal physique. A vision
/// model extracts a coarse target body-composition profile + sport
/// archetype. We turn that into:
///   - a 12-week training template (uses existing exercise library)
///   - a calorie / macro starting point (uses harris-benedict, not LLM)
///   - a non-judgemental "this is realistic in X months" framing
///
/// MVP makes the request shape concrete. The actual vision pass goes
/// through a Cloud Function that calls the Anthropic Claude vision API
/// (server-side, never client) so the API key never ships in the app.
class GoalPhotoRequest {
  const GoalPhotoRequest({
    required this.uid,
    required this.imageStoragePath,
    required this.userHeightCm,
    required this.userWeightKg,
    required this.userAgeYears,
    required this.userIsMale,
    this.timeHorizonMonths = 12,
    this.notes,
  });

  final String uid;
  final String imageStoragePath;
  final double userHeightCm;
  final double userWeightKg;
  final int userAgeYears;
  final bool userIsMale;
  final int timeHorizonMonths;
  final String? notes;
}

class GoalPhotoResult {
  const GoalPhotoResult({
    required this.archetype,
    required this.targetBodyFatPercentRange,
    required this.programmeTemplateId,
    required this.calorieTargetKcal,
    required this.realismMonths,
    required this.framing,
  });

  /// e.g. "lean middle-distance runner", "bodybuilder lean".
  final String archetype;

  final ({double low, double high}) targetBodyFatPercentRange;
  final String programmeTemplateId;
  final int calorieTargetKcal;

  /// Honest estimate (in months) at which the goal is realistic. May be
  /// larger than `timeHorizonMonths` — we deliberately show the user
  /// this if their target is unrealistic.
  final int realismMonths;

  /// Two-sentence narrative that softens any timeline gap. Authored by
  /// the LLM but constrained by a system prompt that bans body shaming.
  final String framing;
}
