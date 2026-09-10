import 'dart:math' show Point;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';

MachineTextLine _line({
  String text = 'LEG PRESS',
  Rect bounds = const Rect.fromLTWH(0, 0, 100, 20),
  List<Point<int>>? cornerPoints,
  double? angle,
  double? confidence,
}) =>
    MachineTextLine(
      text: text,
      bounds: bounds,
      cornerPoints: cornerPoints,
      angle: angle,
      confidence: confidence,
    );

void main() {
  group('MachineTextEvidence construction', () {
    test('holds fullText and lines exactly as constructed', () {
      final evidence = MachineTextEvidence(
        fullText: 'LEG PRESS\n250 KG MAX',
        lines: [_line(text: 'LEG PRESS'), _line(text: '250 KG MAX')],
      );

      expect(evidence.fullText, 'LEG PRESS\n250 KG MAX');
      expect(evidence.lines, hasLength(2));
      expect(evidence.lines[0].text, 'LEG PRESS');
      expect(evidence.lines[1].text, '250 KG MAX');
    });

    test('accepts an empty lines list for a fullText-only reading', () {
      const evidence = MachineTextEvidence(fullText: '', lines: []);

      expect(evidence.fullText, '');
      expect(evidence.lines, isEmpty);
    });
  });

  group('MachineTextLine optional ML Kit fields', () {
    test('cornerPoints, angle and confidence default to null', () {
      final line = _line();

      expect(line.cornerPoints, isNull);
      expect(line.angle, isNull);
      expect(line.confidence, isNull);
    });

    test('carries cornerPoints, angle and confidence when ML Kit supplies them', () {
      final line = _line(
        cornerPoints: const [Point(0, 0), Point(100, 0), Point(100, 20), Point(0, 20)],
        angle: 1.5,
        confidence: 0.87,
      );

      expect(line.cornerPoints, hasLength(4));
      expect(line.angle, 1.5);
      expect(line.confidence, 0.87);
    });
  });

  group('MachineTextEvidence equality', () {
    test('two evidences with identical fullText and lines are equal', () {
      final a = MachineTextEvidence(fullText: 'X', lines: [_line()]);
      final b = MachineTextEvidence(fullText: 'X', lines: [_line()]);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a different fullText makes two evidences unequal', () {
      final a = MachineTextEvidence(fullText: 'X', lines: [_line()]);
      final b = MachineTextEvidence(fullText: 'Y', lines: [_line()]);

      expect(a, isNot(equals(b)));
    });

    test('a different line list makes two evidences unequal', () {
      final a = MachineTextEvidence(fullText: 'X', lines: [_line(text: 'A')]);
      final b = MachineTextEvidence(fullText: 'X', lines: [_line(text: 'B')]);

      expect(a, isNot(equals(b)));
    });

    test('a different line count makes two evidences unequal', () {
      final a = MachineTextEvidence(fullText: 'X', lines: [_line()]);
      final b = MachineTextEvidence(fullText: 'X', lines: [_line(), _line()]);

      expect(a, isNot(equals(b)));
    });
  });

  group('MachineTextLine equality', () {
    test('two lines with identical fields are equal', () {
      final a = _line(angle: 2.0, confidence: 0.5);
      final b = _line(angle: 2.0, confidence: 0.5);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a different bounds rect makes two lines unequal', () {
      final a = _line(bounds: const Rect.fromLTWH(0, 0, 100, 20));
      final b = _line(bounds: const Rect.fromLTWH(0, 0, 200, 20));

      expect(a, isNot(equals(b)));
    });

    test('a null confidence is distinct from a present one, not treated the same', () {
      final withConfidence = _line(confidence: 0.9);
      final withoutConfidence = _line(confidence: null);

      expect(withConfidence, isNot(equals(withoutConfidence)));
    });

    test('a null angle is distinct from a present one, not treated the same', () {
      final withAngle = _line(angle: 0.3);
      final withoutAngle = _line(angle: null);

      expect(withAngle, isNot(equals(withoutAngle)));
    });

    test('different cornerPoints lists make two lines unequal', () {
      final a = _line(cornerPoints: const [Point(0, 0)]);
      final b = _line(cornerPoints: const [Point(1, 1)]);

      expect(a, isNot(equals(b)));
    });

    test('one null cornerPoints and one present list are unequal', () {
      final a = _line(cornerPoints: null);
      final b = _line(cornerPoints: const [Point(0, 0)]);

      expect(a, isNot(equals(b)));
      expect(b, isNot(equals(a)));
    });
  });
}
