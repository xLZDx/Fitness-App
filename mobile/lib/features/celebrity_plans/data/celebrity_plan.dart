/// Curated, celebrity-led video plan. Each plan has a coach (contributing
/// in kind), a 4–8-week structure, and a list of per-day workouts.
/// Premium-tier feature.
///
/// The pointer to `NONPROFIT_PLAN.md` that used to sit here is gone: no
/// such file exists anywhere in the repo, and S0b established there is no
/// nonprofit for it to describe.
class CelebrityPlan {
  const CelebrityPlan({
    required this.id,
    required this.title,
    required this.coachName,
    required this.coachBio,
    required this.weeks,
    required this.heroImageUrl,
    required this.equipmentNeeded,
    required this.dailyWorkouts,
    this.isInKindDonation = true,
    this.isSample = false,
  });

  final String id;
  final String title;
  final String coachName;
  final String coachBio;
  final int weeks;
  final String heroImageUrl;
  final List<String> equipmentNeeded;

  /// Day index (0-based, runs 0..weeks*7-1) → exerciseId list.
  final Map<int, List<String>> dailyWorkouts;

  final bool isInKindDonation;

  /// True for the built-in placeholder plans — invented coaches with
  /// invented credentials, shipped so the screen has something to render
  /// before real donated plans exist. The UI labels these visibly: a
  /// fabricated "US-certified strength coach" that reads as genuine is
  /// worse than an obviously-empty screen, and that risk gets HIGHER, not
  /// lower, once the text is translated into the reader's own language.
  final bool isSample;
}
