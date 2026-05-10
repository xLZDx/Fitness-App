import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';

void main() {
  group('normaliseAndTopK', () {
    test('drops below-threshold candidates', () {
      final out = normaliseAndTopK([
        const VisualMatch(equipmentId: 'a', confidence: 0.8),
        const VisualMatch(equipmentId: 'b', confidence: 0.05),
      ]);
      expect(out.length, 1);
      expect(out.first.equipmentId, 'a');
    });

    test('renormalises so confidences sum to 1', () {
      final out = normaliseAndTopK([
        const VisualMatch(equipmentId: 'a', confidence: 0.6),
        const VisualMatch(equipmentId: 'b', confidence: 0.3),
        const VisualMatch(equipmentId: 'c', confidence: 0.1),
      ]);
      final sum = out.fold<double>(0, (a, b) => a + b.confidence);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('limit caps the result count', () {
      final out = normaliseAndTopK(
        List.generate(
            10, (i) => VisualMatch(equipmentId: 'eq$i', confidence: 0.5)),
        limit: 2,
      );
      expect(out.length, 2);
    });

    test('all-below-threshold returns empty', () {
      final out = normaliseAndTopK(const [
        VisualMatch(equipmentId: 'a', confidence: 0.05),
      ]);
      expect(out, isEmpty);
    });
  });
}
