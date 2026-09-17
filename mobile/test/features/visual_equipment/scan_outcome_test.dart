import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';

/// R2.2 states 6-11. `ScanResult` exists because an
/// `AsyncValue<List<VisualMatch>>` collapses four different endings into
/// "empty list": nothing matched, nothing matched AND nothing could be named,
/// and — because the call was unbounded — a request that never returned had no
/// representation at all.
void main() {
  group('ScanResult.fromMatches', () {
    // FITAPP-EQUIP-ACC-2026-09-17: a single candidate and a wide top1/top2
    // margin used to both mean "confident". Measurement (48.5% live top-1 on
    // 33 real gym photos, core/ml/eval/eval_results_2026-09-17.json) showed
    // neither signal separates a correct answer from a confident-sounding
    // wrong one, so every non-empty match list now settles as alternatives.
    test('a clear leader is still alternatives, not confident', () {
      final r = ScanResult.fromMatches(const [
        VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
        VisualMatch(equipmentId: 'squat_rack', confidence: 0.2),
      ]);
      expect(r.outcome, ScanOutcome.alternatives);
      expect(r.matches.first.equipmentId, 'leg_press');
    });

    test('a close field is alternatives, not a silent pick of the first', () {
      // The rule this pins: never convert an uncertain result into one
      // deterministic answer. 0.05 apart is not a decision.
      final r = ScanResult.fromMatches(const [
        VisualMatch(equipmentId: 'leg_press', confidence: 0.45),
        VisualMatch(equipmentId: 'hack_squat', confidence: 0.40),
        VisualMatch(equipmentId: 'smith_machine', confidence: 0.35),
      ]);
      expect(r.outcome, ScanOutcome.alternatives);
      expect(r.matches, hasLength(3));
    });

    test('a lone match is alternatives with nothing to compare against', () {
      final r = ScanResult.fromMatches(
          const [VisualMatch(equipmentId: 'leg_press', confidence: 0.3)]);
      expect(r.outcome, ScanOutcome.alternatives);
    });

    test('no matches never resolves to unknown on its own', () {
      // The caller must ask the describer before deciding between "not in our
      // catalogue" and "no machine in this frame" — this factory cannot know.
      expect(ScanResult.fromMatches(const []).outcome, ScanOutcome.noEquipment);
    });
  });

  group('ScanResult.isWorthRemembering', () {
    // R2.6. This rule lives on the result, not as an `if` inside the page,
    // because the page's capture path needs a real camera file and cannot be
    // driven from a host widget test. Two widget tests written against the
    // inline version passed by writing nothing at all — the wrong reason —
    // which is what moved the rule here.
    test('a confident answer is remembered', () {
      expect(
          ScanResult.confident(const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]).isWorthRemembering,
          isTrue);
    });

    test('an undecided answer is NOT remembered', () {
      // "I am not sure, you pick" must not become "you identified this".
      expect(
          ScanResult.alternatives(const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.45),
            VisualMatch(equipmentId: 'hack_squat', confidence: 0.40),
          ]).isWorthRemembering,
          isFalse);
    });

    test('nothing without an identified machine is remembered', () {
      for (final r in [
        const ScanResult.unknown(),
        const ScanResult.noEquipment(),
        const ScanResult.timeout(),
        const ScanResult.failed(),
      ]) {
        expect(r.isWorthRemembering, isFalse, reason: '${r.outcome}');
      }
    });
  });

  group('ScanResult.isRetryable', () {
    test('timeout and failure are worth a second attempt', () {
      expect(const ScanResult.timeout().isRetryable, isTrue);
      expect(const ScanResult.failed().isRetryable, isTrue);
    });

    test('unknown is NOT retryable', () {
      // The same image through the same model returns the same "not in the
      // catalogue". A retry button here would be a loop with a friendly label.
      expect(const ScanResult.unknown().isRetryable, isFalse);
    });

    test('an answered scan offers no retry', () {
      expect(
          const ScanResult(outcome: ScanOutcome.confident).isRetryable, isFalse);
      expect(const ScanResult(outcome: ScanOutcome.alternatives).isRetryable,
          isFalse);
      expect(const ScanResult.noEquipment().isRetryable, isFalse);
    });
  });
  group('an on-device answer is never settled', () {
    // B1 measured this model against 30 real gym photos: its three most
    // confident answers were all wrong, and all three were machines it has no
    // class for -- an abduction machine at treadmill 0.892, a shoulder press
    // at leg_press 0.897, an abdominal machine at treadmill 0.742. A gate on
    // the score cannot catch that, so the degradation is on the SOURCE.
    test('a lone offline match is alternatives, not confident', () {
      final r = ScanResult.fromMatches(
        const [VisualMatch(equipmentId: 'treadmill', confidence: 0.892)],
        answeredOffline: true,
      );
      expect(r.outcome, ScanOutcome.alternatives);
      expect(r.answeredOffline, isTrue);
    });

    test('a runaway offline lead is still alternatives', () {
      // 0.892 vs 0.032 -- the real numbers from the abduction machine. The
      // margin rule would call this settled with room to spare.
      final r = ScanResult.fromMatches(
        const [
          VisualMatch(equipmentId: 'treadmill', confidence: 0.892),
          VisualMatch(equipmentId: 'cable_machine', confidence: 0.032),
        ],
        answeredOffline: true,
      );
      expect(r.outcome, ScanOutcome.alternatives,
          reason: 'a 0.86 lead from a 10-class model is not an identification');
    });

    test('an offline answer is never remembered as a saved machine', () {
      final r = ScanResult.fromMatches(
        const [VisualMatch(equipmentId: 'treadmill', confidence: 0.95)],
        answeredOffline: true,
      );
      expect(r.isWorthRemembering, isFalse,
          reason: 'the fallback must not file a machine identity');
    });

    test('the cloud path is alternatives too, same as offline', () {
      // FITAPP-EQUIP-ACC-2026-09-17: this used to be the control proving the
      // online and offline paths diverge. They no longer do -- neither path
      // is trusted to settle on one answer until a real end-to-end
      // measurement of the production (cloud) path exists.
      final r = ScanResult.fromMatches(
        const [
          VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          VisualMatch(equipmentId: 'bench', confidence: 0.1),
        ],
      );
      expect(r.outcome, ScanOutcome.alternatives);
      expect(r.isWorthRemembering, isFalse);
    });
  });

}
