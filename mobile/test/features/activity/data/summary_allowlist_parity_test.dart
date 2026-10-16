// S02-01 U06: the summary allowlist and bounds in Dart equal the ones parsed
// out of firestore.rules.
import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/firestore_rules_parser.dart';
import '../../../support/synthetic_activity_corpus.dart';

/// Differences between the Dart vocabulary and a parsed rules shape.
List<String> parityDiff(ActivityRulesShape r) {
  final out = <String>[];
  final dart = kSummaryAllowedKeys;
  for (final k in dart) {
    if (!r.allowedKeys.contains(k)) out.add('Dart key $k missing from hasOnly');
  }
  for (final k in r.allowedKeys) {
    if (!dart.contains(k)) out.add('rules key $k unknown to Dart');
  }
  if (r.requiredKeys.toSet().difference(kSummaryRequiredKeys.toSet()).isNotEmpty ||
      kSummaryRequiredKeys.toSet().difference(r.requiredKeys.toSet()).isNotEmpty) {
    out.add('required keys differ: ${r.requiredKeys} vs $kSummaryRequiredKeys');
  }
  for (final e in kSummaryNumericBounds.entries) {
    final b = r.numberBounds[e.key];
    if (b == null) {
      out.add('no numeric bound for ${e.key} in the rules');
    } else if (b.min != e.value.min || b.max != e.value.max) {
      out.add('${e.key}: Dart ${e.value.min}..${e.value.max} vs rules $b');
    }
  }
  for (final e in kSummaryIntBounds.entries) {
    final b = r.intBounds[e.key];
    if (b == null) {
      out.add('no int bound for ${e.key} in the rules');
    } else if (b.min != e.value.min || b.max != e.value.max) {
      out.add('${e.key}: Dart ${e.value.min}..${e.value.max} vs rules $b');
    }
  }
  for (final k in r.numberBounds.keys) {
    if (!kSummaryNumericBounds.containsKey(k)) out.add('rules number key $k unknown to Dart');
  }
  return out;
}

void main() {
  final rules = parseActivityRules();

  test('the parser sees the real rules (guard on the instrument)', () {
    expect(rules.allowedKeys.length, 32);
    expect(rules.requiredKeys, containsAll(['schema', 'sport', 'startUtc', 'endUtc', 'rev']));
    expect(rules.numberBounds['distanceM'], const RulesBound(0, 10000000));
    expect(rules.intBounds['userEditCount'], const RulesBound(0, 64));
    expect(rules.intBounds['rev'], const RulesBound(1, 1000000));
    expect(rules.sourceKinds, hasLength(5));
  });

  test('every Dart key and bound equals the rules, both directions', () {
    expect(parityDiff(rules), isEmpty);
  });

  test('the required list contains rev and every summary carries it', () {
    expect(rules.requiredKeys, contains('rev'));
    final c = SyntheticCorpus.build();
    for (final s in c.valid) {
      expect(ActivityCloudSummary.fromSession(s).containsKey('rev'), isTrue);
    }
  });

  test('negative controls: a key added to Dart only, or removed from the rules, '
      'or a loosened bound is detected', () {
    final text = readRulesText();
    final noRev = parseActivityRules(text.replaceFirst("'rev', 'updatedAt'])", "'updatedAt'])"));
    expect(parityDiff(noRev), contains('Dart key rev missing from hasOnly'));
    final loose = parseActivityRules(
        text.replaceFirst("actNumOk(d, 'distanceM', 0, 10000000)", "actNumOk(d, 'distanceM', 0, 20000000)"));
    expect(parityDiff(loose).any((d) => d.contains('distanceM')), isTrue);
    final noCount = parseActivityRules(
        text.replaceFirst("actIntOk(d, 'userEditCount', 0, 64)", "actIntOk(d, 'userEditCount', 0, 65)"));
    expect(parityDiff(noCount).any((d) => d.contains('userEditCount')), isTrue);
  });

  test('the maximum the generator emits for each numeric key reaches but never '
      'exceeds the rules bound', () {
    final c = SyntheticCorpus.build();
    final sums = [for (final s in c.valid) ActivityCloudSummary.fromSession(s)];
    final maxed = ActivityCloudSummary.fromSession(c.byId(c.edgeCases['E-11:max']!));
    for (final e in rules.numberBounds.entries) {
      var top = 0.0;
      for (final s in sums) {
        final v = s[e.key];
        if (v != null && (v as num) > top) top = v.toDouble();
      }
      expect(top, lessThanOrEqualTo(e.value.max), reason: e.key);
      expect(maxed[e.key], e.value.max, reason: '${e.key} at its rules maximum');
    }
    for (final s in sums) {
      expect(rulesViolations(rules, s), isEmpty);
    }
    expect(maxed['userEditCount'], isNotNull);
  });
}
