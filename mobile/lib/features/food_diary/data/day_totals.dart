/// Per-day totals against the plan, and per-meal targets (design s17.7,
/// s17.8, D-39a, D-29, FOOD-18, FOOD-19). Pure Dart.
///
/// Wording rules live in the UI; this file only produces neutral numbers and
/// a three-way status. No exercise credit enters any figure (D-29).
library;

import 'food_entry.dart';

/// Where the day's mid kcal sits relative to the plan range.
enum KcalStatus { below, within, above }

/// The plan figures the diary compares against.
class DayTargets {
  const DayTargets({
    required this.kcalLow,
    required this.kcalTarget,
    required this.kcalHigh,
    this.proteinMinG,
  });

  final double kcalLow;
  final double kcalTarget;
  final double kcalHigh;

  /// Protein minimum in grams; null hides the "minimum reached" tick.
  final double? proteinMinG;
}

/// Result of [computeDayTotals].
class DayTotals {
  const DayTotals({
    required this.totals,
    required this.status,
    required this.belowRangeBy,
    required this.remainingKcal,
    required this.proteinMinimumReached,
  });

  final MacroTotals totals;

  /// `mid` against `[kcalLow, kcalHigh]`, both bounds inclusive.
  final KcalStatus status;

  /// `max(0, kcalLow - mid)` (D-39a). During the current day the UI shows it
  /// only as "to reach the lower end of your range"; a closed past day may
  /// say "below range".
  final double belowRangeBy;

  /// `max(0, kcalHigh - mid)`: room left to the TOP of the range. Secondary
  /// text, never a countdown.
  final double remainingKcal;

  /// True when protein mid is at or above the minimum (exactly equal counts).
  final bool proteinMinimumReached;
}

/// Day total from entry totals: `mid = sum(mid)`, spreads by RSS.
DayTotals computeDayTotals(Iterable<MacroTotals> entries, DayTargets targets) {
  final totals = MacroTotals.combine(entries);
  final mid = totals.kcal.mid;
  final status = mid < targets.kcalLow
      ? KcalStatus.below
      : mid > targets.kcalHigh
          ? KcalStatus.above
          : KcalStatus.within;
  final below = targets.kcalLow - mid;
  final room = targets.kcalHigh - mid;
  final min = targets.proteinMinG;
  return DayTotals(
    totals: totals,
    status: status,
    belowRangeBy: below > 0 ? below : 0,
    remainingKcal: room > 0 ? room : 0,
    proteinMinimumReached: min != null && totals.proteinG.mid >= min,
  );
}

/// Fixed shares of the day for [mealsPerDay] eating occasions (design s17.7,
/// [OWN]); the list always sums to 1.0.
///
/// 1 meal: 100 %; 2 meals: 50/50; 3 meals: 30/35/35 (breakfast, lunch,
/// dinner). With snacks (4+): each snack takes 10 % (at most 40 % in total)
/// and the three main meals keep 30/35/35 of the remainder, so the remainder
/// is spread evenly across snacks. Order: breakfast, lunch, dinner, then
/// snacks.
List<double> mealShares(int mealsPerDay) {
  final n = mealsPerDay < 1 ? 1 : mealsPerDay;
  if (n == 1) return const [1.0];
  if (n == 2) return const [0.5, 0.5];
  const mains = [0.30, 0.35, 0.35];
  if (n == 3) return mains;
  final snacks = n - 3;
  final snackEach = snacks * 0.10 > 0.40 ? 0.40 / snacks : 0.10;
  final mainPool = 1.0 - snackEach * snacks;
  return [
    for (final m in mains) m * mainPool,
    for (var i = 0; i < snacks; i++) snackEach,
  ];
}

/// Per-meal kcal targets as ranges: each share of the plan's low/target/high.
List<MacroRange> mealKcalTargets(int mealsPerDay, DayTargets targets) => [
      for (final s in mealShares(mealsPerDay))
        MacroRange(
          targets.kcalLow * s,
          targets.kcalTarget * s,
          targets.kcalHigh * s,
        ),
    ];
