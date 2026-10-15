/// Where a food item's nutrition numbers came from (design s17.3, s17.9).
/// Pure Dart, no Flutter imports.
library;

/// The source tag carried by every [FoodItem]. `off` = Open Food Facts,
/// `usda` = USDA FoodData Central, `llmEstimate` = the model's own per-100 g
/// values (never presented as database facts).
enum FoodSource {
  off('open_food_facts', 'Open Food Facts', 'off'),
  usda('usda_fdc', 'USDA FoodData Central', 'usda'),
  llmEstimate('llm_estimate', 'Estimate', 'llm_estimate'),
  user('user', 'Your own food', 'user'),
  label('label_ocr', 'Nutrition label', 'label');

  const FoodSource(this.wireId, this.attributionName, this.tag);

  /// The value stored in `FoodItem.sourceId`.
  final String wireId;

  /// Human-readable provider name used by the source badge and the
  /// data-sources page. Not localised here; UI maps by [tag].
  final String attributionName;

  /// Short stable tag (`off | usda | llm_estimate | user | label`).
  final String tag;

  /// True when the numbers are an estimate and the UI must say so plainly.
  bool get isEstimate => this == FoodSource.llmEstimate;

  /// True when the source requires attribution (ODbL / CC0 credit).
  bool get requiresAttribution =>
      this == FoodSource.off || this == FoodSource.usda;

  /// Strict parse of a stored `sourceId`; null when unknown.
  static FoodSource? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final s in FoodSource.values) {
      if (s.wireId == raw) return s;
    }
    return null;
  }
}
