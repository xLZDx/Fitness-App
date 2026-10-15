/// Per-serving <-> per-100 g scaling of confirmed label values (design s17.6,
/// FOOD-16). Pure Dart.
///
/// The two directions are exact inverses (up to double rounding). A missing,
/// zero, negative or non-finite serving weight never divides: the result
/// carries `scaleMissing` instead (a "Check these" code).
library;

import 'check_these.dart';
import 'food_entry.dart';

/// Outcome of a scaling call.
class LabelScaleResult {
  const LabelScaleResult.ok(Per100g this.values) : issue = null;
  const LabelScaleResult.missing()
      : values = null,
        issue = CheckCode.scaleMissing;

  /// Scaled values, or null when the serving weight is unusable.
  final Per100g? values;

  /// `CheckCode.scaleMissing` when [values] is null.
  final CheckCode? issue;

  bool get isOk => values != null;
}

class LabelScale {
  const LabelScale._();

  static bool _usable(double? servingG) =>
      servingG != null && servingG.isFinite && servingG > 0;

  static Per100g _map(Per100g p, double factor) => Per100g(
        kcal: p.kcal * factor,
        proteinG: p.proteinG * factor,
        carbsG: p.carbsG * factor,
        fatG: p.fatG * factor,
      );

  /// `per100g = perServing * 100 / servingG`.
  static LabelScaleResult toPer100g(Per100g perServing, double? servingG) {
    if (!_usable(servingG)) return const LabelScaleResult.missing();
    return LabelScaleResult.ok(_map(perServing, 100 / servingG!));
  }

  /// `perServing = per100g * servingG / 100`.
  static LabelScaleResult toPerServing(Per100g per100g, double? servingG) {
    if (!_usable(servingG)) return const LabelScaleResult.missing();
    return LabelScaleResult.ok(_map(per100g, servingG! / 100));
  }
}
