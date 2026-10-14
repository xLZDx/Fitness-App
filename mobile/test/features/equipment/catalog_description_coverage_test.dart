import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A ratchet on how much of the shipped catalogue can be missing its
/// description — requested by the operator after finding an exercise whose
/// "How to do it" card was empty on their phone (2026-08-12).
///
/// Every exercise ships with steps and a summary, so the allowance is zero.
/// The vendor's own sheet was ~79% filled, and the rows it left empty have since
/// been authored; a row that loses its text again
/// lands here with the new count in the message.
///
/// A second ratchet below covers `purpose`: every row has one except the
/// quarantined `ea_major_groups_muscle_body`, which is not an exercise.
/// Both fields are re-applied after every catalogue build by
/// `scripts/catalog/catalog_corrections.py`.
const int _kMaxMissing = 0;

/// Guards the ratchet from the other direction: a build that DROPS rows would
/// otherwise lower the missing count and look like an improvement.
const int _kMinTotal = 1887;

void main() {
  test('catalogue description coverage does not regress', () {
    // `flutter test` runs with the package root as the working directory.
    final file = File('assets/data/exercises_vendor.json');
    expect(file.existsSync(), isTrue,
        reason: 'the shipped catalogue is what the app actually reads; a test '
            'against a fixture would not have caught this');

    final rows = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    bool blank(Map<String, dynamic> r) {
      final steps = (r['steps'] as List?) ?? const [];
      final summary = (r['summary'] as String? ?? '').trim();
      return steps.isEmpty && summary.isEmpty;
    }

    final missing = rows.where(blank).toList();

    expect(rows.length, greaterThanOrEqualTo(_kMinTotal),
        reason: 'rows disappeared; a smaller catalogue can pass the missing '
            'count below without a single description being written');

    expect(missing.length, lessThanOrEqualTo(_kMaxMissing),
        reason: '${missing.length} exercises now ship with neither steps nor '
            'summary, up from $_kMaxMissing. Example: '
            '${missing.take(3).map((r) => r['id']).join(', ')}');
  });

  test('summary and steps are empty on the same rows', () {
    // The premise the UI fix rests on: `ExerciseStepsCard` decides it has
    // nothing to show by checking BOTH, and that is only equivalent to
    // checking one because every builder sets `summary = steps[0]`. If a
    // future source fills one without the other, the card's logic needs
    // revisiting — and this is where that shows up.
    final rows = (jsonDecode(
      File('assets/data/exercises_vendor.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();

    final noSteps = rows
        .where((r) => ((r['steps'] as List?) ?? const []).isEmpty)
        .map((r) => r['id'] as String)
        .toSet();
    final noSummary = rows
        .where((r) => (r['summary'] as String? ?? '').trim().isEmpty)
        .map((r) => r['id'] as String)
        .toSet();

    expect(noSteps, equals(noSummary));
  });

  test('every exercise except the quarantined one has a purpose, en and ru', () {
    final rows = (jsonDecode(
      File('assets/data/exercises_vendor.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();
    final ru = jsonDecode(
      File('assets/data/exercises_vendor.ru.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    bool blank(Object? v) => v == null || (v is String && v.trim().isEmpty);

    final noPurpose = rows.where((r) => blank(r['purpose'])).map((r) => r['id']);
    expect(noPurpose.toList(), ['ea_major_groups_muscle_body']);

    final noRu = rows
        .where((r) => !blank(r['purpose']))
        .where((r) => blank((ru[r['id']] as Map<String, dynamic>?)?['purpose']))
        .map((r) => r['id'])
        .toList();
    expect(noRu, isEmpty, reason: 'Russian purpose missing for $noRu');
  });
}
