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
    test('a clear leader is confident', () {
      final r = ScanResult.fromMatches(const [
        VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
        VisualMatch(equipmentId: 'squat_rack', confidence: 0.2),
      ]);
      expect(r.outcome, ScanOutcome.confident);
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

    test('the margin is the boundary, and it is inclusive', () {
      final atMargin = ScanResult.fromMatches([
        const VisualMatch(equipmentId: 'a', confidence: 0.50),
        VisualMatch(
            equipmentId: 'b', confidence: 0.50 - ScanResult.confidentMargin),
      ]);
      expect(atMargin.outcome, ScanOutcome.confident);

      final justUnder = ScanResult.fromMatches([
        const VisualMatch(equipmentId: 'a', confidence: 0.50),
        VisualMatch(
            equipmentId: 'b',
            confidence: 0.50 - ScanResult.confidentMargin + 0.01),
      ]);
      expect(justUnder.outcome, ScanOutcome.alternatives);
    });

    test('a lone match is confident with nothing to compare against', () {
      final r = ScanResult.fromMatches(
          const [VisualMatch(equipmentId: 'leg_press', confidence: 0.3)]);
      expect(r.outcome, ScanOutcome.confident);
    });

    test('no matches never resolves to unknown on its own', () {
      // The caller must ask the describer before deciding between "not in our
      // catalogue" and "no machine in this frame" — this factory cannot know.
      expect(ScanResult.fromMatches(const []).outcome, ScanOutcome.noEquipment);
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
}
