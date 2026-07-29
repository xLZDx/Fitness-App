import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/live_recognition.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';

VisualMatch _m(String id, double c) =>
    VisualMatch(equipmentId: id, confidence: c);

void main() {
  group('RecognitionSmoother', () {
    test('stays silent until the window is full', () {
      final s = RecognitionSmoother(window: 5);
      for (var i = 0; i < 4; i++) {
        expect(s.add(_m('treadmill', 0.9)), isNull);
      }
      expect(s.add(_m('treadmill', 0.9)), isNotNull);
    });

    test('reports the majority label with mean confidence and agreement', () {
      final s = RecognitionSmoother(window: 4, minAgreement: 0.5);
      s.add(_m('treadmill', 0.8));
      s.add(_m('bench', 0.9));
      s.add(_m('treadmill', 0.6));
      final r = s.add(_m('treadmill', 0.7));

      expect(r, isNotNull);
      expect(r!.equipmentId, 'treadmill');
      expect(r.agreement, 0.75);
      expect(r.confidence, closeTo(0.7, 1e-9));
    });

    test('a flickering camera reports nothing rather than guessing', () {
      // Four different labels: nothing reaches a majority.
      final s = RecognitionSmoother(window: 4, minAgreement: 0.5);
      s.add(_m('treadmill', 0.9));
      s.add(_m('bench', 0.9));
      s.add(_m('leg_press', 0.9));
      expect(s.add(_m('barbell', 0.9)), isNull);
    });

    test('a confident-looking but weak majority is rejected', () {
      final s = RecognitionSmoother(window: 4, minConfidence: 0.5);
      s.add(_m('bench', 0.2));
      s.add(_m('bench', 0.2));
      s.add(_m('bench', 0.2));
      expect(s.add(_m('bench', 0.2)), isNull, reason: 'mean 0.2 < 0.5');
    });

    test('frames with no match at all count against agreement', () {
      final s = RecognitionSmoother(window: 4, minAgreement: 0.75);
      s.add(null);
      s.add(_m('bench', 0.9));
      s.add(null);
      expect(s.add(_m('bench', 0.9)), isNull, reason: 'agreement 0.5 < 0.75');
    });

    test('reset clears the window so a stale label cannot leak', () {
      final s = RecognitionSmoother(window: 2);
      s.add(_m('bench', 0.9));
      s.reset();
      expect(s.add(_m('bench', 0.9)), isNull, reason: 'window restarted');
    });
  });
}
