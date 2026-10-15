/// "Check these" chips for a food entry (design s17.10): a CLOSED list of
/// codes, each with one concrete resolution action. Pure Dart.
///
/// The oil-amount maths lives in `portion_math.dart` (it needs `FoodItem`);
/// this file has no dependency on the entry model so `food_entry.dart` can
/// import it without a cycle.
library;

/// The eleven closed codes. Unknown codes read from storage or a server
/// response are DROPPED, never displayed (provider free text is never shown).
enum CheckCode {
  portionUnclear,
  hiddenIngredients,
  liquidUnknown,
  cookingMethod,
  multipleItems,
  brandUnknown,
  foodNotMatched,
  lowConfidenceItem,
  labelAmbiguous,
  dataInconsistent,
  scaleMissing;

  /// Strict parse; null for an unknown code.
  static CheckCode? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final c in CheckCode.values) {
      if (c.name == raw) return c;
    }
    return null;
  }

  /// The concrete resolution the chip opens.
  CheckResolution get resolution => switch (this) {
        CheckCode.portionUnclear => CheckResolution.adjustPortion,
        CheckCode.hiddenIngredients => CheckResolution.chooseOilAmount,
        CheckCode.liquidUnknown => CheckResolution.chooseLiquid,
        CheckCode.cookingMethod => CheckResolution.chooseCookingMethod,
        CheckCode.multipleItems => CheckResolution.reviewItems,
        CheckCode.brandUnknown => CheckResolution.pickAnotherFood,
        CheckCode.foodNotMatched => CheckResolution.pickAnotherFood,
        CheckCode.lowConfidenceItem => CheckResolution.pickAnotherFood,
        CheckCode.labelAmbiguous => CheckResolution.editLabelNumbers,
        CheckCode.dataInconsistent => CheckResolution.editLabelNumbers,
        CheckCode.scaleMissing => CheckResolution.enterServingWeight,
      };
}

/// What a chip opens. UI maps each to a small sheet.
enum CheckResolution {
  adjustPortion,
  chooseOilAmount,
  chooseLiquid,
  chooseCookingMethod,
  reviewItems,
  pickAnotherFood,
  editLabelNumbers,
  enterServingWeight,
}

/// Oil amount offered for `hiddenIngredients`: none, 1 tsp (5 g), 1 tbsp (14 g)
/// of oil from the generic table.
enum OilChoice {
  none(0),
  teaspoon(5),
  tablespoon(14);

  const OilChoice(this.grams);
  final double grams;
}

/// One chip on an entry: `{code, resolved}`.
class CheckItem {
  const CheckItem({required this.code, this.resolved = false});

  final CheckCode code;
  final bool resolved;

  CheckItem resolve() => CheckItem(code: code, resolved: true);

  Map<String, dynamic> toJson() => {'code': code.name, 'resolved': resolved};

  /// Null when the code is not in the closed list.
  static CheckItem? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = CheckCode.tryParse(raw['code']);
    if (code == null) return null;
    return CheckItem(code: code, resolved: raw['resolved'] == true);
  }
}

/// Pure helpers over a chip list.
class CheckThese {
  const CheckThese._();

  /// Hard cap per entry (rules: `checkThese` size <= 8; UI shows at most 8).
  static const int maxChips = 8;

  /// Builds a de-duplicated chip list from codes (first occurrence wins),
  /// capped at [maxChips]. Unresolved by default.
  static List<CheckItem> fromCodes(Iterable<CheckCode> codes) {
    final seen = <CheckCode>{};
    final out = <CheckItem>[];
    for (final c in codes) {
      if (out.length >= maxChips) break;
      if (seen.add(c)) out.add(CheckItem(code: c));
    }
    return out;
  }

  /// Parses a stored/server list: unknown codes and non-map rows dropped,
  /// duplicates collapsed (resolved wins), capped at [maxChips].
  static List<CheckItem> parseList(Object? raw) {
    if (raw is! List) return const [];
    final order = <CheckCode>[];
    final resolved = <CheckCode, bool>{};
    for (final row in raw) {
      final item = CheckItem.tryFromJson(row);
      if (item == null) continue;
      if (!resolved.containsKey(item.code)) order.add(item.code);
      resolved[item.code] = (resolved[item.code] ?? false) || item.resolved;
    }
    return [
      for (final c in order.take(maxChips))
        CheckItem(code: c, resolved: resolved[c] ?? false),
    ];
  }

  /// Marks [code] resolved; other chips untouched. Absent code: unchanged.
  static List<CheckItem> markResolved(List<CheckItem> items, CheckCode code) =>
      [for (final i in items) i.code == code ? i.resolve() : i];

  /// Chips still needing attention.
  static List<CheckItem> unresolved(List<CheckItem> items) =>
      [for (final i in items) if (!i.resolved) i];
}
