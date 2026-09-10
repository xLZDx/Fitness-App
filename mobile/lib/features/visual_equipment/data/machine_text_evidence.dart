import 'dart:math' show Point;
import 'dart:ui' show Rect;

/// Structured OCR evidence from a single recognition pass: the full text
/// exactly as [MachineTextRecogniser.readText]/[readFrame] already return,
/// plus every recognised line's geometry.
///
/// Binding design: `MachineTextEvidence` in
/// `core/design/sptr_equipment_recognition_v4_1/
/// SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md`.
/// `fullText` is the same value the legacy String OCR API already returns --
/// this model only adds structure, it never changes what recognition
/// produces. Privacy: `v4.2_REMEDIATED_RC_2026-08-22.md` section 8.5 extends
/// "no raw image in Firestore or logs" to `fullText`/line text explicitly --
/// callers must not log this value; only parsed identity tokens are logged.
class MachineTextEvidence {
  const MachineTextEvidence({required this.fullText, required this.lines});

  final String fullText;
  final List<MachineTextLine> lines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MachineTextEvidence &&
          other.fullText == fullText &&
          _lineListEquals(other.lines, lines));

  @override
  int get hashCode => Object.hash(fullText, Object.hashAll(lines));

  @override
  String toString() =>
      'MachineTextEvidence(fullText: ${fullText.length} chars, '
      'lines: ${lines.length})';
}

/// One recognised line's text and geometry.
///
/// `cornerPoints`, `angle` and `confidence` mirror ML Kit's own fields
/// verbatim rather than inventing a value the platform did not supply:
/// `angle` is Android-only (null on iOS), `confidence` is commonly null
/// on-device (confirmed against the installed
/// `google_mlkit_text_recognition` plugin source).
class MachineTextLine {
  const MachineTextLine({
    required this.text,
    required this.bounds,
    this.cornerPoints,
    this.angle,
    this.confidence,
  });

  final String text;
  final Rect bounds;
  final List<Point<int>>? cornerPoints;
  final double? angle;
  final double? confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MachineTextLine &&
          other.text == text &&
          other.bounds == bounds &&
          _pointListEquals(other.cornerPoints, cornerPoints) &&
          other.angle == angle &&
          other.confidence == confidence);

  @override
  int get hashCode => Object.hash(
        text,
        bounds,
        cornerPoints == null ? null : Object.hashAll(cornerPoints!),
        angle,
        confidence,
      );

  @override
  String toString() =>
      'MachineTextLine(bounds: $bounds, angle: $angle, '
      'confidence: $confidence)';
}

bool _lineListEquals(List<MachineTextLine> a, List<MachineTextLine> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _pointListEquals(List<Point<int>>? a, List<Point<int>>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
