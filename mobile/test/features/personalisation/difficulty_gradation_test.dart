import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F001 — the difficulty field exists; the gradation does not.
///
/// `ExerciseItem.difficulty` is a three-value enum and `sortByTierFit` orders
/// by it, so the machinery for level-based personalisation is all present and
/// tested. What is absent is the DATA: measured against the shipped catalogue,
/// 1877 of 1887 rows are `beginner`. Ten rows carry anything else.
///
/// The consequence is not that the sort is broken — it is that the sort has
/// nothing to sort. An advanced user and a beginner receive the same order,
/// because 99.5% of the pool is one value.
///
/// ## Why this is a copy fix and not a wiring fix
///
/// F001's instruction is explicit that `fitnessProfileProvider` must not be
/// connected somewhere merely to produce a reference count. It is stronger
/// than that here: there is no honest place to connect it. A signal that is
/// constant across 99.5% of its domain cannot improve a decision path, so
/// "real integration" is not one of the available outcomes — the data would
/// have to be graded first, which is a content project, not a code change.
///
/// So the remediation is the other branch: narrow the claim. The equipment
/// suitability card said "Based on your goal and level"; the only input to
/// that card is `rec.hiddenForInjury > 0`, so neither signal was read, and one
/// of them could not have carried information if it had been.
void main() {
  List<Map<String, dynamic>> catalogue() {
    final file = File('assets/data/exercises_vendor.json');
    expect(file.existsSync(), isTrue);
    final rows = <Map<String, dynamic>>[];
    void walk(Object? node) {
      if (node is Map) {
        if (node.containsKey('id') && node.containsKey('steps')) {
          rows.add(Map<String, dynamic>.from(node));
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(jsonDecode(file.readAsStringSync()));
    return rows;
  }

  test('the measurement, so the claim can be revisited when the data changes',
      () {
    final rows = catalogue();
    final byDifficulty = <String, int>{};
    for (final r in rows) {
      final d = (r['difficulty'] as String?) ?? '(absent)';
      byDifficulty[d] = (byDifficulty[d] ?? 0) + 1;
    }

    expect(rows, hasLength(1887),
        reason: 'the catalogue changed; re-measure before trusting the rest');
    expect(byDifficulty['beginner'], 1877);
    expect(byDifficulty['advanced'], 8);
    expect(byDifficulty['intermediate'], 2);

    // The figure the finding turns on, stated as a ratio rather than a count
    // so it survives a catalogue that grows without being graded.
    final graded = rows.length - (byDifficulty['beginner'] ?? 0);
    expect(graded / rows.length, lessThan(0.05),
        reason: 'if this ever rises, level-based personalisation becomes '
            'possible and the narrowed copy below should be revisited — that '
            'is the point of measuring it here rather than asserting a '
            'permanent absence');
  });

  test('the suitability card no longer claims a signal it does not read', () {
    // The card's only input is `rec.hiddenForInjury > 0`. It now says so.
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final ru = jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())
        as Map<String, dynamic>;

    final claim = en['equipmentSuitableBecause'] as String;
    expect(claim.toLowerCase(), isNot(contains('level')));
    expect(claim.toLowerCase(), isNot(contains('goal')));
    expect(claim.toLowerCase(), contains('health'));

    expect(ru['equipmentSuitableBecause'], isNotNull);
    expect((ru['equipmentSuitableBecause'] as String).toLowerCase(),
        isNot(contains('уровн')),
        reason: 'the Russian copy carried the same unsupported claim');
  });

  test('the page really does read only the injury count', () {
    // Pins the premise of the copy change. If the card ever starts reading a
    // goal or a level, the narrowed wording becomes wrong in the other
    // direction and this is where that shows up.
    final src =
        File('lib/features/equipment/equipment_detail_page.dart').readAsStringSync();
    expect(src, contains('final flagged = rec.hiddenForInjury > 0;'));
  });
}
