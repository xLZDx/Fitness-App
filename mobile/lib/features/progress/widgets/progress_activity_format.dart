/// Pure formatting and ordering helpers of the Progress activity widgets
/// (S03-14, design 3.4, contract 11). Metric units only; numbers go through
/// `intl` with the resolved locale.
library;

import 'package:intl/intl.dart';

import '../../activity/data/activity_aggregates.dart';
import '../../modes/data/mode_models.dart' show AppMode;

/// Whole minutes of [seconds], at least 1 for any positive value.
int progressMinutesOf(double seconds) {
  final m = (seconds / 60).round();
  return (m == 0 && seconds > 0) ? 1 : m;
}

/// Kilometres with one decimal in [locale] followed by [unit] (the localized
/// `activityUnitKm`).
String formatProgressDistance(double metres, String locale, String unit) {
  final km = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: 1,
  ).format(metres / 1000);
  return '$km $unit';
}

/// Integer in [locale].
String formatProgressCount(int n, String locale) =>
    NumberFormat.decimalPattern(locale).format(n);

/// Short stable key suffix of a group (`progress.tile.<suffix>`).
String progressGroupKeyName(SportGroup g) => switch (g) {
      SportGroup.walkHike => 'walk',
      SportGroup.run => 'run',
      SportGroup.ride => 'ride',
      SportGroup.swim => 'swim',
      SportGroup.row => 'row',
      SportGroup.other => 'other',
    };

/// The tiles with the groups of the selected [mode] first; nothing is hidden
/// and the rest keep the fixed order (contract 8.4).
List<WeekTile> orderTilesForMode(List<WeekTile> tiles, AppMode? mode) {
  final first = switch (mode) {
    AppMode.explore => const [SportGroup.walkHike, SportGroup.run],
    AppMode.ride => const [SportGroup.ride],
    _ => const <SportGroup>[],
  };
  if (first.isEmpty) return tiles;
  return [
    for (final g in first)
      for (final t in tiles)
        if (t.group == g) t,
    for (final t in tiles)
      if (!first.contains(t.group)) t,
  ];
}

/// Columns of the tile grid: clamp(floor((available + 12) / (160 + 12)), 1, 3).
int progressTileColumns(double available) {
  final c = ((available + 12) / (160 + 12)).floor();
  return c < 1 ? 1 : (c > 3 ? 3 : c);
}
