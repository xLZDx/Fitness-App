/// In-app "moments" — one-shot celebration / nurture prompts shown at
/// specific user-journey milestones. Each moment has a stable id; once
/// shown it's recorded in the user's local prefs so it never repeats.
enum MomentId {
  /// Day-3 welcome modal. Fires on the user's third active session
  /// (anywhere in the app) once the account is at least 48h old.
  day3Welcome,

  /// First time the user actively uses the injury-aware exercise filter.
  /// Celebrates the moat feature + soft-asks for a donation.
  firstInjuryFilter,
}

/// Pure decision: should we show a moment given (a) account age,
/// (b) launch count, (c) whether the moment has already fired?
///
/// Kept pure so it's testable without a widget tree.
bool shouldShowDay3Welcome({
  required DateTime accountCreatedAt,
  required int launchCount,
  required bool alreadyShown,
  DateTime? now,
}) {
  if (alreadyShown) return false;
  final t = now ?? DateTime.now();
  final age = t.difference(accountCreatedAt);
  // Guard rails: must be >= 48h old AND >= 3 launches. Either alone
  // would fire too eagerly (very fresh user power-tapping the app, or
  // someone who left it untouched for a week).
  return age >= const Duration(hours: 48) && launchCount >= 3;
}

bool shouldShowFirstInjuryFilter({
  required int filterUsesCount,
  required bool alreadyShown,
}) {
  if (alreadyShown) return false;
  return filterUsesCount >= 1;
}
