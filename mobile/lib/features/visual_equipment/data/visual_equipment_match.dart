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

/// Pure score post-processor. Drops candidates below [minConfidence],
/// renormalises the remaining to sum to 1, and returns the top-[limit].
List<VisualMatch> normaliseAndTopK(
  Iterable<VisualMatch> raw, {
  double minConfidence = 0.10,
  int limit = 3,
}) {
  final filtered = raw.where((m) => m.confidence >= minConfidence).toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final top = filtered.take(limit).toList();
  if (top.isEmpty) return const [];
  final sum = top.fold<double>(0, (a, b) => a + b.confidence);
  return top
      .map((m) => VisualMatch(
            equipmentId: m.equipmentId,
            confidence: sum > 0 ? m.confidence / sum : 0,
            labelHint: m.labelHint,
          ))
      .toList();
}
