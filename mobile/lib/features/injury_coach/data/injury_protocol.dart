/// TX.1 — Injury Recovery Coach.
///
/// A protocol is a multi-week, day-by-day rehab plan tagged to one or
/// more injuries the user has logged. Each day prescribes safe
/// alternatives that pass the existing injury-aware exercise filter.
///
/// MVP keeps protocol authoring offline (asset JSON) so a DPT board
/// member can author + version-control protocols without a writable
/// admin console. Phase 2 moves to Firestore so updates ship without
/// an app release.
class InjuryProtocol {
  const InjuryProtocol({
    required this.id,
    required this.title,
    required this.targetInjuries,
    required this.summary,
    required this.weeks,
    required this.reviewedBy,
    this.contraindicationsAdded = const [],
  });

  /// Stable id. Use kebab-case (e.g. `low-back-strain-acute`).
  final String id;

  /// Display name, sentence-cased.
  final String title;

  /// Injury tags this protocol applies to (matches the canonical injury
  /// taxonomy used by `exercise_filter.dart`).
  final List<String> targetInjuries;

  /// One-paragraph summary the user reads on the protocol-detail page.
  final String summary;

  /// Ordered weeks of programming. Each week has 7 days.
  final List<InjuryProtocolWeek> weeks;

  /// Credit line shown beneath the protocol ("Reviewed by Dr. X, DPT").
  /// `community` placeholder while we recruit DPT board members.
  final String reviewedBy;

  /// Extra contraindications the protocol forces on top of the user's
  /// reported list while it's active. Cleared when the protocol ends.
  final List<String> contraindicationsAdded;
}

class InjuryProtocolWeek {
  const InjuryProtocolWeek({
    required this.weekNumber,
    required this.days,
    this.intentLine,
  });

  final int weekNumber;
  final List<InjuryProtocolDay> days;

  /// Optional thematic line ("Week 2 — restore range of motion").
  final String? intentLine;
}

class InjuryProtocolDay {
  const InjuryProtocolDay({
    required this.dayNumber,
    required this.exerciseIds,
    this.restDay = false,
    this.note,
  });

  final int dayNumber;
  final List<String> exerciseIds;
  final bool restDay;
  final String? note;
}
