/// PORT through which the weekly review reads the smoothed body-fat trend
/// without `nutrition_plan` importing `body_scan` (D-71). Pure Dart, no
/// Flutter imports. The implementation lives in the body_scan feature and is
/// bound at the app root; the safe default reports no usable trend, so an
/// unwired app simply never applies the recomposition rule.
library;

/// What the review needs to know about the body-fat trend.
class BodyFatTrendInput {
  const BodyFatTrendInput({
    required this.meaningful,
    required this.changePts,
    required this.modelId,
    this.provisional = false,
    this.seriesChanged = false,
  });

  /// The 4-week trend change exceeds the noise threshold (design 12.3).
  final bool meaningful;

  /// Smoothed change in percentage points over the trend window; negative
  /// means body fat went down.
  final double changePts;

  /// The estimator id the series was measured with (traceability only).
  final String modelId;

  /// The active series comes from the provisional estimator.
  final bool provisional;

  /// The estimator changed inside the window, so no comparison is valid
  /// (D-54).
  final bool seriesChanged;

  /// True only for a meaningful DOWNWARD change on a trustworthy series: a
  /// provisional estimator or a changed model is ignored (D-54, D-71).
  bool get isMeaningfulDecrease =>
      meaningful && changePts < 0 && !provisional && !seriesChanged;

  static const none = BodyFatTrendInput(
    meaningful: false,
    changePts: 0,
    modelId: '',
  );
}

/// Supplies the current trend, or null when there is none.
abstract class BodyFatTrendSource {
  const BodyFatTrendSource();

  BodyFatTrendInput? currentTrend();
}

/// The safe default: no trend.
class NoBodyFatTrendSource extends BodyFatTrendSource {
  const NoBodyFatTrendSource();

  @override
  BodyFatTrendInput? currentTrend() => null;
}
