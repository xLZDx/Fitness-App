/// TX.2 — Photo-based equipment recognition.
///
/// When the user takes a photo of a machine, an on-device classifier
/// returns the top-K candidate equipmentIds. We persist the user's
/// pick + (optional) ground-truth label so we can retrain.
/// Where a match came from. Not decoration: it decides what the UI is allowed
/// to SAY about the match.
///
/// [labelHint] is filled by both sources and means different things in each.
/// From the classifier it is a raw model label (`treadmill`, `bench`); from the
/// text anchor it is a phrase read off the machine (`abduction adduction`).
/// Rendering the first as "read on the machine" would be a straight lie, and
/// nothing in the value itself distinguishes them — hence this field.
enum MatchSource {
  /// A model's guess from the image. `labelHint` is its internal label.
  classifier,

  /// Read from text printed on the machine. `labelHint` is that text, and is
  /// worth showing: an identification the user can check beats one they have
  /// to trust.
  printedText,
}

class VisualMatch {
  const VisualMatch({
    required this.equipmentId,
    required this.confidence,
    this.labelHint,
    this.source = MatchSource.classifier,
  });

  final String equipmentId;
  final double confidence;
  final String? labelHint;

  /// Defaults to [MatchSource.classifier] so every existing call site keeps
  /// its current meaning, and only the anchor has to opt in.
  final MatchSource source;
}

/// Pure score post-processor. Drops candidates below [minConfidence], sorts
/// by confidence, returns the top-[limit] — with their REAL confidences.
///
/// The old version renormalised the survivors to sum to 1. That is how two
/// flat benches were shown as "treadmill, уверенность 100%" (operator
/// screenshot 2026-07-30): treadmill was the only label that mapped onto the
/// catalog, its actual score was a fraction of that, and dividing by the sum
/// inflated it to certainty. A confidence the model never produced must never
/// be displayed.
List<VisualMatch> rankTopK(
  Iterable<VisualMatch> raw, {
  double minConfidence = 0.10,
  int limit = 3,
}) {
  final filtered = raw.where((m) => m.confidence >= minConfidence).toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  return filtered.take(limit).toList();
}
