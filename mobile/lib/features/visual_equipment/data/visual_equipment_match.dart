/// TX.2 — Photo-based equipment recognition.
///
/// When the user takes a photo of a machine, an on-device classifier
/// returns the top-K candidate equipmentIds. We persist the user's
/// pick + (optional) ground-truth label so we can retrain.
class VisualMatch {
  const VisualMatch({
    required this.equipmentId,
    required this.confidence,
    this.labelHint,
  });

  final String equipmentId;
  final double confidence;
  final String? labelHint;
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
