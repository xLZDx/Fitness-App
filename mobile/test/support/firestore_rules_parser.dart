// Parses the `activities` summary shape out of `firestore.rules` (the source of
// truth of what the server accepts). Test-only; used by U06 (parity) and U38
// (the writer never produces a summary the rules refuse).
import 'dart:io';

import 's02_paths.dart';

class RulesBound {
  const RulesBound(this.min, this.max);
  final num min;
  final num max;
  @override
  String toString() => '[$min..$max]';
  @override
  bool operator ==(Object other) =>
      other is RulesBound && other.min == min && other.max == max;
  @override
  int get hashCode => Object.hash(min, max);
}

class ActivityRulesShape {
  ActivityRulesShape({
    required this.allowedKeys,
    required this.requiredKeys,
    required this.numberBounds,
    required this.intBounds,
    required this.stringPatterns,
    required this.sourceKinds,
  });

  /// The `hasOnly` list.
  final List<String> allowedKeys;

  /// The `hasAll` list.
  final List<String> requiredKeys;

  /// Keys checked with `actNumOk` (number, may be fractional).
  final Map<String, RulesBound> numberBounds;

  /// Keys checked with `actIntOk` plus `numberIn` on `schema` / `rev`.
  final Map<String, RulesBound> intBounds;

  /// Keys checked with `actStrOk` and their regex source.
  final Map<String, String> stringPatterns;

  /// The `primarySourceKind` membership list.
  final List<String> sourceKinds;
}

String readRulesText() => repoFile('firestore.rules').readAsStringSync();

List<String> _quotedList(String inner) => [
      for (final m in RegExp(r"'([^']+)'").allMatches(inner)) m.group(1)!,
    ];

ActivityRulesShape parseActivityRules([String? text]) {
  final src = text ?? readRulesText();
  final fn = src.indexOf('function activitySummaryOk');
  if (fn < 0) throw StateError('activitySummaryOk not found in firestore.rules');
  final body = src.substring(fn);
  final only = RegExp(r'hasOnly\(\[(.*?)\]\)', dotAll: true).firstMatch(body);
  final all = RegExp(r'hasAll\(\[(.*?)\]\)', dotAll: true).firstMatch(body);
  if (only == null || all == null) {
    throw StateError('hasOnly / hasAll list not found');
  }
  final numberBounds = <String, RulesBound>{};
  for (final m in RegExp(r"actNumOk\(d, '(\w+)', (-?[\d.]+), (-?[\d.]+)\)")
      .allMatches(src)) {
    numberBounds[m.group(1)!] =
        RulesBound(num.parse(m.group(2)!), num.parse(m.group(3)!));
  }
  final intBounds = <String, RulesBound>{};
  for (final m in RegExp(r"actIntOk\(d, '(\w+)', (-?\d+), (-?\d+)\)")
      .allMatches(src)) {
    intBounds[m.group(1)!] =
        RulesBound(int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  for (final m in RegExp(r'numberIn\(d\.(schema|rev), (\d+), (\d+)\)')
      .allMatches(body)) {
    intBounds[m.group(1)!] =
        RulesBound(int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  final strings = <String, String>{};
  for (final m
      in RegExp(r"actStrOk\(d, '(\w+)', '([^']+)'\)").allMatches(src)) {
    strings[m.group(1)!] = m.group(2)!;
  }
  final kinds = RegExp(r"primarySourceKind in \[(.*?)\]", dotAll: true)
      .firstMatch(src);
  return ActivityRulesShape(
    allowedKeys: _quotedList(only.group(1)!),
    requiredKeys: _quotedList(all.group(1)!),
    numberBounds: numberBounds,
    intBounds: intBounds,
    stringPatterns: strings,
    sourceKinds: kinds == null ? const [] : _quotedList(kinds.group(1)!),
  );
}

/// True when [summary] (the map `ActivityCloudSummary` emits) satisfies the
/// parsed rules: allowed keys only, required keys, bounds, int types. Returns
/// the list of violations (empty = the rules would accept it).
List<String> rulesViolations(ActivityRulesShape rules, Map<String, Object?> summary) {
  final out = <String>[];
  for (final k in summary.keys) {
    if (!rules.allowedKeys.contains(k)) out.add('key $k not allowed');
  }
  for (final k in rules.requiredKeys) {
    if (!summary.containsKey(k)) out.add('required key $k missing');
  }
  for (final e in summary.entries) {
    final v = e.value;
    final nb = rules.numberBounds[e.key];
    if (nb != null) {
      if (v is! num || v < nb.min || v > nb.max) out.add('${e.key}=$v outside $nb');
    }
    final ib = rules.intBounds[e.key];
    if (ib != null) {
      if (v is! int || v < ib.min || v > ib.max) out.add('${e.key}=$v outside $ib');
    }
    final sp = rules.stringPatterns[e.key];
    if (sp != null) {
      if (v is! String || !RegExp(sp).hasMatch(v)) out.add('${e.key}=$v bad string');
    }
  }
  final kind = summary['primarySourceKind'];
  if (kind != null && !rules.sourceKinds.contains(kind)) {
    out.add('primarySourceKind=$kind unknown');
  }
  final id = summary['primarySourceId'];
  if (id != null && (id is! String || id.length > 64)) out.add('primarySourceId bad');
  final route = summary['hasRoute'];
  if (route != null && route is! bool) out.add('hasRoute not bool');
  final sport = summary['sport'];
  if (sport is! String || !RegExp(r'^[a-z][A-Za-z0-9]{0,31}$').hasMatch(sport)) {
    out.add('sport=$sport bad');
  }
  return out;
}

/// Keeps `dart:io` referenced for the import in callers that only need paths.
bool get rulesFileExists => File(repoFile('firestore.rules').path).existsSync();
