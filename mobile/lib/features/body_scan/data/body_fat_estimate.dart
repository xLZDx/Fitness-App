/// One body-fat estimate with its range and provenance (design s8, s12).
/// Pure Dart, no Flutter imports.
library;

import 'check_items.dart';

/// How much to trust a single reading. Levels, never percentages.
enum EstimateConfidence {
  low,
  medium,
  high;

  /// One level lower (low stays low).
  EstimateConfidence get lowered => switch (this) {
        EstimateConfidence.high => EstimateConfidence.medium,
        EstimateConfidence.medium => EstimateConfidence.low,
        EstimateConfidence.low => EstimateConfidence.low,
      };

  static EstimateConfidence? byName(Object? name) {
    if (name is! String) return null;
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

class BodyFatEstimate {
  const BodyFatEstimate({
    required this.value,
    required this.low,
    required this.high,
    required this.confidence,
    required this.modelId,
    required this.modelVersion,
    required this.provisional,
    this.checkCodes = const [],
  });

  /// Body fat in percent.
  final double value;
  final double low;
  final double high;
  final EstimateConfidence confidence;
  final String modelId;
  final String modelVersion;

  /// True for the on-device anthropometric placeholder: the UI shows the
  /// provisional banner and hides goal-chasing figures (D-73).
  final bool provisional;
  final List<CheckCode> checkCodes;

  /// Half the range width, the `hw` of the noise and trend formulas.
  double get halfWidth => (high - low) / 2;

  /// Identity of the estimator for series segmentation (D-54).
  String get modelKey => '$modelId|$modelVersion';

  BodyFatEstimate copyWith({
    double? value,
    double? low,
    double? high,
    EstimateConfidence? confidence,
    List<CheckCode>? checkCodes,
  }) =>
      BodyFatEstimate(
        value: value ?? this.value,
        low: low ?? this.low,
        high: high ?? this.high,
        confidence: confidence ?? this.confidence,
        modelId: modelId,
        modelVersion: modelVersion,
        provisional: provisional,
        checkCodes: checkCodes ?? this.checkCodes,
      );

  Map<String, dynamic> toJson() => {
        'bodyFatPct': value,
        'rangeLowPct': low,
        'rangeHighPct': high,
        'confidence': confidence.name,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'provisional': provisional,
        'checkCodes': [for (final c in checkCodes) c.name],
      };

  /// Tolerant read; null when the numbers or ids cannot form an estimate.
  static BodyFatEstimate? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['bodyFatPct'];
    final lo = raw['rangeLowPct'];
    final hi = raw['rangeHighPct'];
    final id = raw['modelId'];
    final ver = raw['modelVersion'];
    if (v is! num || lo is! num || hi is! num) return null;
    if (id is! String || id.isEmpty || ver is! String) return null;
    final value = v.toDouble();
    final low = lo.toDouble();
    final high = hi.toDouble();
    if (!value.isFinite || !low.isFinite || !high.isFinite) return null;
    return BodyFatEstimate(
      value: value,
      low: low,
      high: high,
      confidence:
          EstimateConfidence.byName(raw['confidence']) ?? EstimateConfidence.low,
      modelId: id,
      modelVersion: ver,
      provisional: raw['provisional'] == true,
      checkCodes: parseCheckCodes(raw['checkCodes']),
    );
  }
}
