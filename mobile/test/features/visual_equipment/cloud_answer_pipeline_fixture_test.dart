import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/data/gemini_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';

/// CR-06. The cloud classifier's mistakes have a DIRECTION: the recorded
/// measurement (`core/ml/eval/eval_results_2026-09-17.json`) shows a real
/// photo of one machine being named as another. A filter keyed on the
/// PREDICTED name (`kKnownUnreliableMachineNames`) cannot catch that -- it only
/// drops an answer that happens to be called "rotary torso machine", which can
/// be a CORRECT answer. What actually protects the user is that no cloud answer
/// can become a confirmed identity (FITAPP-EQUIP-ACC-2026-09-17): every cloud
/// match settles as `alternatives`, is never written to history as the user's
/// machine, and only the user's own pick -- or printed text on the machine --
/// confirms anything.
///
/// So this test keeps TRUE label and PREDICTED label apart and replays every
/// recorded real-photo answer through the production parse + classification
/// path. It does NOT claim accuracy: the 33 photos are the operator's own
/// test set from one session, a historical run, not a holdout and not a
/// market measurement.
EquipmentAliasIndex _index() => EquipmentAliasIndex.fromJson(
      (jsonDecode(File('assets/data/equipment_aliases.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>(),
    );

List<Map<String, dynamic>> _rows() {
  final f = File('../core/ml/eval/eval_results_2026-09-17.json');
  if (!f.existsSync()) {
    throw StateError(
        'the recorded measurement this fixture replays is missing: ${f.path}');
  }
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return (j['results'] as List).cast<Map<String, dynamic>>();
}

void main() {
  final index = _index();
  final rows = _rows();

  test('the fixture is the measurement it claims to be', () {
    expect(rows.length, 33);
    for (final r in rows) {
      expect(r['ground_truth'], isA<String>());
      expect(r['raw_model_output'], isA<Map>());
    }
  });

  test('no recorded cloud answer -- right OR wrong -- is a confirmed identity',
      () {
    var rightAndWrong = {'right': 0, 'wrong': 0};
    for (final r in rows) {
      final raw = jsonEncode(r['raw_model_output']);
      final matches = GeminiVisualEquipmentService.parseResponse(raw, index);
      final result = ScanResult.fromMatches(matches);
      expect(result.outcome, isNot(ScanOutcome.confident),
          reason: '${r['file']}: a cloud answer became confident');
      expect(result.isWorthRemembering, isFalse,
          reason: '${r['file']}: a cloud answer would be filed in history as '
              'the user\'s machine without them choosing it');
      (r['match'] == true) ? rightAndWrong['right'] = rightAndWrong['right']! + 1
          : rightAndWrong['wrong'] = rightAndWrong['wrong']! + 1;
    }
    // The set contains both, so "never confident" was exercised on wrong
    // answers too, which is the whole point.
    expect(rightAndWrong['wrong'], greaterThan(0));
    expect(rightAndWrong['right'], greaterThan(0));
  });

  test('a TRUE rotary torso named as something else is not confirmed either',
      () {
    // The case the predicted-name denylist cannot see: ground truth is the
    // machine the denylist is about, the model names a different one.
    final misnamed = rows.where((r) =>
        (r['ground_truth'] as String).toLowerCase() == 'rotary torso machine' &&
        (r['predicted'] as String?)?.toLowerCase() != 'rotary torso machine');
    expect(misnamed, isNotEmpty,
        reason: 'the recorded set no longer contains the case this guards');
    for (final r in misnamed) {
      final matches = GeminiVisualEquipmentService.parseResponse(
          jsonEncode(r['raw_model_output']), index);
      // It may list candidates (never the true one, per the recorded run) --
      // what matters is the outcome it is allowed to have.
      final result = ScanResult.fromMatches(matches);
      expect(result.outcome,
          anyOf(ScanOutcome.alternatives, ScanOutcome.noEquipment),
          reason: 'a misnamed real rotary torso must not be confirmed');
      expect(result.isWorthRemembering, isFalse);
    }
  });

  test('the predicted-name denylist hides a CORRECT answer too, which is why it '
      'is not the protection', () {
    // A model that names the rotary torso machine correctly is dropped by the
    // denylist. That is a stated trade (see the constant), and this pins it so
    // nobody mistakes the denylist for the control that handles misnaming.
    final matches = GeminiVisualEquipmentService.parseResponse(
        '{"machine": "rotary torso machine", "confidence": 0.9, "alternatives": []}',
        index);
    expect(matches, isEmpty);
  });

  test('true and predicted labels are tallied separately and agree with the '
      'recorded summary', () {
    final j = jsonDecode(
            File('../core/ml/eval/eval_results_2026-09-17.json').readAsStringSync())
        as Map<String, dynamic>;
    final correct = rows.where((r) => r['match'] == true).length;
    expect(correct, j['correct_all']);
    // Confusion pairs (true -> predicted) among the wrong answers: every one
    // is a case where true != predicted, so a rule on predicted alone is
    // insufficient by construction.
    final wrong = rows.where((r) => r['match'] != true).toList();
    expect(wrong, isNotEmpty);
    for (final r in wrong) {
      expect((r['ground_truth'] as String).toLowerCase(),
          isNot((r['predicted'] as String? ?? '').toLowerCase()));
    }
  });
}
