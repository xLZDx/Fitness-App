import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';

void main() {
  group('rankTopK', () {
    test('drops below-threshold candidates', () {
      final out = rankTopK([
        const VisualMatch(equipmentId: 'a', confidence: 0.8),
        const VisualMatch(equipmentId: 'b', confidence: 0.05),
      ]);
      expect(out.length, 1);
      expect(out.first.equipmentId, 'a');
    });

    test('confidences are the model scores, NOT renormalised', () {
      // THE regression test for "две скамейки → treadmill, уверенность 100%"
      // (operator screenshot 2026-07-30 14:32). The old post-processor divided
      // survivors by their sum, so a lone weak match — the only label that
      // mapped onto the catalog — was displayed as certainty.
      final lone = rankTopK([
        const VisualMatch(equipmentId: 'treadmill', confidence: 0.22),
      ]);
      expect(lone.single.confidence, closeTo(0.22, 1e-9),
          reason: 'a lone 22% match must be shown as 22%, never 100%');

      final several = rankTopK([
        const VisualMatch(equipmentId: 'a', confidence: 0.6),
        const VisualMatch(equipmentId: 'b', confidence: 0.3),
      ]);
      expect(several[0].confidence, closeTo(0.6, 1e-9));
      expect(several[1].confidence, closeTo(0.3, 1e-9));
    });

    test('sorts best-first', () {
      final out = rankTopK(const [
        VisualMatch(equipmentId: 'low', confidence: 0.3),
        VisualMatch(equipmentId: 'high', confidence: 0.9),
      ]);
      expect(out.map((m) => m.equipmentId), ['high', 'low']);
    });

    test('limit caps the result count', () {
      final out = rankTopK(
        List.generate(
            10, (i) => VisualMatch(equipmentId: 'eq$i', confidence: 0.5)),
        limit: 2,
      );
      expect(out.length, 2);
    });

    test('all-below-threshold returns empty', () {
      final out = rankTopK(const [
        VisualMatch(equipmentId: 'a', confidence: 0.05),
      ]);
      expect(out, isEmpty);
    });
  });
}
