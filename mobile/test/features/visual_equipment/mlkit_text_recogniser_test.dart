import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';

/// Builds a real `mlkit.RecognizedText` the same shape ML Kit itself would
/// return, using the plugin's own public constructors -- no platform channel
/// involved, since only `TextRecognizer.processImage` touches one.
mlkit.RecognizedText _recognizedText({
  required String fullText,
  required List<mlkit.TextLine> lines,
}) =>
    mlkit.RecognizedText(
      text: fullText,
      blocks: [
        mlkit.TextBlock(
          text: fullText,
          lines: lines,
          boundingBox: const Rect.fromLTWH(0, 0, 200, 100),
          recognizedLanguages: const ['en'],
          cornerPoints: const [],
        ),
      ],
    );

mlkit.TextLine _mlkitLine({
  required String text,
  Rect boundingBox = const Rect.fromLTWH(0, 0, 200, 20),
  double? confidence,
  double? angle,
}) =>
    mlkit.TextLine(
      text: text,
      elements: const [],
      boundingBox: boundingBox,
      recognizedLanguages: const ['en'],
      cornerPoints: const [],
      confidence: confidence,
      angle: angle,
    );

void main() {
  group('machineTextEvidenceFromRecognizedText (pure mapping)', () {
    test('fullText is exactly the RecognizedText.text ML Kit returned', () {
      final result = _recognizedText(
        fullText: 'LEG PRESS\nMAX 250 KG',
        lines: [_mlkitLine(text: 'LEG PRESS'), _mlkitLine(text: 'MAX 250 KG')],
      );

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.fullText, 'LEG PRESS\nMAX 250 KG');
    });

    test('flattens every block/line into MachineTextEvidence.lines in order', () {
      final result = _recognizedText(
        fullText: 'A\nB',
        lines: [_mlkitLine(text: 'A'), _mlkitLine(text: 'B')],
      );

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.lines.map((l) => l.text), ['A', 'B']);
    });

    test('an empty RecognizedText.text produces empty fullText and no lines', () {
      final result = _recognizedText(fullText: '', lines: const []);

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.fullText, isEmpty);
      expect(evidence.lines, isEmpty);
    });

    test('passes bounds through unchanged', () {
      final result = _recognizedText(
        fullText: 'X',
        lines: [_mlkitLine(text: 'X', boundingBox: const Rect.fromLTWH(5, 6, 70, 8))],
      );

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.lines.single.bounds, const Rect.fromLTWH(5, 6, 70, 8));
    });

    test('a null confidence/angle (as returned on iOS) stays null, not fabricated', () {
      final result = _recognizedText(
        fullText: 'X',
        lines: [_mlkitLine(text: 'X', confidence: null, angle: null)],
      );

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.lines.single.confidence, isNull);
      expect(evidence.lines.single.angle, isNull);
    });

    test('a present confidence/angle (as returned on Android) passes through unchanged', () {
      final result = _recognizedText(
        fullText: 'X',
        lines: [_mlkitLine(text: 'X', confidence: 0.93, angle: 1.2)],
      );

      final evidence = machineTextEvidenceFromRecognizedText(result);

      expect(evidence.lines.single.confidence, 0.93);
      expect(evidence.lines.single.angle, 1.2);
    });
  });

  group('FakeStructuredTextRecogniser', () {
    test('readStructured returns the seeded evidence and counts the call', () async {
      final evidence = const MachineTextEvidence(fullText: 'LAT PULLDOWN', lines: []);
      final fake = FakeStructuredTextRecogniser(evidence);

      final result = await fake.readStructured('/tmp/whatever.jpg');

      expect(result, same(evidence));
      expect(fake.calls, 1);
    });

    test('readText (legacy) derives from the seeded evidence.fullText', () async {
      final evidence = const MachineTextEvidence(fullText: 'CABLE MACHINE', lines: []);
      final fake = FakeStructuredTextRecogniser(evidence);

      final text = await fake.readText('/tmp/whatever.jpg');

      expect(text, 'CABLE MACHINE');
      expect(fake.calls, 1);
    });

    test('is a MachineTextRecogniser and a StructuredTextRecogniser at once', () {
      final fake =
          FakeStructuredTextRecogniser(const MachineTextEvidence(fullText: '', lines: []));

      expect(fake, isA<MachineTextRecogniser>());
      expect(fake, isA<StructuredTextRecogniser>());
    });
  });

  group('capability probe', () {
    test('FakeMachineTextRecogniser is NOT a StructuredTextRecogniser', () {
      final legacyOnly = FakeMachineTextRecogniser('some text');

      expect(legacyOnly, isNot(isA<StructuredTextRecogniser>()));
    });
  });
}
