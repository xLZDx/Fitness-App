import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A ratchet on how much of the shipped catalogue can be missing its
/// description — requested by the operator after finding an exercise whose
/// "How to do it" card was empty on their phone (2026-08-12).
///
/// This does NOT assert that every exercise has a description. 403 of 1,887 do
/// not, and that is the vendor's own gap: their metadata sheet is ~79% filled
/// (`scripts/catalog/build_vendor_catalog.py`, header), every builder derives
/// `summary` as `steps[0]`, and so the two fields are empty on exactly the same
/// rows. Asserting full coverage would be asserting a fact that is false today
/// and can only be made true by authoring 403 technique descriptions — which is
/// content work, not a code change, and not something to invent for a fitness
/// app where a wrong cue is an injury.
///
/// What it asserts is that the number cannot QUIETLY grow. Adding vendor rows
/// without descriptions, or a regression in the build that drops the text for
/// rows that had it, both land here as a failure with the new count in the
/// message. Filling descriptions lowers the number, and lowering [_kMaxMissing]
/// is then part of that change.
const int _kMaxMissing = 403;

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
}
