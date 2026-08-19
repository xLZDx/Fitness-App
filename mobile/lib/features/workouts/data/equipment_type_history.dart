import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'workout_log.dart';

/// Whether [EquipmentTypeHistorySummary.lastEntry] reflects the user's whole
/// history for this equipment type, or only the recent window the caller
/// searched.
///
/// The distinction only matters when nothing matched: "never done this
/// equipment type" and "done, but longer ago than we checked" must not
/// collapse into the same "no history" message. See
/// `core/product/GATE_D_EQUIPMENT_TYPE_HISTORY_D0_NOTE_2026-08-19.md`.
enum EquipmentHistoryCompleteness {
  /// Every logged workout the user has ever completed was searched — either
  /// a match was found, or there truly is none.
  completeHistory,

  /// No match in the searched window, but the user has older workouts this
  /// search never looked at. A "no history" claim would be false here.
  recentWindowOnly,
}

/// The last relevant workout for one equipment TYPE (e.g. `leg_press`), not
/// a specific gym or physical machine — those are out of scope for this type
/// on purpose.
///
/// Built by [summarizeEquipmentTypeHistory] from data the app already holds:
/// no equipment-type-scoped Firestore query exists or is added for this.
class EquipmentTypeHistorySummary {
  const EquipmentTypeHistorySummary._({
    required this.equipmentId,
    required this.lastEntry,
    required this.completeness,
  });

  /// A genuine match. Always `completeHistory` — a match found inside the
  /// searched window is provably the true most-recent one regardless of
  /// truncation (see [summarizeEquipmentTypeHistory]'s doc comment), so
  /// there is no combination of `lastEntry` and `completeness` for a hit
  /// left for a caller to get wrong.
  EquipmentTypeHistorySummary.found(String equipmentId, WorkoutLogEntry entry)
      : this._(
          equipmentId: equipmentId,
          lastEntry: entry,
          completeness: EquipmentHistoryCompleteness.completeHistory,
        );

  /// No match. [windowCoveredAllHistory] decides whether that miss is a
  /// confirmed "never done this" or an honest "not found in what we could
  /// check" — the one distinction this whole type exists to keep separate.
  EquipmentTypeHistorySummary.notFound(
    String equipmentId, {
    required bool windowCoveredAllHistory,
  }) : this._(
          equipmentId: equipmentId,
          lastEntry: null,
          completeness: windowCoveredAllHistory
              ? EquipmentHistoryCompleteness.completeHistory
              : EquipmentHistoryCompleteness.recentWindowOnly,
        );

  final String equipmentId;

  /// The most recent logged set for any exercise mapped to [equipmentId],
  /// or null when none was found.
  final WorkoutLogEntry? lastEntry;

  final EquipmentHistoryCompleteness completeness;

  bool get hasHistory => lastEntry != null;

  /// True only for a genuine "not found, and we checked everything" result.
  /// A truncated miss ([EquipmentHistoryCompleteness.recentWindowOnly]) is
  /// not this — the UI must phrase that case differently.
  bool get isConfirmedNoHistory =>
      lastEntry == null &&
      completeness == EquipmentHistoryCompleteness.completeHistory;
}

/// Matches [windowedHistory] against [exerciseIdsForEquipment] to find the
/// most recent workout logged for one equipment type.
///
/// [windowedHistory] is expected newest-first (the shape
/// `workoutSessionHistoryProvider` already streams) and may be capped short
/// of the user's whole history. [allTimeTotal] is the exact all-time
/// *session* count (`WorkoutLogTotals.total`, from `workoutSessionTotalsProvider`)
/// used only to tell a truncated miss from a confirmed one — it never adds a
/// query of its own; callers already fetch it for the totals figure.
///
/// [allTimeTotal] counts sessions, not rows: since R11e, one completed
/// session can produce several [WorkoutLogEntry] rows in [windowedHistory]
/// (`WorkoutSession.asLogEntries()` — one row per exercise in that session,
/// "so a 5-exercise gym visit surfaces all five"). Comparing raw row count
/// to a session total would under-count how truncated the window really is
/// whenever a session has more than one exercise, silently reporting
/// `completeHistory` for a window that is actually missing sessions —
/// exactly the false claim this type exists to prevent (Gate D review,
/// 2026-08-19). Counting distinct [WorkoutLogEntry.sessionId]s instead is
/// the same fix the codebase already applies for this exact row-vs-session
/// gap elsewhere (`WorkoutLogEntry.sessionId`'s own doc comment: counting
/// logic "must count distinct sessionIds, not rows... or it would report
/// five workouts for one visit").
///
/// Matching is exact `exerciseId` membership in [exerciseIdsForEquipment].
/// There is no name/alias/fuzzy matching here on purpose: the exercise
/// catalog already resolves free-text equipment names to a stable
/// `equipmentId` upstream (`EquipmentAliasIndex`), and this function only
/// ever sees that resolved id — matching anything looser would risk
/// attributing one equipment type's history to another.
EquipmentTypeHistorySummary summarizeEquipmentTypeHistory({
  required String equipmentId,
  required List<WorkoutLogEntry> windowedHistory,
  required Set<String> exerciseIdsForEquipment,
  required int allTimeTotal,
}) {
  WorkoutLogEntry? mostRecent;
  for (final entry in windowedHistory) {
    if (!exerciseIdsForEquipment.contains(entry.exerciseId)) continue;
    if (mostRecent == null || entry.completedAt.isAfter(mostRecent.completedAt)) {
      mostRecent = entry;
    }
  }

  // A match found inside the window is provably the true most-recent one:
  // the window is "the newest N sessions, any exercise", so nothing outside
  // it is newer than anything inside it. Only a miss needs the truncation
  // check, and that check must count sessions, not rows -- see the doc
  // comment above.
  if (mostRecent != null) {
    return EquipmentTypeHistorySummary.found(equipmentId, mostRecent);
  }
  final sessionsInWindow = windowedHistory.map((e) => e.sessionId).toSet().length;
  return EquipmentTypeHistorySummary.notFound(
    equipmentId,
    windowCoveredAllHistory: sessionsInWindow >= allTimeTotal,
  );
}

/// The weight/reps line for a last-session card, or null when neither was
/// logged (a bodyweight exercise, or the user declined to enter a number —
/// `set_capture_sheet.dart` keeps that distinct from a logged zero).
///
/// Pulled out of the widget so the three-way choice between "both",
/// "weight only" and "reps only" is unit-testable without pumping a widget
/// tree, in both shipped locales.
String? formatLastSessionMetric(
  AppLocalizations l10n, {
  required double? weightKg,
  required int? repsCompleted,
}) {
  String kg(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  if (weightKg != null && repsCompleted != null) {
    return l10n.workoutsKgReps(kg(weightKg), repsCompleted);
  }
  if (weightKg != null) return l10n.commonKilograms(kg(weightKg));
  if (repsCompleted != null) return l10n.commonReps(repsCompleted);
  return null;
}
